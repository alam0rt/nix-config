{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.server;
  webuiPort = 8080;
  torrentingPort = 51413;
in {
  networking.firewall.allowedTCPPorts = [torrentingPort];
  networking.firewall.allowedUDPPorts = [torrentingPort];

  # TODO: rename DNS record qbittorrent.<domain> → transmission.<domain> in Cloudflare
  # (DNS change is outside this repo; once done the old record can be removed)
  services.nginx.virtualHosts."transmission.${cfg.domain}" = {
    forceSSL = true;
    useACMEHost = cfg.domain;
    locations."/" = {
      proxyPass = "http://127.0.0.1:${toString webuiPort}";
    };
  };

  services.qbittorrent = {
    enable = true;
    openFirewall = true;
    webuiPort = webuiPort;
    torrentingPort = torrentingPort;
    serverConfig = {
      BitTorrent = {
        "Session\\DefaultSavePath" = "/srv/media/downloads";
        "Session\\TempPath" = "/srv/media/downloads/.incomplete";
        "Session\\TempPathEnabled" = true;

        # Active torrent limits — server has 64 cores and 62GB RAM, can handle many concurrent torrents
        "Session\\MaxActiveDownloads" = 100;
        "Session\\MaxActiveTorrents" = 150;
        "Session\\MaxActiveUploads" = 50;

        # Seeding policy: stop immediately after download (ratio 0, pause action)
        "Session\\GlobalMaxSeedingMinutes" = 5;
        "Session\\MaxRatio" = 0;
        "Session\\MaxRatioAction" = 1; # pause

        # Connection limits — 10GbE can sustain thousands of peers; was 800/40
        "Session\\MaxConnections" = 3000;
        "Session\\MaxConnectionsPerTorrent" = 100;
        "Session\\MaxUploads" = 500;
        "Session\\MaxUploadsPerTorrent" = 20;

        # Disk I/O — 1GB RAM cache reduces ZFS write amplification from small random writes;
        # async I/O threads scaled to core count for concurrent torrent disk access
        "Session\\DiskCacheSize" = 1024; # MiB
        "Session\\DiskCacheTTL" = 60; # seconds
        "Session\\UseOSCache" = false; # let qBt cache handle it, not double-cache via ZFS ARC
        "Session\\CoalesceReadWrite" = true;
        "Session\\AsyncIOThreadsCount" = 16; # matches typical ZFS I/O thread count
        "Session\\FilePoolSize" = 500;

        # Send buffer tuning — larger watermarks reduce CPU wake-ups at 10GbE speeds
        "Session\\SendBufferWatermark" = 1024; # KiB
        "Session\\SendBufferLowWatermark" = 64; # KiB
        "Session\\SendBufferWatermarkFactor" = 250; # %

        "Session\\DeleteTorrentFilesAsDefault" = true;
        "Session\\AnonymousModeEnabled" = false;
        "Session\\BTProtocol" = 0; # both TCP and uTP
        "Session\\uTPRateLimited" = true; # keep uTP from saturating TCP torrents
      };
      Preferences = {
        "WebUI\\Address" = "127.0.0.1";
        "WebUI\\Port" = webuiPort;
        "WebUI\\Username" = "omar";
        "WebUI\\Password_PBKDF2" = "@ByteArray(sXHUKbtrwuMZDQSf9NkSnw==:GPsZiEsuzyJzZDnY6YsmcXYjp54ptR2QcCH28m6tuR45LjnzNOTdpTldYiISoQC1G7yTwsNo8Ao4PB4+Wu+26Q==)";
        "LegalNotice\\Accepted" = true;
      };
    };
  };

  # Prometheus exporter for qBittorrent metrics
  systemd.services.prometheus-qbittorrent-exporter = {
    description = "Prometheus exporter for qBittorrent";
    after = ["network.target" "qbittorrent.service"];
    wantedBy = ["multi-user.target"];
    environment = {
      QBITTORRENT_BASE_URL = "http://127.0.0.1:${toString webuiPort}";
      EXPORTER_PORT = "9716";
      EXPORTER_HOST = "127.0.0.1";
    };
    serviceConfig = {
      Type = "simple";
      ExecStart = "${pkgs.prometheus-qbittorrent-exporter}/bin/qbit-exp";
      Restart = "on-failure";
      RestartSec = "10s";
      DynamicUser = true;
    };
  };
}
