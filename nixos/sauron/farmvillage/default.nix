{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.server;
  dataDir = "/srv/share/public/farmvillage";
  port = 5500;
in {
  users.users.farmvillage = {
    isSystemUser = true;
    group = "farmvillage";
    home = dataDir;
  };
  users.groups.farmvillage = {};

  # Persistent, writable data dir on the tank for ~17GB of WARC assets + player saves.
  systemd.tmpfiles.rules = [
    "d ${dataDir} 0750 farmvillage farmvillage - -"
  ];

  systemd.services.farmvillage = {
    description = "FarmVille 1 preservation server";
    after = ["network-online.target"];
    wants = ["network-online.target"];
    wantedBy = ["multi-user.target"];

    environment = {
      FARMVILLAGE_DATA_DIR = dataDir;
      FARMVILLAGE_BASE_URL = "https://farm.iced.cool";
      # Flush stdout immediately so journal logs aren't block-buffered, and
      # enable verbose AMF gateway request dumps (unset to quieten).
      PYTHONUNBUFFERED = "1";
      FARMVILLAGE_DEBUG = "1";
    };

    serviceConfig = {
      ExecStart = lib.getExe pkgs.farmvillage;
      WorkingDirectory = dataDir;
      User = "farmvillage";
      Group = "farmvillage";
      Restart = "on-failure";

      # Hardening
      NoNewPrivileges = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
      ReadWritePaths = [dataDir];
    };
  };

  services.nginx.virtualHosts."farm.iced.cool" = {
    forceSSL = true;
    useACMEHost = "iced.cool";
    locations."/" = {
      proxyPass = "http://127.0.0.1:${toString port}";
      recommendedProxySettings = true;
    };
  };
}
