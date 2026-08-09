{config, ...}: let
  # smartctl's health/error counters carry only {instance,device}. The model
  # and serial live on the `smartctl_device` info metric (always 1), so
  # multiplying by it preserves the value while pulling those labels in —
  # otherwise annotations render "Disk sdh ()" and you have to go look up
  # which physical drive that is.
  withDisk = expr: "(${expr}) * on (instance, device) group_left (model_name, serial_number) smartctl_device";

  # How long a job may go without a successful run before we call it stale.
  # Derived from the job list so a newly added backup is covered by default;
  # only jobs that do not run daily need an entry here.
  borgJobOverrides = {
    "mordor-srv-data" = 3 * 3600; # hourly
  };
  borgMaxAge = name: borgJobOverrides.${name} or (26 * 3600);
  borgJobs = builtins.attrNames config.services.borgbackup.jobs;
in {
  services.prometheus.rules = [
    (builtins.toJSON {
      groups = [
        {
          name = "system";
          rules = [
            {
              alert = "HighCpuUsage";
              expr = ''100 - (avg(rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100) > 90'';
              for = "10m";
              labels.severity = "warning";
              annotations = {
                summary = "High CPU usage on {{ $labels.instance }}";
                description = "CPU usage has been above 90% for 10 minutes. Current value: {{ $value }}%";
              };
            }
            {
              alert = "HighMemoryUsage";
              expr = ''100 * (1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes) > 90'';
              for = "5m";
              labels.severity = "warning";
              annotations = {
                summary = "High memory usage on {{ $labels.instance }}";
                description = "Memory usage has been above 90% for 5 minutes. Current value: {{ $value }}%";
              };
            }
            {
              alert = "HighLoadAverage";
              expr = ''node_load5 > 50'';
              for = "10m";
              labels.severity = "warning";
              annotations = {
                summary = "High load average on {{ $labels.instance }}";
                description = "5-minute load average has been above 50 for 10 minutes. Current value: {{ $value }}";
              };
            }
            {
              alert = "HostDown";
              expr = "up == 0";
              for = "2m";
              labels.severity = "critical";
              annotations = {
                summary = "Target {{ $labels.job }} down";
                description = "{{ $labels.instance }} has been unreachable for 2 minutes.";
              };
            }
            {
              # NTP drift silently breaks TOTP, cert validation and log
              # correlation long before anything looks broken.
              alert = "ClockNotSynchronised";
              expr = "node_timex_sync_status == 0";
              for = "30m";
              labels.severity = "warning";
              annotations = {
                summary = "Clock not synchronised on {{ $labels.instance }}";
                description = "The kernel time sync status is unsynchronised. Check `timedatectl` and systemd-timesyncd/chrony.";
              };
            }
          ];
        }
        {
          name = "filesystem";
          rules = [
            {
              alert = "DiskSpaceLow";
              expr = ''(node_filesystem_avail_bytes{fstype=~"ext4|xfs|zfs|btrfs"} / node_filesystem_size_bytes{fstype=~"ext4|xfs|zfs|btrfs"}) * 100 < 10'';
              for = "5m";
              labels.severity = "warning";
              annotations = {
                summary = "Low disk space on {{ $labels.mountpoint }}";
                description = "Filesystem {{ $labels.mountpoint }} has less than 10% free space. Current free: {{ $value }}%";
              };
            }
            {
              alert = "DiskSpaceCritical";
              expr = ''(node_filesystem_avail_bytes{fstype=~"ext4|xfs|zfs|btrfs"} / node_filesystem_size_bytes{fstype=~"ext4|xfs|zfs|btrfs"}) * 100 < 5'';
              for = "2m";
              labels.severity = "critical";
              annotations = {
                summary = "Critical disk space on {{ $labels.mountpoint }}";
                description = "Filesystem {{ $labels.mountpoint }} has less than 5% free space. Current free: {{ $value }}%";
              };
            }
            {
              # A filesystem the kernel remounted read-only has already hit an
              # I/O or corruption error. Writes are being silently dropped.
              alert = "FilesystemReadOnly";
              expr = ''node_filesystem_readonly{fstype=~"ext4|xfs|btrfs"} == 1'';
              for = "1m";
              labels.severity = "critical";
              annotations = {
                summary = "Filesystem {{ $labels.mountpoint }} is read-only";
                description = "{{ $labels.device }} on {{ $labels.mountpoint }} was remounted read-only — check `dmesg` for I/O errors.";
              };
            }
            {
              # Running out of inodes looks like a full disk to applications
              # while `df -h` still shows free space.
              alert = "InodesLow";
              expr = ''(node_filesystem_files_free{fstype=~"ext4|xfs|btrfs"} / node_filesystem_files{fstype=~"ext4|xfs|btrfs"}) * 100 < 10'';
              for = "10m";
              labels.severity = "warning";
              annotations = {
                summary = "Low inodes on {{ $labels.mountpoint }}";
                description = "Filesystem {{ $labels.mountpoint }} has {{ $value }}% inodes free. Writes will fail with ENOSPC while df still shows space.";
              };
            }
          ];
        }
        {
          # smartctl scrapes every 5m, so every `for` here is >= 10m to ride
          # out a single missed scrape.
          name = "disk-health";
          rules = [
            {
              # NOTE: the metric is smart_status, not smart_healthy — the
              # latter does not exist in this exporter and silently never
              # fires. 1 = SMART overall-health PASSED, 0 = FAILED.
              alert = "SmartDiskUnhealthy";
              expr = withDisk "smartctl_device_smart_status == 0";
              for = "10m";
              labels.severity = "critical";
              annotations = {
                summary = "Disk {{ $labels.device }} SMART health check failed";
                description = "SMART overall-health self-assessment FAILED on {{ $labels.device }} ({{ $labels.model_name }}, s/n {{ $labels.serial_number }}). Replace this disk.";
              };
            }
            {
              # smartctl's exit status is a bitmask; anything non-zero means
              # it could not fully read the device or found a failure
              # indication. Without this, a drive that drops off the bus
              # stops producing health metrics and nothing notices.
              alert = "SmartctlReadFailed";
              expr = "smartctl_device_smartctl_exit_status != 0";
              for = "15m";
              labels.severity = "warning";
              annotations = {
                summary = "smartctl could not fully read {{ $labels.device }}";
                description = "smartctl exited {{ $value }} for {{ $labels.device }} (bitmask: 1=cli error, 2=open failed, 4=command failed, 8=DISK FAILING, 16=prefail, 32=usage-attr, 64=error log, 128=self-test log). Run `smartctl -a /dev/{{ $labels.device }}`.";
              };
            }
            {
              # If the exporter stops enumerating a disk, every other alert in
              # this group goes quiet instead of firing. Compare against the
              # high-water mark over a week rather than a hardcoded count.
              alert = "SmartctlDeviceDisappeared";
              expr = "smartctl_devices < max_over_time(smartctl_devices[7d])";
              for = "15m";
              labels.severity = "critical";
              annotations = {
                summary = "A disk vanished from the smartctl exporter";
                description = "smartctl now reports {{ $value }} devices, fewer than the last 7 days. A drive has dropped off the bus — compare `lsblk` against `zpool status`.";
              };
            }
            {
              # Uncorrected read/write errors mean the drive could not
              # recover the data itself — real media trouble.
              alert = "DiskUncorrectedErrors";
              expr = withDisk ''increase(smartctl_read_total_uncorrected_errors[1h]) >= 1 or increase(smartctl_write_total_uncorrected_errors[1h]) >= 1'';
              for = "0m";
              labels.severity = "critical";
              annotations = {
                summary = "New uncorrected errors on disk {{ $labels.device }}";
                description = "Disk {{ $labels.device }} ({{ $labels.model_name }}, s/n {{ $labels.serial_number }}) logged {{ $value }} uncorrected read/write errors in the last hour.";
              };
            }
            {
              # The increase() rule above only catches *new* errors. A drive
              # that accumulated uncorrected errors before this rule existed
              # (or before the last restart) would otherwise stay invisible.
              alert = "DiskUncorrectedErrorsPresent";
              expr = withDisk ''smartctl_read_total_uncorrected_errors > 0 or smartctl_write_total_uncorrected_errors > 0'';
              for = "1h";
              labels.severity = "warning";
              annotations = {
                summary = "Disk {{ $labels.device }} has logged uncorrected errors";
                description = "Disk {{ $labels.device }} ({{ $labels.model_name }}, s/n {{ $labels.serial_number }}) has {{ $value }} lifetime uncorrected errors. This does not clear on its own — plan a replacement.";
              };
            }
            {
              # ReRead/ReWrite-corrected errors climbing is the classic
              # signature of a marginal cable/connector/backplane lane
              # (the data was recovered, but the transport is flaky).
              alert = "DiskTransportErrors";
              expr = withDisk ''increase(smartctl_read_errors_corrected_by_rereads_rewrites[1h]) >= 1 or increase(smartctl_write_errors_corrected_by_rereads_rewrites[1h]) >= 1'';
              for = "0m";
              labels.severity = "warning";
              annotations = {
                summary = "Transport-corrected errors on disk {{ $labels.device }}";
                description = "Disk {{ $labels.device }} ({{ $labels.model_name }}, s/n {{ $labels.serial_number }}) needed reread/rewrite retries in the last hour — suspect a cable/backplane/HBA link, not the platters.";
              };
            }
            {
              # SCSI grown defect list = sectors the drive has reallocated
              # since leaving the factory. Growth is the single best early
              # predictor of SAS drive failure and nothing else alerts on it.
              alert = "DiskGrownDefectsIncreasing";
              expr = withDisk ''increase(smartctl_scsi_grown_defect_list[24h]) >= 1'';
              for = "0m";
              labels.severity = "warning";
              annotations = {
                summary = "Disk {{ $labels.device }} is reallocating sectors";
                description = "Disk {{ $labels.device }} ({{ $labels.model_name }}, s/n {{ $labels.serial_number }}) added {{ $value }} entries to its grown defect list in 24h. Active media degradation.";
              };
            }
            {
              alert = "DiskGrownDefectsHigh";
              expr = withDisk ''smartctl_scsi_grown_defect_list > 100'';
              for = "1h";
              labels.severity = "warning";
              annotations = {
                summary = "Disk {{ $labels.device }} has a large grown defect list";
                description = "Disk {{ $labels.device }} ({{ $labels.model_name }}, s/n {{ $labels.serial_number }}) has reallocated {{ $value }} sectors. Treat this drive as a replacement candidate.";
              };
            }
            {
              alert = "DiskTemperatureHigh";
              expr = withDisk ''smartctl_device_temperature{temperature_type="current"} > 50'';
              for = "10m";
              labels.severity = "warning";
              annotations = {
                summary = "High temperature on disk {{ $labels.device }}";
                description = "Disk {{ $labels.device }} ({{ $labels.model_name }}) is at {{ $value }}C.";
              };
            }
            {
              # Absolute thresholds are guesses; the drive publishes its own
              # trip temperature, so alert within 10C of it.
              alert = "DiskTemperatureCritical";
              expr = ''smartctl_device_temperature{temperature_type="current"} >= on (instance, device) (smartctl_device_temperature{temperature_type="drive_trip"} - 10)'';
              for = "5m";
              labels.severity = "critical";
              annotations = {
                summary = "Disk {{ $labels.device }} is near its thermal trip point";
                description = "Disk {{ $labels.device }} is at {{ $value }}C, within 10C of the temperature at which it will protect itself. Check chassis airflow now.";
              };
            }
            # --- NVMe-only (the boot SSD); these metrics do not exist for the
            # SAS drives, so the rules simply never match there.
            {
              alert = "NvmeCriticalWarning";
              expr = withDisk "smartctl_device_critical_warning > 0";
              for = "10m";
              labels.severity = "critical";
              annotations = {
                summary = "NVMe {{ $labels.device }} raised a critical warning";
                description = "{{ $labels.device }} ({{ $labels.model_name }}) critical warning bitmask is {{ $value }} (1=spare low, 2=temp, 4=reliability degraded, 8=read-only, 16=volatile memory backup failed).";
              };
            }
            {
              alert = "NvmeSpareLow";
              expr = withDisk "smartctl_device_available_spare < smartctl_device_available_spare_threshold";
              for = "10m";
              labels.severity = "critical";
              annotations = {
                summary = "NVMe {{ $labels.device }} is out of spare blocks";
                description = "{{ $labels.device }} available spare is {{ $value }}%, below the manufacturer threshold. The drive is at end of life.";
              };
            }
            {
              alert = "NvmeWearHigh";
              expr = withDisk "smartctl_device_percentage_used > 80";
              for = "1h";
              labels.severity = "warning";
              annotations = {
                summary = "NVMe {{ $labels.device }} is {{ $value }}% through its rated endurance";
                description = "{{ $labels.device }} ({{ $labels.model_name }}) has consumed {{ $value }}% of its rated write endurance.";
              };
            }
            {
              alert = "NvmeMediaErrors";
              expr = withDisk "increase(smartctl_device_media_errors[24h]) >= 1";
              for = "0m";
              labels.severity = "critical";
              annotations = {
                summary = "NVMe {{ $labels.device }} logged media errors";
                description = "{{ $labels.device }} recorded {{ $value }} unrecovered data integrity errors in 24h.";
              };
            }
          ];
        }
        {
          # The zpool_* metrics come from the textfile collector fed by
          # ./zpool-textfile.nix, which refreshes every 5 minutes.
          name = "zfs";
          rules = [
            {
              # zfs_pool_health: 0 = ONLINE; anything else is
              # DEGRADED/FAULTED/UNAVAIL/etc.
              alert = "ZfsPoolNotOnline";
              expr = "zfs_pool_health != 0";
              for = "1m";
              labels.severity = "critical";
              annotations = {
                summary = "ZFS pool {{ $labels.pool }} is not ONLINE";
                description = "Pool {{ $labels.pool }} reports health state {{ $value }} (0 = ONLINE). Check `zpool status -v`.";
              };
            }
            {
              alert = "ZfsPoolReadOnly";
              expr = "zfs_pool_readonly == 1";
              for = "1m";
              labels.severity = "critical";
              annotations = {
                summary = "ZFS pool {{ $labels.pool }} is read-only";
                description = "Pool {{ $labels.pool }} was imported read-only or faulted into read-only. Writes are failing.";
              };
            }
            {
              # A raidz pool stays ONLINE while individual members rack up
              # read/write/checksum errors, so ZfsPoolNotOnline never fires
              # for the single most common real-world ZFS fault. This is the
              # `zpool status` READ/WRITE/CKSUM columns.
              alert = "ZfsVdevErrorsIncreasing";
              expr = ''increase(zpool_vdev_read_errors[1h]) >= 1 or increase(zpool_vdev_write_errors[1h]) >= 1 or increase(zpool_vdev_checksum_errors[1h]) >= 1'';
              for = "0m";
              labels.severity = "critical";
              annotations = {
                summary = "ZFS vdev {{ $labels.vdev }} is accumulating errors";
                description = "{{ $labels.vdev }} in {{ $labels.parent }} ({{ $labels.pool }}) logged {{ $value }} new errors in the last hour. Active fault — `zpool status -v {{ $labels.pool }}`.";
              };
            }
            {
              alert = "ZfsVdevErrorsPresent";
              expr = ''zpool_vdev_read_errors > 0 or zpool_vdev_write_errors > 0 or zpool_vdev_checksum_errors > 0'';
              for = "30m";
              labels.severity = "warning";
              annotations = {
                summary = "ZFS vdev {{ $labels.vdev }} has non-zero error counters";
                description = "{{ $labels.vdev }} in {{ $labels.parent }} ({{ $labels.pool }}) has {{ $value }} accumulated errors. Investigate, then `zpool clear {{ $labels.pool }}` to reset the counters so new faults are visible.";
              };
            }
            {
              alert = "ZfsVdevNotOnline";
              expr = "zpool_vdev_online == 0";
              for = "5m";
              labels.severity = "critical";
              annotations = {
                summary = "ZFS vdev {{ $labels.vdev }} is not ONLINE";
                description = "{{ $labels.vdev }} in {{ $labels.parent }} ({{ $labels.pool }}) has left the ONLINE state. Redundancy is reduced.";
              };
            }
            {
              alert = "ZfsPoolDataErrors";
              expr = "zpool_errors > 0";
              for = "5m";
              labels.severity = "critical";
              annotations = {
                summary = "ZFS pool {{ $labels.pool }} has permanent data errors";
                description = "{{ $value }} files have unrecoverable errors. `zpool status -v {{ $labels.pool }}` lists them; restore those paths from borg.";
              };
            }
            {
              # Catch-all for the advisory text `zpool status` prints that
              # none of the numeric metrics capture (resilver needed, device
              # removed, feature flags, previous unrecoverable errors).
              alert = "ZfsPoolStatusAdvisory";
              expr = "zpool_status_ok == 0";
              for = "30m";
              labels.severity = "warning";
              annotations = {
                summary = "ZFS pool {{ $labels.pool }} has a status advisory";
                description = "`zpool status {{ $labels.pool }}` is printing a status/action message. Read it — this covers conditions the numeric metrics miss.";
              };
            }
            {
              alert = "ZfsScrubFoundErrors";
              expr = "zpool_scrub_errors > 0";
              for = "5m";
              labels.severity = "critical";
              annotations = {
                summary = "Last scrub of {{ $labels.pool }} found unrepairable errors";
                description = "The last scrub of {{ $labels.pool }} could not repair {{ $value }} errors.";
              };
            }
            {
              # services.zfs.autoScrub runs monthly; 35 days leaves slack for
              # a long scrub (a full pass here takes over a day) before we
              # complain that scrubbing has stopped happening at all.
              alert = "ZfsScrubOverdue";
              expr = "time() - zpool_scrub_end_timestamp_seconds > 35 * 24 * 3600 and zpool_scrub_in_progress == 0";
              for = "1h";
              labels.severity = "warning";
              annotations = {
                summary = "ZFS pool {{ $labels.pool }} has not been scrubbed recently";
                description = "The last scrub of {{ $labels.pool }} finished more than 35 days ago and none is running. Check `systemctl status zfs-scrub-{{ $labels.pool }}.timer`.";
              };
            }
            {
              # ZFS allocation performance falls off a cliff past ~80% and
              # fragmentation becomes hard to undo without rewriting data.
              alert = "ZfsPoolCapacityHigh";
              expr = "zfs_pool_allocated_bytes / zfs_pool_size_bytes > 0.80";
              for = "1h";
              labels.severity = "warning";
              annotations = {
                summary = "ZFS pool {{ $labels.pool }} is over 80% full";
                description = "Pool {{ $labels.pool }} is {{ $value }} allocated. Write performance degrades sharply past 80% and fragmentation becomes permanent.";
              };
            }
            {
              alert = "ZfsPoolCapacityCritical";
              expr = "zfs_pool_allocated_bytes / zfs_pool_size_bytes > 0.90";
              for = "15m";
              labels.severity = "critical";
              annotations = {
                summary = "ZFS pool {{ $labels.pool }} is over 90% full";
                description = "Pool {{ $labels.pool }} is {{ $value }} allocated. Free space now — copy-on-write needs headroom even to delete.";
              };
            }
            {
              alert = "ZfsExporterCollectorFailed";
              expr = "zfs_scrape_collector_success == 0";
              for = "15m";
              labels.severity = "warning";
              annotations = {
                summary = "ZFS exporter collector {{ $labels.collector }} is failing";
                description = "The {{ $labels.collector }} collector is not returning data — the ZFS alerts above are running blind.";
              };
            }
            {
              # NOTE: node_zfs_arc_hits/misses are cumulative counters. The
              # raw ratio is a lifetime average that never moves, so this has
              # to be rate()-based to mean anything.
              alert = "ZfsArcHitRateLow";
              expr = ''sum(rate(node_zfs_arc_hits[30m])) / (sum(rate(node_zfs_arc_hits[30m])) + sum(rate(node_zfs_arc_misses[30m]))) < 0.5'';
              for = "30m";
              labels.severity = "warning";
              annotations = {
                summary = "ZFS ARC hit rate is low";
                description = "ARC hit ratio has been below 50% for 30 minutes (currently {{ $value }}). ARC is likely being squeezed — check memory pressure.";
              };
            }
          ];
        }
        {
          # Backups had no alerting at all: a job that fails every night is
          # invisible until you need to restore. Metrics come from the
          # ExecStopPost hook in ./borg-metrics.nix.
          name = "backups";
          rules =
            [
              {
                alert = "BorgBackupFailed";
                expr = "borg_backup_last_run_success == 0";
                for = "10m";
                labels.severity = "warning";
                annotations = {
                  summary = "Borg job {{ $labels.job_name }} failed";
                  description = "The last run of borgbackup-job-{{ $labels.job_name }} exited with result '{{ $labels.result }}'. Check `journalctl -u borgbackup-job-{{ $labels.job_name }}`.";
                };
              }
            ]
            ++ (map (name: {
                alert = "BorgBackupStale";
                # The absent() arm also fires on a freshly deployed host until
                # each job has run once — up to a day for the daily jobs. That
                # is the price of catching the case where the metric stops
                # being written at all; it clears itself after the first run.
                expr = "time() - borg_backup_last_success_timestamp_seconds{job_name=\"${name}\"} > ${toString (borgMaxAge name)} or absent(borg_backup_last_success_timestamp_seconds{job_name=\"${name}\"})";
                for = "30m";
                labels.severity = "critical";
                labels.job_name = name;
                annotations = {
                  summary = "Borg job ${name} has no recent successful backup";
                  description = "borgbackup-job-${name} has not completed successfully within ${toString ((borgMaxAge name) / 3600)}h. Backups are not being taken.";
                };
              })
              borgJobs);
        }
        {
          name = "certificates";
          rules = [
            {
              alert = "CertificateExpiringSoon";
              expr = "ssl_certificate_expiry_seconds < 21 * 24 * 3600";
              for = "1h";
              labels.severity = "warning";
              annotations = {
                summary = "Certificate for {{ $labels.subject }} expires soon";
                description = "{{ $labels.path }} ({{ $labels.subject }}) expires in {{ $value }}s. ACME renews at 30 days, so this means renewal is failing — check `systemctl status acme-*.service`.";
              };
            }
            {
              alert = "CertificateExpiryImminent";
              expr = "ssl_certificate_expiry_seconds < 7 * 24 * 3600";
              for = "15m";
              labels.severity = "critical";
              annotations = {
                summary = "Certificate for {{ $labels.subject }} expires in under 7 days";
                description = "{{ $labels.path }} ({{ $labels.subject }}) expires in {{ $value }}s and ACME has not renewed it.";
              };
            }
            {
              alert = "CertificateUnreadable";
              expr = "ssl_certificate_expiry_failed > 0";
              for = "30m";
              labels.severity = "warning";
              annotations = {
                summary = "Certificate at {{ $labels.path }} could not be parsed";
                description = "The cert exporter failed to read {{ $labels.path }} — expiry for that certificate is not being monitored.";
              };
            }
          ];
        }
        {
          name = "power";
          rules = [
            {
              # NUT reporting stale data means upsd has lost contact with the
              # driver: the UPS is effectively unmonitored and an outage will
              # not trigger a clean shutdown.
              alert = "UpsDataStale";
              expr = ''absent(network_ups_tools_ups_status) or up{job="nut"} == 0'';
              for = "15m";
              labels.severity = "warning";
              annotations = {
                summary = "UPS telemetry is unavailable";
                description = "No UPS status is being reported. upsmon cannot trigger a clean shutdown on power loss — check `upsc sauron@localhost` and `systemctl status nut-driver-*`.";
              };
            }
            {
              alert = "UpsOnBattery";
              expr = ''network_ups_tools_ups_status{flag="OB"} == 1'';
              for = "1m";
              labels.severity = "critical";
              annotations = {
                summary = "UPS is running on battery";
                description = "Mains power is gone. Runtime is limited — expect a clean shutdown when the low-battery signal arrives.";
              };
            }
            {
              alert = "UpsBatteryLow";
              expr = ''network_ups_tools_ups_status{flag="LB"} == 1'';
              for = "0m";
              labels.severity = "critical";
              annotations = {
                summary = "UPS battery is low";
                description = "The UPS has signalled low battery. Shutdown is imminent.";
              };
            }
            {
              alert = "UpsBatteryNeedsReplacement";
              expr = ''network_ups_tools_ups_status{flag="RB"} == 1'';
              for = "1h";
              labels.severity = "warning";
              annotations = {
                summary = "UPS battery needs replacing";
                description = "The UPS is reporting the replace-battery flag. It will not hold up the server through an outage.";
              };
            }
          ];
        }
        {
          name = "services";
          rules = [
            {
              alert = "SystemdUnitFailed";
              expr = ''node_systemd_unit_state{state="failed"} == 1'';
              for = "2m";
              labels.severity = "warning";
              annotations = {
                summary = "Systemd unit {{ $labels.name }} failed";
                description = "Systemd unit {{ $labels.name }} has been in failed state for 2 minutes.";
              };
            }
          ];
        }
        {
          # Memory is tight on this host (62G, ZFS ARC + a 12G transcode
          # tmpfs + active swap). PSI memory pressure is the right early
          # signal — it measures time tasks actually stalled waiting on
          # memory, unlike raw "free" which is misleading with reclaimable
          # ARC/page cache. systemd-oomd (PSI-driven) is the backstop that
          # kills cgroups before the kernel OOM killer; these alerts tell us
          # when that's getting close or has fired.
          name = "memory";
          rules = [
            {
              # "some" PSI: fraction of wall-time at least one task was
              # stalled waiting on memory. >10% sustained = real pressure.
              alert = "MemoryPressureHigh";
              expr = ''rate(node_pressure_memory_waiting_seconds_total[5m]) > 0.10'';
              for = "10m";
              labels.severity = "warning";
              annotations = {
                summary = "Sustained memory pressure on {{ $labels.instance }}";
                description = "Tasks have been stalled waiting on memory >10% of the time for 10m. ARC/tmpfs/swap are competing — check `cat /proc/pressure/memory`, `free -h`, ARC size.";
              };
            }
            {
              # "full" PSI: fraction of time *every* task was stalled on
              # memory — severe, throughput is collapsing.
              alert = "MemoryPressureCritical";
              expr = ''rate(node_pressure_memory_stalled_seconds_total[5m]) > 0.20'';
              for = "5m";
              labels.severity = "critical";
              annotations = {
                summary = "Severe memory pressure on {{ $labels.instance }}";
                description = "All tasks stalled on memory >20% of the time for 5m — OOM kills are likely imminent.";
              };
            }
            {
              # Definitive: the kernel (or systemd-oomd) actually killed
              # something for memory. Counter increasing = it happened.
              alert = "OOMKillsDetected";
              expr = ''increase(node_vmstat_oom_kill[10m]) > 0'';
              for = "0m";
              labels.severity = "critical";
              annotations = {
                summary = "OOM kill(s) on {{ $labels.instance }}";
                description = "{{ $value }} process(es) were OOM-killed in the last 10m. Check `journalctl -k -g oom` and `journalctl -u systemd-oomd`.";
              };
            }
            {
              alert = "SwapNearlyFull";
              expr = ''(node_memory_SwapFree_bytes / node_memory_SwapTotal_bytes) < 0.10'';
              for = "15m";
              labels.severity = "warning";
              annotations = {
                summary = "Swap nearly exhausted on {{ $labels.instance }}";
                description = "Less than 10% swap free for 15m. Once swap fills, the next pressure spike goes straight to OOM kills.";
              };
            }
          ];
        }
        {
          name = "blackbox";
          rules = [
            {
              alert = "ServiceDown";
              expr = ''probe_success{job="blackbox"} == 0'';
              for = "3m";
              labels.severity = "critical";
              annotations = {
                summary = "Service {{ $labels.instance }} is down";
                description = "HTTP probe to {{ $labels.instance }} has been failing for 3 minutes.";
              };
            }
            {
              alert = "ServiceSlowResponse";
              expr = ''probe_http_duration_seconds{job="blackbox"} > 5'';
              for = "5m";
              labels.severity = "warning";
              annotations = {
                summary = "Slow response from {{ $labels.instance }}";
                description = "{{ $labels.instance }} response time is {{ $value }}s (>5s for 5 minutes).";
              };
            }
          ];
        }
        {
          # Without these, the monitoring stack failing looks identical to
          # everything being healthy.
          name = "monitoring";
          rules = [
            {
              alert = "PrometheusRuleEvaluationFailing";
              expr = "increase(prometheus_rule_evaluation_failures_total[10m]) > 0";
              for = "0m";
              labels.severity = "warning";
              annotations = {
                summary = "Prometheus rule evaluations are failing";
                description = "{{ $value }} rule evaluations failed in group {{ $labels.rule_group }} in the last 10m — some alerts are not being evaluated.";
              };
            }
            {
              alert = "PrometheusNotificationsFailing";
              expr = "increase(prometheus_notifications_errors_total[10m]) > 0";
              for = "0m";
              labels.severity = "critical";
              annotations = {
                summary = "Prometheus cannot reach Alertmanager";
                description = "{{ $value }} notification deliveries to {{ $labels.alertmanager }} failed in 10m. Alerts are firing but not being delivered.";
              };
            }
            {
              alert = "AlertmanagerNotificationsFailing";
              expr = "increase(alertmanager_notifications_failed_total[10m]) > 0";
              for = "0m";
              labels.severity = "critical";
              annotations = {
                summary = "Alertmanager cannot deliver to {{ $labels.integration }}";
                description = "{{ $value }} notifications to the {{ $labels.integration }} integration failed in 10m. You are not receiving alerts.";
              };
            }
            {
              alert = "PrometheusTsdbCompactionFailing";
              expr = "increase(prometheus_tsdb_compactions_failed_total[3h]) > 0";
              for = "0m";
              labels.severity = "warning";
              annotations = {
                summary = "Prometheus TSDB compaction is failing";
                description = "Compaction has failed {{ $value }} times in 3h — check disk space and permissions on the Prometheus data directory.";
              };
            }
            {
              alert = "PrometheusTargetScrapesFailing";
              expr = ''increase(prometheus_target_scrapes_sample_duplicate_timestamp_total[1h]) > 0 or increase(prometheus_target_scrapes_exceeded_sample_limit_total[1h]) > 0'';
              for = "0m";
              labels.severity = "warning";
              annotations = {
                summary = "Prometheus is dropping samples";
                description = "Samples are being rejected (duplicate timestamps or sample limit). Some metrics are silently missing.";
              };
            }
            {
              # Always firing. Route it somewhere you can see so that the
              # *absence* of this alert tells you the pipeline is broken —
              # otherwise a dead Alertmanager and a healthy server look the
              # same from the outside.
              alert = "Watchdog";
              expr = "vector(1)";
              for = "0m";
              labels.severity = "watchdog";
              annotations = {
                summary = "Alerting pipeline heartbeat";
                description = "This alert always fires. If it stops arriving, the alerting pipeline itself is broken.";
              };
            }
          ];
        }
        {
          name = "media";
          rules = [
            {
              alert = "SonarrQueueStuck";
              expr = "sonarr_queue_total > 0";
              for = "6h";
              labels.severity = "warning";
              annotations = {
                summary = "Sonarr queue has been non-empty for 6 hours";
                description = "Sonarr has {{ $value }} items stuck in queue.";
              };
            }
            {
              alert = "RadarrQueueStuck";
              expr = "radarr_queue_total > 0";
              for = "6h";
              labels.severity = "warning";
              annotations = {
                summary = "Radarr queue has been non-empty for 6 hours";
                description = "Radarr has {{ $value }} items stuck in queue.";
              };
            }
            {
              alert = "MediaServiceDown";
              expr = ''node_systemd_unit_state{name=~"(jellyfin|sonarr|radarr|bazarr|jackett|prowlarr|jellyseerr|qbittorrent)\\.service",state="failed"} == 1'';
              for = "2m";
              labels.severity = "critical";
              annotations = {
                summary = "Media service {{ $labels.name }} is down";
                description = "{{ $labels.name }} has been in failed state for 2 minutes.";
              };
            }
          ];
        }
      ];
    })
  ];
}
