{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.server;
  dashboardDir = ./dashboards;
  exportarrPorts = {
    sonarr = 9707;
    radarr = 9708;
  };
in {
  users.users.grafana.extraGroups = ["mail"]; # allow mail cred reading

  services.grafana = {
    enable = true;
    settings = {
      server = {
        domain = "grafana.${cfg.domain}";
        root_url = "https://${toString config.services.grafana.settings.server.domain}/";
        protocol = "http";
        http_port = 3000;
        http_addr = "127.0.0.1";
        serve_from_sub_path = false;
      };
      security = {
        cookie_secure = true; # serving via https proxy
      };
      smtp = {
        enabled = true;
        host = "$__file{${config.age.secrets.smtp-addr.path}}:465";
        user = "$__file{${config.age.secrets.smtp-user.path}}";
        password = "$__file{${config.age.secrets.smtp-pass.path}}";
        from_address = "bot@iced.cool";
      };
    };

    # Declarative datasources
    provision = {
      datasources.settings.datasources = [
        {
          name = "Prometheus";
          type = "prometheus";
          uid = "prometheus";
          url = "http://127.0.0.1:${toString config.services.prometheus.port}";
          isDefault = true;
          jsonData = {
            timeInterval = config.services.prometheus.globalConfig.scrape_interval;
          };
        }
      ];

      # Declarative dashboards
      dashboards.settings.providers = [
        {
          name = "NixOS Dashboards";
          options.path = dashboardDir;
          options.foldersFromFilesStructure = false;
          disableDeletion = true;
          allowUiUpdates = true;
        }
      ];
    };
  };

  services.nginx.virtualHosts.${toString config.services.grafana.settings.server.domain} = {
    forceSSL = true;
    useACMEHost = cfg.domain;
    locations = {
      "/" = {
        proxyPass = "${toString config.services.grafana.settings.server.protocol}://${toString config.services.grafana.settings.server.http_addr}:${toString config.services.grafana.settings.server.http_port}";
        recommendedProxySettings = true;
        proxyWebsockets = true;
        extraConfig = ''
          proxy_cookie_path / "/; HttpOnly; SameSite=strict";
        '';
      };
    };
  };

  # --- Prometheus exporters ---
  # https://nixos.org/manual/nixos/stable/#module-services-prometheus-exporters
  services.prometheus.exporters.node = {
    enable = true;
    port = 9000;
    enabledCollectors = ["systemd"];
    extraFlags = [
      "--collector.ethtool"
      "--collector.softirqs"
      "--collector.tcpstat"
    ];
  };

  services.prometheus.exporters = {
    zfs.enable = true;
    nginx.enable = true;
    smartctl.enable = true;

    # HTTP endpoint probing for all services
    blackbox = {
      enable = true;
      configFile = (pkgs.formats.yaml {}).generate "blackbox.yml" {
        modules = {
          http_2xx = {
            prober = "http";
            timeout = "10s";
            http = {
              valid_http_versions = ["HTTP/1.1" "HTTP/2.0"];
              valid_status_codes = [200 301 302 401 403];
              method = "GET";
              follow_redirects = true;
              preferred_ip_protocol = "ip4";
            };
          };
        };
      };
    };
  };

  # --- Exportarr for *arr services ---
  systemd.services = let
    mkExportarr = {
      name,
      port,
      apiKeySecret,
      urlPort,
    }: {
      "exportarr-${name}" = {
        description = "Exportarr for ${name}";
        after = ["network.target" "${name}.service"];
        wantedBy = ["multi-user.target"];
        script = ''
          export API_KEY=$(cat ${config.age.secrets.${apiKeySecret}.path})
          exec ${pkgs.unstable.exportarr}/bin/exportarr ${name} \
            --url http://localhost:${toString urlPort} \
            --port ${toString port}
        '';
        serviceConfig = {
          Type = "simple";
          Restart = "on-failure";
          RestartSec = "10s";
          DynamicUser = true;
          SupplementaryGroups = [config.age.secrets.${apiKeySecret}.group];
        };
      };
    };
  in
    lib.mkMerge [
      (mkExportarr {
        name = "sonarr";
        port = exportarrPorts.sonarr;
        apiKeySecret = "sonarr-api-key";
        urlPort = config.services.sonarr.settings.server.port;
      })
      (mkExportarr {
        name = "radarr";
        port = exportarrPorts.radarr;
        apiKeySecret = "radarr-api-key";
        urlPort = config.services.radarr.settings.server.port;
      })
    ];

  # --- Prometheus ---
  services.prometheus = {
    enable = true;
    retentionTime = "30d";
    globalConfig.scrape_interval = "10s";

    scrapeConfigs = [
      {
        job_name = "node";
        static_configs = [
          {
            targets = [
              "localhost:${toString config.services.prometheus.exporters.node.port}"
            ];
            labels.instance = "sauron";
          }
        ];
      }
      {
        job_name = "zfs";
        scrape_interval = "30s";
        static_configs = [
          {
            targets = [
              "localhost:${toString config.services.prometheus.exporters.zfs.port}"
            ];
            labels.instance = "sauron";
          }
        ];
      }
      {
        job_name = "nginx";
        static_configs = [
          {
            targets = [
              "localhost:${toString config.services.prometheus.exporters.nginx.port}"
            ];
            labels.instance = "sauron";
          }
        ];
      }
      {
        job_name = "smartctl";
        scrape_interval = "5m";
        static_configs = [
          {
            targets = [
              "localhost:${toString config.services.prometheus.exporters.smartctl.port}"
            ];
            labels.instance = "sauron";
          }
        ];
      }
      {
        job_name = "blackbox";
        scrape_interval = "30s";
        metrics_path = "/probe";
        params.module = ["http_2xx"];
        static_configs = [
          {
            targets = [
              "http://localhost:8096" # jellyfin
              "http://localhost:${toString config.services.sonarr.settings.server.port}" # sonarr
              "http://localhost:${toString config.services.radarr.settings.server.port}" # radarr
              "http://localhost:${toString config.services.lidarr.settings.server.port}" # lidarr
              "http://localhost:${toString config.services.bazarr.listenPort}" # bazarr
              "http://localhost:9117" # jackett
              "http://localhost:${toString config.services.jellyseerr.port}" # jellyseerr
              "http://localhost:${toString config.services.qbittorrent.webuiPort}" # qbittorrent
            ];
          }
        ];
        relabel_configs = [
          {
            source_labels = ["__address__"];
            target_label = "__param_target";
          }
          {
            source_labels = ["__param_target"];
            target_label = "instance";
          }
          {
            target_label = "__address__";
            replacement = "localhost:${toString config.services.prometheus.exporters.blackbox.port}";
          }
        ];
      }
      {
        job_name = "jellyfin";
        scrape_interval = "30s";
        static_configs = [
          {
            targets = ["localhost:8096"];
            labels.instance = "sauron";
          }
        ];
        metrics_path = "/metrics";
      }
      {
        job_name = "exportarr-sonarr";
        scrape_interval = "60s";
        static_configs = [
          {
            targets = ["localhost:${toString exportarrPorts.sonarr}"];
            labels.instance = "sauron";
          }
        ];
      }
      {
        job_name = "exportarr-radarr";
        scrape_interval = "60s";
        static_configs = [
          {
            targets = ["localhost:${toString exportarrPorts.radarr}"];
            labels.instance = "sauron";
          }
        ];
      }
      {
        job_name = "qbittorrent";
        scrape_interval = "30s";
        static_configs = [
          {
            targets = ["localhost:9716"];
            labels.instance = "sauron";
          }
        ];
      }
    ];

    # --- Alerting rules ---
    rules = [
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
            ];
          }
          {
            name = "disk-health";
            rules = [
              {
                alert = "SmartDiskUnhealthy";
                expr = "smartctl_device_smart_healthy == 0";
                for = "0m";
                labels.severity = "critical";
                annotations = {
                  summary = "Disk {{ $labels.device }} SMART health check failed";
                  description = "SMART reports {{ $labels.device }} ({{ $labels.model_name }}) as unhealthy.";
                };
              }
              {
                alert = "DiskTemperatureHigh";
                expr = ''smartctl_device_temperature{temperature_type="current"} > 50'';
                for = "5m";
                labels.severity = "warning";
                annotations = {
                  summary = "High temperature on disk {{ $labels.device }}";
                  description = "Disk {{ $labels.device }} temperature is {{ $value }}C.";
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
            name = "zfs";
            rules = [
              {
                alert = "ZfsArcHitRateLow";
                expr = ''node_zfs_arc_hits / (node_zfs_arc_hits + node_zfs_arc_misses) < 0.5'';
                for = "30m";
                labels.severity = "warning";
                annotations = {
                  summary = "ZFS ARC hit rate is low";
                  description = "ZFS ARC hit ratio has been below 50% for 30 minutes. Current: {{ $value }}";
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
                expr = ''node_systemd_unit_state{name=~"(jellyfin|sonarr|radarr|lidarr|bazarr|jackett|jellyseerr|qbittorrent)\\.service",state="failed"} == 1'';
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

    # Alertmanager integration
    alertmanagers = [
      {
        static_configs = [
          {
            targets = ["localhost:${toString config.services.prometheus.alertmanager.port}"];
          }
        ];
      }
    ];
  };

  # --- Alertmanager ---
  services.prometheus.alertmanager = {
    enable = true;
    configuration = {
      global = {};
      route = {
        receiver = "default";
        group_by = ["alertname" "severity"];
        group_wait = "30s";
        group_interval = "5m";
        repeat_interval = "4h";
        routes = [
          {
            receiver = "critical";
            match.severity = "critical";
            repeat_interval = "1h";
          }
        ];
      };
      receivers = [
        {
          name = "default";
          # Grafana will query alertmanager API for alerts display
        }
        {
          name = "critical";
          # Configure email/webhook here when ready
        }
      ];
    };
  };
}
