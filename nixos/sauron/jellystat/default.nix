{config, ...}: let
  cfg = config.server;
  port = 3004;
in {
  # --- Secrets ---
  # Contains: JWT_SECRET=<value>
  age.secrets."jellystat-env" = {
    rekeyFile = ./jellystat-env.age;
    mode = "0440";
  };

  # --- PostgreSQL ---
  services.postgresql = {
    ensureDatabases = ["jellystat"];
    ensureUsers = [
      {
        name = "jellystat";
        ensureDBOwnership = true;
      }
    ];
    # Trust local socket connections for the jellystat user to the jellystat db
    authentication = ''
      local jellystat jellystat trust
    '';
  };

  # --- Data directory ---
  systemd.tmpfiles.rules = [
    "d /srv/data/jellystat 0750 root root -"
    "d /srv/data/jellystat/backup-data 0750 root root -"
  ];

  # --- OCI Container ---
  virtualisation.oci-containers.containers.jellystat = {
    image = "cyfershepard/jellystat:latest";
    ports = ["127.0.0.1:${toString port}:3000"];
    environment = {
      POSTGRES_USER = "jellystat";
      POSTGRES_PASSWORD = "unused"; # required by app but trust auth ignores it
      POSTGRES_IP = "/run/postgresql";
      POSTGRES_PORT = "5432";
      POSTGRES_DB = "jellystat";
      TZ = "Australia/Sydney";
    };
    environmentFiles = [
      config.age.secrets."jellystat-env".path
    ];
    volumes = [
      "/run/postgresql:/run/postgresql"
      "/srv/data/jellystat/backup-data:/app/backend/backup-data"
    ];
    pull = "always";
  };

  # Ensure the container starts after PostgreSQL
  systemd.services.podman-jellystat.after = ["postgresql.service"];
  systemd.services.podman-jellystat.requires = ["postgresql.service"];

  # --- Nginx reverse proxy ---
  services.nginx.virtualHosts."jellystat.${cfg.domain}" = {
    forceSSL = true;
    useACMEHost = cfg.domain;
    locations."/" = {
      proxyPass = "http://127.0.0.1:${toString port}";
      recommendedProxySettings = true;
    };
  };

  services.nginx.tailscaleAuth.virtualHosts = [
    "jellystat.${cfg.domain}"
  ];
}
