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
  imports = [
    ./alerts.nix
    ./zpool-textfile.nix
    ./borg-metrics.nix
    ./alertmanager-matrix.nix
  ];

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
        # Was the upstream default prior to NixOS 26.05; pinned to preserve
        # decryption of existing DB-stored secrets. Rotate via an agenix
        # secret + file-provider when secrets that need real protection land.
        secret_key = "SW2YcwTIb9zpOOhoPsMm";
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
      # Metrics that need root or a shell pipeline are written here by
      # ./zpool-textfile.nix and ./borg-metrics.nix.
      "--collector.textfile.directory=/var/lib/prometheus-node-exporter-text-files"
    ];
  };

  # Run SMART self-tests on a schedule so the smartctl exporter has fresh
  # health data to scrape. Short test nightly at 02:00, long test Saturday
  # 03:00. Warnings are logged to syslog; real-time alerting is via the
  # Prometheus rules below (SmartDiskUnhealthy / DiskUncorrectedErrors /
  # DiskTransportErrors).
  services.smartd = {
    enable = true;
    autodetect = true;
    defaults.monitored = "-a -o on -S on -s (S/../.././02|L/../../6/03)";
  };

  services.prometheus.exporters = {
    zfs.enable = true;
    nginx.enable = true;
    smartctl.enable = true;

    # ACME renews at 30 days; without this a renewal that has been quietly
    # failing only surfaces when a browser refuses the site.
    node-cert = {
      enable = true;
      paths = ["/var/lib/acme"];
      # lego's internal store keeps a directory per ACME account, and the ones
      # from retired accounts are never cleaned up. Their long-expired copies
      # fired CertificateExpiringSoon for domains whose live cert is fine.
      excludePaths = ["/var/lib/acme/.lego"];
      # One series per domain — chain.pem reports the (much longer lived)
      # intermediate and full/fullchain.pem duplicate the leaf.
      #
      # Globs are matched with Go's filepath.Match against the *full* path, and
      # `*` does not cross `/`, so a bare "*/cert.pem" silently matches nothing
      # and filters nothing. Anchor every pattern at /var/lib/acme.
      excludeGlobs = [
        "/var/lib/acme/*/chain.pem"
        "/var/lib/acme/*/full.pem"
        "/var/lib/acme/*/fullchain.pem"
      ];
    };

    # upsd is already running for clean shutdown on power loss, but nothing
    # was reporting whether it can still talk to the UPS.
    nut = {
      enable = true;
      nutServer = "127.0.0.1";
    };

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
        job_name = "cert";
        scrape_interval = "5m";
        static_configs = [
          {
            targets = [
              "localhost:${toString config.services.prometheus.exporters.node-cert.port}"
            ];
            labels.instance = "sauron";
          }
        ];
      }
      {
        job_name = "nut";
        scrape_interval = "30s";
        static_configs = [
          {
            targets = [
              "localhost:${toString config.services.prometheus.exporters.nut.port}"
            ];
            labels.instance = "sauron";
          }
        ];
      }
      # Self-monitoring: without these, a Prometheus that cannot evaluate
      # rules or an Alertmanager that cannot deliver looks exactly like a
      # healthy system.
      {
        job_name = "prometheus";
        static_configs = [
          {
            targets = ["localhost:${toString config.services.prometheus.port}"];
            labels.instance = "sauron";
          }
        ];
      }
      {
        job_name = "alertmanager";
        static_configs = [
          {
            targets = ["localhost:${toString config.services.prometheus.alertmanager.port}"];
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
              "http://localhost:${toString config.services.bazarr.listenPort}" # bazarr
              "http://localhost:9117" # jackett
              "http://localhost:${toString config.services.prowlarr.settings.server.port}" # prowlarr
              "http://localhost:${toString config.services.seerr.port}" # jellyseerr
              # "http://localhost:${toString config.services.qbittorrent.webuiPort}" # qbittorrent - causes localhost ban due to failed auth
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
      # {
      #   job_name = "qbittorrent";
      #   scrape_interval = "30s";
      #   static_configs = [
      #     {
      #       targets = ["localhost:9716"];
      #       labels.instance = "sauron";
      #     }
      #   ];
      # }
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
  # Routing, inhibition and delivery live in ./alertmanager-matrix.nix.
  services.prometheus.alertmanager = {
    enable = true;
    configuration.global = {};
  };
}
