{
  config,
  pkgs,
  ...
}: let
  # Shared with ./borg-metrics.nix; the node exporter is pointed at this
  # directory in ./default.nix.
  textfileDir = "/var/lib/prometheus-node-exporter-text-files";

  # `zpool status` per-vdev READ/WRITE/CKSUM counters and scrub timing are not
  # exposed by either the zfs exporter or node_exporter's zfs collector, so a
  # raidz pool can sit at ONLINE while individual members accumulate errors
  # and nothing alerts. OpenZFS >= 2.3 emits machine-readable JSON, which is
  # far safer to parse than the human status table.
  zpoolTextfile = pkgs.writeShellApplication {
    name = "zpool-textfile-collector";
    runtimeInputs = [config.boot.zfs.package pkgs.jq pkgs.coreutils];
    text = ''
      out="${textfileDir}/zpool.prom"
      tmp="$out.$$"
      trap 'rm -f "$tmp"' EXIT

      # --json-int makes every numeric field (including scan timestamps) a
      # real number rather than a human-formatted string.
      zpool status -j --json-flat-vdevs --json-int | jq -r '
        def lbl($p; $k; $v): "{pool=\"\($p)\",vdev=\"\($k)\",parent=\"\($v.parent // "")\"}";

        "# HELP zpool_vdev_read_errors Read errors counted by ZFS for a leaf vdev.",
        "# TYPE zpool_vdev_read_errors counter",
        "# HELP zpool_vdev_write_errors Write errors counted by ZFS for a leaf vdev.",
        "# TYPE zpool_vdev_write_errors counter",
        "# HELP zpool_vdev_checksum_errors Checksum errors counted by ZFS for a leaf vdev.",
        "# TYPE zpool_vdev_checksum_errors counter",
        "# HELP zpool_vdev_slow_ios I/Os slower than zio_slow_io_ms for a leaf vdev.",
        "# TYPE zpool_vdev_slow_ios counter",
        "# HELP zpool_vdev_online 1 if the leaf vdev state is ONLINE, else 0.",
        "# TYPE zpool_vdev_online gauge",
        "# HELP zpool_errors Permanent data errors known to the pool.",
        "# TYPE zpool_errors gauge",
        "# HELP zpool_status_ok 1 when zpool status prints no advisory text.",
        "# TYPE zpool_status_ok gauge",
        "# HELP zpool_scrub_end_timestamp_seconds Unix time the last scrub finished.",
        "# TYPE zpool_scrub_end_timestamp_seconds gauge",
        "# HELP zpool_scrub_errors Unrepairable errors found by the last scrub.",
        "# TYPE zpool_scrub_errors gauge",
        "# HELP zpool_scrub_in_progress 1 while a scrub is running.",
        "# TYPE zpool_scrub_in_progress gauge",

        (.pools | to_entries[] | .key as $pool | .value as $p
         | ($p.vdevs // {} | to_entries[]
            | select(.value.vdev_type == "disk")
            | lbl($pool; .key; .value) as $l
            | "zpool_vdev_read_errors\($l) \(.value.read_errors // 0)",
              "zpool_vdev_write_errors\($l) \(.value.write_errors // 0)",
              "zpool_vdev_checksum_errors\($l) \(.value.checksum_errors // 0)",
              "zpool_vdev_slow_ios\($l) \(.value.slow_ios // 0)",
              "zpool_vdev_online\($l) \(if .value.state == "ONLINE" then 1 else 0 end)"),

           "zpool_errors{pool=\"\($pool)\"} \($p.error_count // 0)",
           "zpool_status_ok{pool=\"\($pool)\"} \(if ($p.status // "") == "" then 1 else 0 end)",

           ($p.scan_stats // {} | select(.function == "SCRUB")
            | "zpool_scrub_errors{pool=\"\($pool)\"} \(.errors // 0)",
              "zpool_scrub_in_progress{pool=\"\($pool)\"} \(if .state == "SCANNING" then 1 else 0 end)",
              (select((.end_time // 0) > 0)
               | "zpool_scrub_end_timestamp_seconds{pool=\"\($pool)\"} \(.end_time)")))
      ' > "$tmp"

      chmod 0644 "$tmp"
      # Rename so node_exporter never reads a half-written file.
      mv "$tmp" "$out"
      trap - EXIT
    '';
  };
in {
  systemd.tmpfiles.rules = [
    "d ${textfileDir} 0755 root root -"
  ];

  systemd.services.zpool-textfile-collector = {
    description = "Export zpool vdev error counters and scrub state for node_exporter";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${zpoolTextfile}/bin/zpool-textfile-collector";
      # zpool status needs root to talk to /dev/zfs.
      User = "root";
      ProtectSystem = "strict";
      ReadWritePaths = [textfileDir];
      PrivateTmp = true;
      NoNewPrivileges = true;
    };
  };

  systemd.timers.zpool-textfile-collector = {
    description = "Refresh zpool textfile metrics";
    wantedBy = ["timers.target"];
    timerConfig = {
      OnBootSec = "2m";
      OnUnitActiveSec = "5m";
      AccuracySec = "30s";
    };
  };
}
