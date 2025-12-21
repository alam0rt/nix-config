{
  config,
  pkgs,
  ...
}: let
  cfg = config.server;
in {
  environment.systemPackages = with pkgs; [
    unstable.jellyfin
    unstable.jellyfin-web
    unstable.jellyfin-ffmpeg
  ];

  services.jellyseerr = {
    enable = true;
    openFirewall = true;
  };

  age.secrets."sonarr-api-key" = {
    rekeyFile = ./sonarr-api-key.age;
    owner = "recyclarr";
    group = "recyclarr";
  };

  age.secrets."radarr-api-key" = {
    rekeyFile = ./radarr-api-key.age;
    owner = "recyclarr";
    group = "recyclarr";
  };

  services.recyclarr = {
    enable = true;
    schedule = "daily";
    configuration = {
      radarr = [
        {
          api_key = {
            _secret = config.age.secrets."radarr-api-key".path;
          };
          base_url = "http://localhost:${toString config.services.radarr.settings.port}/";
          instance_name = "main";

        }
      ];
      sonarr = [
        {
          api_key = {
            _secret = config.age.secrets."sonarr-api-key".path;
          };
          base_url = "http://localhost:${toString config.services.sonarr.settings.port}/";
          instance_name = "main";
        }
      ];
    };
  };

  services.nginx = {
    virtualHosts."tv.samlockart.com" = {
      forceSSL = true;
      enableACME = true;
      locations."/" = {
        proxyPass = "http://127.0.0.1:8096";
        recommendedProxySettings = true;
      };
    };
    virtualHosts."requests.iced.cool" = {
      forceSSL = true;
      enableACME = true;
      locations."/" = {
        proxyPass = "http://127.0.0.1:${toString config.services.jellyseerr.port}";
        recommendedProxySettings = true;
      };
    };
    virtualHosts."jellyseerr.${cfg.domain}" = {
      forceSSL = true;
      useACMEHost = cfg.domain;
      locations."/" = {
        proxyPass = "http://127.0.0.1:${toString config.services.jellyseerr.port}";
        recommendedProxySettings = true;
      };
    };
    virtualHosts."tv.${cfg.domain}" = {
      forceSSL = true;
      useACMEHost = cfg.domain;
      locations."/" = {
        proxyPass = "http://127.0.0.1:8096";
        recommendedProxySettings = true;
      };
    };
    virtualHosts."sonarr.${cfg.domain}" = {
      forceSSL = true;
      useACMEHost = cfg.domain;
      locations."/" = {
        proxyPass = "http://127.0.0.1:${toString config.services.sonarr.settings.port}";
        recommendedProxySettings = true;
      };
    };
    virtualHosts."jackett.${cfg.domain}" = {
      forceSSL = true;
      useACMEHost = cfg.domain;
      locations."/" = {
        proxyPass = "http://127.0.0.1:9117";
        recommendedProxySettings = true;
      };
    };
    virtualHosts."bazarr.${cfg.domain}" = {
      forceSSL = true;
      useACMEHost = cfg.domain;
      locations."/" = {
        proxyPass = "http://127.0.0.1:${toString config.services.bazarr.listenPort}";
        recommendedProxySettings = true;
      };
    };
    virtualHosts."radarr.${cfg.domain}" = {
      forceSSL = true;
      useACMEHost = cfg.domain;
      locations."/" = {
        proxyPass = "http://127.0.0.1:${toString config.services.radarr.settings.port}";
        recommendedProxySettings = true;
      };
    };
    virtualHosts."lidarr.${cfg.domain}" = {
      forceSSL = true;
      useACMEHost = cfg.domain;
      locations."/" = {
        proxyPass = "http://127.0.0.1:${toString config.services.lidarr.settings.server.port}";
      };
    };
  };

  services.jellyfin = {
    package = pkgs.unstable.jellyfin;
    enable = true;
    openFirewall = true;
    dataDir = "/srv/data/jellyfin";
    cacheDir = "/var/cache/jellyfin"; # leave on ssd
  };

  services.lidarr = {
    enable = true;
    dataDir = "/srv/data/lidarr";
    openFirewall = true;
  };
  users.users.lidarr.extraGroups = ["transmission"];

  services.radarr = {
    enable = true;
    dataDir = "/srv/data/radarr";
    openFirewall = true;
  };
  users.users.radarr.extraGroups = ["transmission"];

  services.sonarr = {
    enable = true;
    dataDir = "/srv/data/sonarr";
    openFirewall = true;
  };
  users.users.sonarr.extraGroups = ["transmission"];

  services.jackett = {
    enable = true;
    dataDir = "/srv/data/jackett";
    package = pkgs.unstable.jackett;
    openFirewall = true;
  };

  services.bazarr = {
    enable = true;
    openFirewall = true;
  };
  users.users.bazarr.extraGroups = [
    "sonarr"
    "radarr"
  ];

  networking.firewall.allowedUDPPorts = [
    1900
    7359
  ]; # dlna
  networking.firewall.allowedTCPPorts = [8191]; # flaresolverr

  virtualisation.oci-containers.containers = {
    rarbg = {
      # https://github.com/mgdigital/rarbg-selfhosted
      image = "ghcr.io/mgdigital/rarbg-selfhosted:latest";
      ports = ["3333:3333"];
      volumes = ["/srv/data/rarbg_db.sqlite:/rarbg_db.sqlite"];
      pull = "always";
      serviceName = "rarbg-selfhosted";
    };

    flaresolverr = {
      image = "ghcr.io/flaresolverr/flaresolverr:latest";
      ports = ["8191:8191"];
      pull = "always";
      serviceName = "flaresolverr";
      extraOptions = ["--network=host"];
    };
  };
}
