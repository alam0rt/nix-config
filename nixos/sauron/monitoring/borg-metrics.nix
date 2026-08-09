{
  config,
  lib,
  pkgs,
  ...
}: let
  # Shared with ./zpool-textfile.nix; see ./default.nix for the node exporter
  # flag that makes this directory a metrics source.
  textfileDir = "/var/lib/prometheus-node-exporter-text-files";

  jobNames = builtins.attrNames config.services.borgbackup.jobs;

  # A borgbackup job is a oneshot: on success the unit returns to "inactive",
  # so node_exporter's systemd collector shows nothing at all and a job that
  # has silently stopped running looks identical to a healthy one. Recording
  # the outcome of each run gives us both "the last run failed" and, more
  # importantly, "no run has succeeded in N hours".
  recordResult = pkgs.writeShellApplication {
    name = "borg-record-result";
    runtimeInputs = [pkgs.coreutils];
    text = ''
      name="$1"
      out="${textfileDir}/borg-$name.prom"
      tmp="$out.$$"
      trap 'rm -f "$tmp"' EXIT

      # systemd sets SERVICE_RESULT in ExecStopPost; "success" is the only
      # value that means the archive was actually created.
      result="''${SERVICE_RESULT:-unknown}"
      now=$(date +%s)

      {
        echo "# HELP borg_backup_last_run_success 1 if the last borg run for this job succeeded."
        echo "# TYPE borg_backup_last_run_success gauge"
        echo "# HELP borg_backup_last_run_timestamp_seconds Unix time the last borg run for this job finished."
        echo "# TYPE borg_backup_last_run_timestamp_seconds gauge"
        echo "# HELP borg_backup_last_success_timestamp_seconds Unix time the last *successful* borg run finished."
        echo "# TYPE borg_backup_last_success_timestamp_seconds gauge"

        if [ "$result" = "success" ]; then
          echo "borg_backup_last_run_success{job_name=\"$name\",result=\"$result\"} 1"
          echo "borg_backup_last_success_timestamp_seconds{job_name=\"$name\"} $now"
        else
          echo "borg_backup_last_run_success{job_name=\"$name\",result=\"$result\"} 0"
          # Carry the previous success timestamp forward so a failing run does
          # not reset the staleness clock — otherwise a job that fails forever
          # would look freshly backed up.
          if [ -f "$out" ]; then
            grep '^borg_backup_last_success_timestamp_seconds' "$out" || true
          fi
        fi
        echo "borg_backup_last_run_timestamp_seconds{job_name=\"$name\"} $now"
      } > "$tmp"

      chmod 0644 "$tmp"
      mv "$tmp" "$out"
      trap - EXIT
    '';
  };
in {
  systemd.services =
    lib.genAttrs (map (n: "borgbackup-job-${n}") jobNames)
    (unit: let
      name = lib.removePrefix "borgbackup-job-" unit;
    in {
      serviceConfig = {
        ExecStopPost = ["${recordResult}/bin/borg-record-result ${name}"];
        ReadWritePaths = [textfileDir];
      };
    });
}
