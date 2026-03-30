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

  services.nginx.virtualHosts."qbittorrent.${cfg.domain}" = {
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
        "Session\\MaxActiveDownloads" = 30;
        "Session\\MaxActiveTorrents" = 35;
        "Session\\MaxActiveUploads" = 5;
        "Session\\GlobalMaxSeedingMinutes" = 5;
        "Session\\MaxRatio" = 0;
        "Session\\MaxRatioAction" = 1; # pause
        "Session\\MaxConnections" = 800;
        "Session\\MaxConnectionsPerTorrent" = 40;
        "Session\\DeleteTorrentFilesAsDefault" = true;
      };
      Preferences = {
        "WebUI\\Address" = "127.0.0.1";
        "WebUI\\Port" = webuiPort;
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
