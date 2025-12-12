{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.server;
  ports = {
    http = 8081;
    https = 8444;
    udp = 3478;
  };
in {
  virtualisation.oci-containers.containers.unifi = {
    image = "jacobalberty/unifi";
    ports = [
      "127.0.0.1:${toString ports.http}:${toString ports.http}" # bind to localhost, accessed via nginx
      "127.0.0.1:${toString ports.https}:${toString ports.https}"
      "${toString ports.udp}:${toString ports.udp}/udp" # STUN needs to be public for device discovery
    ];
    user = "${toString config.users.users.unifi.uid}:${toString config.users.groups.unifi.gid}";
    volumes = ["/srv/data/unifi:/unifi"];
    environment = {
      TZ = "Australia/Melbourne";
      UNIFI_HTTP_PORT = "${toString ports.http}";
      UNIFI_HTTPS_PORT = "${toString ports.https}";
    };
  };

  users.users.unifi = {
    isSystemUser = true;
    group = "unifi";
  };
  users.groups.unifi = {};

  # Only STUN port needs to be public for device discovery
  networking.firewall.allowedUDPPorts = [ports.udp];

  # nginx reverse proxy with tailscaleAuth for Unifi controller
  services.nginx.virtualHosts."unifi.middleearth.samlockart.com" = {
    forceSSL = false;
    enableACME = false;
    locations."/" = {
      proxyPass = "https://127.0.0.1:${toString ports.https}";
      recommendedProxySettings = true;
      proxyWebsockets = true;
      extraConfig = ''
        proxy_ssl_verify off; # self-signed cert from unifi
      '';
    };
  };

  services.nginx.tailscaleAuth.virtualHosts = [
    "unifi.middleearth.samlockart.com"
  ];

  # cannot compile mongo so disabling
  services.unifi = {
    enable = false;
    unifiPackage = pkgs.unifi6;
    mongodbPackage = pkgs.mongodb-6_0;
  };
}
