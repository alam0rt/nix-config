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
      radarr = {
        movies = {
          api_key = {
            _secret = config.age.secrets."radarr-api-key".path;
          };
          base_url = "http://localhost:${toString config.services.radarr.settings.server.port}/";
          delete_old_custom_formats = true;
          include = [
            {template = "radarr-quality-definition-movie";}
            {template = "radarr-quality-profile-hd-bluray-web";}
            {template = "radarr-custom-formats-hd-bluray-web";}
          ];
        };
      };
      sonarr = {
        tv = {
          api_key = {
            _secret = config.age.secrets."sonarr-api-key".path;
          };
          base_url = "http://localhost:${toString config.services.sonarr.settings.server.port}/";
          delete_old_custom_formats = true;
          include = [
            # regular
            {template = "sonarr-quality-definition-series";}
            {template = "sonarr-v4-quality-profile-web-1080p";}
            {template = "sonarr-v4-custom-formats-web-1080p";}
          ];
        };
      };
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
        proxyPass = "http://127.0.0.1:${toString config.services.sonarr.settings.server.port}";
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
        proxyPass = "http://127.0.0.1:${toString config.services.radarr.settings.server.port}";
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

    janitorr = {
      image = "ghcr.io/schaka/janitorr:jvm-v2.0.1";
      ports = [];
      volumes = [
        "/srv/data/janitorr/config/application.yml:/config/application.yml:ro"
        "/srv/data/janitorr/logs:/logs"
        "/srv/media/movies:/srv/media/movies"
        "/srv/media/tv:/srv/media/tv"
        "/srv/media/the_will_collection:/srv/media/the_will_collection"
      ];
      user = "1000:1000";
      pull = "always";
      serviceName = "janitorr";
      extraOptions = [
        "--memory=256m"
        "--userns=host"
        "--network=host"
      ];
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
