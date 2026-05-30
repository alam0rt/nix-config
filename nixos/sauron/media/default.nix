{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.server;

  janitorrConfig = pkgs.writeText "janitorr-application.yml" ''
    server:
      port: 8978

    logging:
      level:
        com.github.schaka: INFO
      file:
        name: "/logs/janitorr.log"

    file-system:
      access: true
      validate-seeding: true
      from-scratch: true
      leaving-soon-dir: "/srv/data/janitorr/leaving-soon"
      media-server-leaving-soon-dir: "/srv/data/janitorr/leaving-soon"
      free-space-check-dir: "/srv/media"

    clients:
      sonarr:
        enabled: true
        url: "http://127.0.0.1:${toString config.services.sonarr.settings.server.port}"
      radarr:
        enabled: true
        url: "http://127.0.0.1:${toString config.services.radarr.settings.server.port}"
      jellyfin:
        enabled: true
        url: "http://127.0.0.1:8096"
        username: ""
        password: ""
      jellyseerr:
        enabled: true
        url: "http://127.0.0.1:${toString config.services.jellyseerr.port}"

    application:
      dry-run: true
      run-once: true
      whole-tv-show: false
      leaving-soon: 7d
      leaving-soon-threshold-offset-percent: 5
      exclusion-tags:
        - "kino"
      media-deletion:
        enabled: true
        movie-expiration:
          5: 30d
          10: 60d
          15: 90d
          20: 120d
        season-expiration:
          5: 30d
          10: 60d
          15: 90d
          20: 120d
      tag-based-deletion:
        enabled: false
        minimum-free-disk-percent: 100
        schedules: []
      episode-deletion:
        enabled: false
  '';
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
    mode = "0440";
  };

  age.secrets."radarr-api-key" = {
    rekeyFile = ./radarr-api-key.age;
    owner = "recyclarr";
    group = "recyclarr";
    mode = "0440";
  };

  age.secrets."janitorr-env" = {
    rekeyFile = ./janitorr-env.age;
    mode = "0440";
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
      locations."/metrics" = {
        extraConfig = ''
          allow 127.0.0.1;
          deny all;
        '';
        proxyPass = "http://127.0.0.1:8096";
        recommendedProxySettings = true;
      };
      locations."/" = {
        proxyPass = "http://127.0.0.1:8096";
        recommendedProxySettings = true;
      };
      locations."~* /Users/AuthenticateByName" = {
        proxyPass = "http://127.0.0.1:8096";
        recommendedProxySettings = true;
        extraConfig = ''
          limit_req zone=login burst=3 nodelay;
        '';
      };
    };
    virtualHosts."requests.iced.cool" = {
      forceSSL = true;
      useACMEHost = "iced.cool";
      locations."/" = {
        proxyPass = "http://127.0.0.1:${toString config.services.jellyseerr.port}";
        recommendedProxySettings = true;
      };
      locations."/api/v1/auth/local" = {
        proxyPass = "http://127.0.0.1:${toString config.services.jellyseerr.port}";
        recommendedProxySettings = true;
        extraConfig = ''
          limit_req zone=login burst=3 nodelay;
        '';
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
    virtualHosts."prowlarr.${cfg.domain}" = {
      forceSSL = true;
      useACMEHost = cfg.domain;
      locations."/" = {
        proxyPass = "http://127.0.0.1:${toString config.services.prowlarr.settings.server.port}";
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
  users.users.lidarr.extraGroups = ["qbittorrent"];

  services.radarr = {
    enable = true;
    dataDir = "/srv/data/radarr";
    openFirewall = true;
  };
  users.users.radarr.extraGroups = ["qbittorrent"];

  services.sonarr = {
    enable = true;
    dataDir = "/srv/data/sonarr";
    openFirewall = true;
  };
  users.users.sonarr.extraGroups = ["qbittorrent"];

  services.jackett = {
    enable = true;
    dataDir = "/srv/data/jackett";
    package = pkgs.unstable.jackett;
    openFirewall = true;
  };

  services.prowlarr = {
    enable = true;
    dataDir = "/srv/data/prowlarr";
    package = pkgs.unstable.prowlarr;
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

  users.users.janitorr = {
    uid = 977;
    isSystemUser = true;
    group = "janitorr";
    description = "Janitorr media cleanup";
    home = "/srv/data/janitorr";
    createHome = true;
    extraGroups = ["sonarr" "radarr"];
  };
  users.groups.janitorr.gid = 968;

  systemd.tmpfiles.rules = [
    "d /srv/data/janitorr 0750 janitorr janitorr -"
    "d /srv/data/janitorr/logs 0750 janitorr janitorr -"
    "d /srv/data/janitorr/leaving-soon 0750 janitorr janitorr -"
  ];

  systemd.services.janitorr = {
    serviceConfig = {
      Type = lib.mkForce "oneshot";
      Restart = lib.mkForce "no";
    };
  };

  systemd.timers.janitorr = {
    description = "Weekly janitorr media cleanup";
    # wantedBy = ["timers.target"];  # enable after janitorr-env.age is created, rekey is run, and dry-run logs verified
    timerConfig = {
      OnCalendar = "Sun 03:00:00";
      Persistent = true;
      Unit = "janitorr.service";
    };
  };

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
      image = "ghcr.io/schaka/janitorr:jvm-stable";
      volumes = [
        "${janitorrConfig}:/config/application.yml:ro"
        "/srv/data/janitorr/logs:/logs"
        "/srv/data/janitorr/leaving-soon:/srv/data/janitorr/leaving-soon"
        "/srv/media:/srv/media"
      ];
      environmentFiles = [config.age.secrets."janitorr-env".path];
      user = "${toString config.users.users.janitorr.uid}:${toString config.users.groups.janitorr.gid}";
      pull = "always";
      serviceName = "janitorr";
      autoStart = false;
      extraOptions = [
        "--memory=256m"
        "--userns=host"
        "--network=host"
      ];
    };

    flaresolverr = {
      image = "ghcr.io/flaresolverr/flaresolverr:v3.4.6";
      ports = ["127.0.0.1:8191:8191"];
      serviceName = "flaresolverr";
    };
  };
}
