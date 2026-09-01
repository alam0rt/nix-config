{
  config,
  lib,
  ...
}: let
  cfg = config.server;

  # Tdarr writes each transcode to a scratch copy before swapping it in, so the
  # cache needs headroom for the largest source (currently 36.7 GB) times the
  # worker count. It has to be its own dataset, not just a directory: /srv
  # itself is on the ext4 NVMe root with ~46 GB free, and only the child paths
  # (/srv/media, /srv/data, ...) are pool mounts. Tdarr's default cache under
  # the node dataDir is on that same root, which is what this exists to avoid.
  #
  # The quota is the point of keeping it separate — on a pool at 91% a runaway
  # cache would otherwise eat the very space this is meant to reclaim.
  #
  # Declared in hardware-configuration.nix; the dataset itself is a one-off,
  # and must exist BEFORE the first switch that adds the mount:
  #
  #   zfs create -o mountpoint=legacy \
  #              -o quota=300G \
  #              -o compression=off \
  #              -o sync=disabled \
  #              -o recordsize=1M \
  #              -o atime=off \
  #              mordor/tdarr-cache
  #
  # compression=off because the payload is already-compressed video;
  # sync=disabled because a lost cache just means the job re-runs.
  cachePath = "/srv/tdarr-cache";

  nodeService = "tdarr-node-nvenc";
in {
  # Tdarr ships a self-updater that downloads a new build and swaps the binary
  # in place. That can never work here — the binary is in /nix/store — so it
  # burns a ~100 MB download and three retries per attempt before failing at
  # the "promoteNewBuild" step. Seen on 2026-08-30 trying 2.74.01 -> 2.86.01.
  #
  # There is no module option for it: `autoUpdateServer` and `autoUpdateNodes`
  # live in the server's own database (SettingsGlobalJSONDB/globalsettings),
  # not in this file. Both are now false; if a wipe of /var/lib/tdarr/server
  # ever resets them, turn them off again under Settings -> Options, or:
  #
  #   curl -X POST http://127.0.0.1:8265/api/v2/cruddb \
  #     -H 'Content-Type: application/json' \
  #     -d '{"data":{"collection":"SettingsGlobalJSONDB","mode":"update",
  #          "docID":"globalsettings",
  #          "obj":{"autoUpdateServer":false,"autoUpdateNodes":false}}}'
  #
  # `pluginAutoUpdate` is unrelated and stays on: plugins are pulled into the
  # writable state dir, and that succeeds.
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
    unitConfig.RequiresMountsFor = cachePath;
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

      # Before running a job the node shells out to its bundled pnpm to install
      # plugin dependencies, and pnpm writes its store and config under $HOME.
      # $HOME is /var/lib/tdarr from passwd, but ProtectSystem=strict leaves
      # that read-only — only StateDirectory and ReadWritePaths are writable —
      # so pnpm exits 254 with no output and every job fails as "Transcode
      # error" before ffmpeg is ever invoked. Point HOME at the node's own data
      # path, which systemd already grants it via StateDirectory.
      HOME = "/var/lib/tdarr/nodes/nvenc";
    };
  };

  # Neither unit may start before the cache is actually mounted; otherwise they
  # would write into the mountpoint on the NVMe root instead of the dataset.
  systemd.services.tdarr-server.unitConfig.RequiresMountsFor = cachePath;

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
