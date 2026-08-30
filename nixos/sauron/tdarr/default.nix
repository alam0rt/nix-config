{
  config,
  lib,
  ...
}: let
  cfg = config.server;

  # Tdarr writes each transcode to a scratch copy before swapping it in, so the
  # cache needs headroom for the largest source file (currently 36.7 GB) times
  # the worker count. It deliberately lives *outside* /srv/media: anything under
  # the media root gets picked up by Jellyfin and the *arrs mid-write.
  # The NVMe root is not an option either — only ~46 GB free.
  #
  # Requires a one-off, out-of-band:
  #   zfs create -o mountpoint=/srv/tdarr-cache mordor/tdarr-cache
  cachePath = "/srv/tdarr-cache";

  nodeService = "tdarr-node-nvenc";
in {
  services.tdarr = {
    server.enable = true;

    nodes.nvenc = {
      # Transcoding here is DESTRUCTIVE — Tdarr re-encodes and replaces the
      # original on disk, unlike Jellyfin's live transcode which is discarded.
      # The node therefore starts paused and stays paused until work is queued
      # by hand from the web UI.
      startPaused = true;

      # Verified on the box, not inferred from spec sheets: `av1_nvenc` returns
      # "No capable devices found" on both cards (T1000 is Turing, RTX A1000 is
      # Ampere; NVENC AV1 encode starts at Ada). hevc_nvenc works on both, so
      # HEVC is the ceiling — do not build a flow around AV1.
      workers = {
        transcodeGPU = 2;
        transcodeCPU = 0;
        # Health checks rewrite files too, so they are off along with everything
        # else. An idle worker is how a quick pilot becomes a week-long grind.
        healthcheckGPU = 0;
        healthcheckCPU = 0;
      };
    };
  };

  # Library files are owned by radarr/sonarr with group-writable directories;
  # Tdarr replaces files in place, so it needs those groups to swap them, and
  # UMask 0002 so the replacements stay group-writable for the *arrs afterwards.
  users.users.tdarr.extraGroups = ["radarr" "sonarr" "video" "render"];

  # `z` rather than `d`: adjust the mountpoint's ownership if the dataset is
  # there, but never create a plain directory that would shadow the ZFS mount.
  systemd.tmpfiles.rules = [
    "z ${cachePath} 0750 tdarr tdarr -"
  ];

  # The upstream module sets ProtectSystem=strict, which leaves /srv read-only.
  systemd.services.${nodeService} = {
    serviceConfig = {
      ReadWritePaths = [
        "/srv/media"
        cachePath
      ];
      UMask = "0002";
    };
    environment = {
      # ffmpeg dlopens libnvidia-encode/libnvcuvid at runtime; they only live in
      # the driver's opengl-driver path, which is not on the default search path.
      LD_LIBRARY_PATH = "/run/opengl-driver/lib";
    };
  };

  systemd.services.tdarr-server.serviceConfig.ReadWritePaths = [
    "/srv/media"
    cachePath
  ];

  services.nginx.virtualHosts."tdarr.${cfg.domain}" = {
    forceSSL = true;
    useACMEHost = cfg.domain;
    locations."/" = {
      proxyPass = "http://127.0.0.1:${toString config.services.tdarr.server.webUIPort}";
      proxyWebsockets = true;
      recommendedProxySettings = true;
    };
    extraConfig = ''
      # Library scans stream progress over a long-lived connection.
      proxy_read_timeout 3600s;
      client_max_body_size 0;
    '';
  };
}
