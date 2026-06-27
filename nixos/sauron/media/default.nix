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
        url: "http://127.0.0.1:${toString config.services.seerr.port}"

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

  services.seerr = {
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
          # recyclarr v8's official config-templates repo no longer ships
          # include templates, so the old `include: hd-bluray-web` no longer
          # resolves. Inline the "HD Bluray + WEB" template instead (trash-ids
          # mirror radarr/templates/hd-bluray-web.yml from config-templates).
          quality_definition = {type = "movie";};
          quality_profiles = [
            {
              trash_id = "d1d67249d3890e49bc12e275d989a7e9"; # HD Bluray + WEB
              reset_unmatched_scores = {enabled = true;};
            }
          ];
          custom_format_groups = {
            add = [
              {
                trash_id = "f8bf8eab4617f12dfdbd16303d8da245"; # [Optional] Golden Rule HD
                select = ["dc98083864ea246d05a42df0d05f81cc"]; # x265 (HD)
              }
              {
                trash_id = "a3ac6af01d78e4f21fcb75f601ac96df"; # [Unwanted] Unwanted Formats
                select = [
                  "b8cd450cbfa689c0259a01d9e29ba3d6" # 3D
                  "cae4ca30163749b891686f95532519bd" # AV1
                  "b6832f586342ef70d9c128d40c07b872" # Bad Dual Groups
                  "cc444569854e9de0b084ab2b8b1532b2" # Black and White Editions
                  "ed38b889b31be83fda192888e2286d83" # BR-DISK
                  "0a3f082873eb454bde444150b70253cc" # Extras
                  "e6886871085226c3da1830830146846c" # Generated Dynamic HDR
                  "90a6f9a284dff5103f6346090e6280c8" # LQ
                  "e204b80c87be9497a8a6eaff48f72905" # LQ (Release Title)
                  "712d74cd88bceb883ee32f773656b1f5" # Sing-Along Versions
                  "bfd8eb01832d646a0a89c4deb46f8564" # Upscaled
                ];
              }
            ];
          };
        };
      };
      sonarr = {
        tv = {
          api_key = {
            _secret = config.age.secrets."sonarr-api-key".path;
          };
          base_url = "http://localhost:${toString config.services.sonarr.settings.server.port}/";
          delete_old_custom_formats = true;
          # Inlined "WEB-1080p" template (see radarr note above); mirrors
          # sonarr/templates/web-1080p.yml from the config-templates repo.
          quality_definition = {type = "series";};
          quality_profiles = [
            {
              trash_id = "72dae194fc92bf828f32cde7744e51a1"; # WEB-1080p
              reset_unmatched_scores = {enabled = true;};
            }
          ];
          custom_format_groups = {
            add = [
              {
                trash_id = "158188097a58d7687dee647e04af0da3"; # [Optional] Golden Rule HD
                select = ["47435ece6b99a0b477caf360e79ba0bb"]; # x265 (HD)
              }
              {
                trash_id = "85fae4a2294965b75710ef2989c850eb"; # [Streaming Services] HD/UHD boost
                select = [
                  "218e93e5702f44a68ad9e3c6ba87d2f0" # HD Streaming Boost
                  "43b3cf48cb385cd3eac608ee6bca7f09" # UHD Streaming Boost
                ];
              }
              {
                trash_id = "59c3af66780d08332fdc64e68297098f"; # [Unwanted] Unwanted Formats
                select = [
                  "15a05bc7c1a36e2b57fd628f8977e2fc" # AV1
                  "32b367365729d530ca1c124a0b180c64" # Bad Dual Groups
                  "85c61753df5da1fb2aab6f2a47426b09" # BR-DISK
                  "6f808933a71bd9666531610cb8c059cc" # BR-DISK (BTN)
                  "fbcb31d8dabd2a319072b84fc0b7249c" # Extras
                  "9c11cd3f07101cdba90a2d81cf0e56b4" # LQ
                  "e2315f990da2e2cbfc9fa5b7a6fcfe48" # LQ (Release Title)
                  "23297a736ca77c0fc8e70f8edd7ee56c" # Upscaled
                ];
              }
            ];
          };
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
        proxyPass = "http://127.0.0.1:${toString config.services.seerr.port}";
        recommendedProxySettings = true;
      };
      locations."/api/v1/auth/local" = {
        proxyPass = "http://127.0.0.1:${toString config.services.seerr.port}";
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
        proxyPass = "http://127.0.0.1:${toString config.services.seerr.port}";
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
    # Default system-user homeMode is 0700, which blocks jellyfin (in the
    # janitorr group) from traversing /srv/data/janitorr to register the
    # Leaving Soon virtual folders.
    homeMode = "0750";
    extraGroups = ["sonarr" "radarr"];
  };
  users.groups.janitorr.gid = 968;

  # Jellyfin must be able to traverse /srv/data/janitorr/leaving-soon to
  # register the "Leaving Soon" virtual folders — without group membership the
  # Library/VirtualFolders POST fails with 400 "Error processing request."
  users.users.jellyfin.extraGroups = ["janitorr"];

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
      image = "ghcr.io/flaresolverr/flaresolverr:v3.5.0";
      ports = ["127.0.0.1:8191:8191"];
      serviceName = "flaresolverr";
      environment = {
        LOG_LEVEL = "debug";
        LOG_HTML = "true";
      };
    };
  };
}
