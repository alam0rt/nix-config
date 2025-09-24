{
  config,
  lib,
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

  services.nginx = {
    virtualHosts."tv.samlockart.com" = {
      forceSSL = true;
      enableACME = true;
      locations."/" = {
        proxyPass = "http://127.0.0.1:8096";
        recommendedProxySettings = true;
      };
    };
    virtualHosts."tv.middleearth.samlockart.com" = {
      forceSSL = false;
      enableACME = false;
      locations."/" = {
        proxyPass = "http://127.0.0.1:8096";
        recommendedProxySettings = true;
      };
    };
    tailscaleAuth = {
      enable = true;
      virtualHosts = ["jackett.middleearth.samlockart.com"];
    };
    virtualHosts."sonarr.middleearth.samlockart.com" = {
      forceSSL = false;
      enableACME = false;
      locations."/" = {
        proxyPass = "http://127.0.0.1:8989";
        recommendedProxySettings = true;
      };
    };
    virtualHosts."jackett.middleearth.samlockart.com" = {
      forceSSL = false;
      enableACME = false;
      locations."/" = {
        proxyPass = "http://127.0.0.1:9117";
        recommendedProxySettings = true;
      };
    };
    virtualHosts."bazarr.middleearth.samlockart.com" = {
      forceSSL = false;
      enableACME = false;
      locations."/" = {
        proxyPass = "http://127.0.0.1:${toString config.services.bazarr.listenPort}";
        recommendedProxySettings = true;
      };
    };
    virtualHosts."radarr.middleearth.samlockart.com" = {
      forceSSL = false;
      enableACME = false;
      locations."/" = {
        proxyPass = "http://127.0.0.1:7878";
        recommendedProxySettings = true;
      };
    };
    virtualHosts."lidarr.middleearth.samlockart.com" = {
      forceSSL = false;
      enableACME = false;
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
    };
  };
}
