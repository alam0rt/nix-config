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
      "${toString ports.http}:${toString ports.http}"
      "${toString ports.https}:${toString ports.https}"
      "${toString ports.udp}:${toString ports.udp}/udp"
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

  networking.firewall = {
    allowedTCPPorts = [
      ports.http
      ports.https
    ];
    allowedUDPPorts = [ports.udp];
  };

  # cannot compile mongo so disabling
  services.unifi = {
    enable = false;
    unifiPackage = pkgs.unifi6;
    mongodbPackage = pkgs.mongodb-6_0;
  };
}
