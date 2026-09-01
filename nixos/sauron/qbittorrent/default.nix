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

  # Let the *arrs actually remove completed downloads.
  #
  # sonarr and radarr are already supplementary members of the qbittorrent group
  # so they can move finished downloads out of /srv/media/downloads. That
  # membership was inert: unlinking a file requires write permission on the
  # *containing directory*, not on the file, and with systemd's default
  # UMask=0022 qBittorrent creates each per-torrent directory 0755 — group r-x,
  # no w. So Sonarr could read a download but never delete it.
  #
  # The failure mode is a livelock rather than a clean error. Sonarr copies the
  # episode to its destination, fails to unlink the source, and leaves the
  # destination behind; the next pass sees DestinationAlreadyExists, deletes the
  # destination, re-copies, and fails again — twice a minute, indefinitely. The
  # resulting create/delete churn in the library also drove Jellyfin's
  # LibraryMonitor into whole-library refreshes that deadlocked its SQLite
  # writes for 30s at a time and stalled in-flight playback.
  #
  # 0002 gives new directories 0775 and files 0664, so the group membership does
  # what it was always meant to do. Existing directories keep their old mode and
  # need a one-off chmod.
  systemd.services.qbittorrent.serviceConfig.UMask = lib.mkForce "0002";

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

        # Bandwidth ceilings — torrents must never starve Jellyfin.
        #
        # On 2026-09-01 an uncapped seed burst pushed ~80 Mbps out while a remote
        # viewer was direct-streaming a 9.35 Mbps 1080p WEB-DL. Jellyfin's share of
        # the link fell to 7.5 Mbps, below what the film needed, and playback froze
        # ~12 minutes from the end. Remote clients direct-stream at full source
        # bitrate (RemoteClientBitrateLimit is effectively unlimited), so there is no
        # adaptive downgrade to absorb the squeeze — the stream simply stalls.
        #
        # The link is ~200 Mbps up. Capping uploads at ~82 Mbps leaves ~120 Mbps,
        # roughly 12 concurrent full-bitrate streams, which is well clear of real
        # usage. Values are KiB/s, which is what qBittorrent expects.
        "Session\\GlobalUPSpeedLimit" = 10000; # ~82 Mbps
        "Session\\GlobalDLSpeedLimit" = 20000; # ~164 Mbps

        # Mark peer traffic CS1 (background). Costs nothing on its own, but means
        # torrents are already classified as bulk if a shaper or router-side QoS is
        # ever put in front of this. qBittorrent 5.x renamed PeerToS → PeerDSCP and
        # takes the DSCP value directly, so CS1 is 8 here (not the 32 you would write
        # into a ToS byte). Verified against setPeerDSCP in the 5.2.2 binary.
        "Session\\PeerDSCP" = 8;

        # Seeding policy: stop immediately after download (ratio 0, pause action)
        "Session\\GlobalMaxSeedingMinutes" = 5;
        "Session\\MaxRatio" = 0;
        "Session\\MaxRatioAction" = 0; # pause

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
        "WebUI\\MaxAuthenticationFailCount" = 0; # disable localhost ban on failed auth
        "WebUI\\Username" = "omar";
        "WebUI\\Password_PBKDF2" = "@ByteArray(/n9OsMRzfu8xiXDDsOBSzw==:skh7xP3pSe0JVmtgsVq30cAA9Ix6W2jJ+y4zv+2ptw8i65TIk4B+xthz5BCUdlothRcZs7iPRLG5dyEJNbcTSA==)";
        "LegalNotice\\Accepted" = true;
      };
    };
  };
}
