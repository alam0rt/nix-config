{ config
, lib
, pkgs
, ... }:
let cfg = config.server;
in {

  services.grafana = {
    enable = true;
    settings = {
        server = {
          domain = "grafana.middleearth.samlockart.com";
          root_url = "http://${toString config.services.grafana.settings.server.domain}/";
          protocol = "http";
          http_port = 3000;
          http_addr = "127.0.0.1";
          serve_from_sub_path = false;
        };
        security = {
          cookie_secure = false; # serving via https proxy
        };
        smtp = {
          enabled = true;
          host = "$__file{${config.age.secrets.smtp-addr.path}}:465";
          user = "$__file{${config.age.secrets.smtp-user.path}}";
          password = "$__file{${config.age.secrets.smtp-pass.path}}";
          from_address = "bot@iced.cool";
        };
    };
  };

  services.nginx.virtualHosts.${toString config.services.grafana.settings.server.domain} = {
    forceSSL = false;
    enableACME = false;
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

  # https://nixos.org/manual/nixos/stable/#module-services-prometheus-exporters
  services.prometheus.exporters.node = {
    enable = true;
    port = 9000;
    # https://github.com/NixOS/nixpkgs/blob/nixos-24.05/nixos/modules/services/monitoring/prometheus/exporters.nix
    enabledCollectors = [ "systemd" ];
    # /nix/store/zgsw0yx18v10xa58psanfabmg95nl2bb-node_exporter-1.8.1/bin/node_exporter  --help
    extraFlags = [ "--collector.ethtool" "--collector.softirqs" "--collector.tcpstat" ];
  };

  services.prometheus.exporters = {
    zfs.enable = true;
    nginx.enable = true;
    smartctl.enable = true;
  };

  services.prometheus = {
    enable = true;
    globalConfig.scrape_interval = "10s";
    scrapeConfigs = [
      {
        job_name = "self";
        static_configs = [{
          targets = [
            "localhost:${toString config.services.prometheus.exporters.node.port}" 
            "localhost:${toString config.services.prometheus.exporters.zfs.port}"
            "localhost:${toString config.services.prometheus.exporters.nginx.port}" 
            "localhost:${toString config.services.prometheus.exporters.smartctl.port}" 
          ];
        }];
      }
    ];
  }; 
}