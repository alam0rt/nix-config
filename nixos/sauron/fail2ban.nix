{
  config,
  lib,
  ...
}: {
  services.fail2ban = {
    enable = true;

    # Max retry before ban
    maxretry = 5;

    # Ban time (10 minutes default)
    bantime = "10m";

    # Ignore local and tailscale networks
    ignoreIP = [
      "10.0.0.0/8"
      "172.16.0.0/12"
      "192.168.0.0/16"
      "100.64.0.0/10" # Tailscale CGNAT range
    ];

    jails = {
      # SSH jail - NixOS pre-configures this, just customize settings
      sshd.settings = {
        enabled = true;
        maxretry = 3;
        findtime = 3600; # 1 hour
        bantime = 3600; # 1 hour
      };

      # Nginx bad bots and scanners
      nginx-botsearch.settings = {
        enabled = true;
        port = "http,https";
        filter = "nginx-botsearch";
        logpath = "/var/log/nginx/access.log";
        backend = "auto";
        maxretry = 2;
        findtime = 60; # 1 minute
        bantime = 86400; # 1 day
      };

      # Nginx HTTP auth failures
      nginx-http-auth.settings = {
        enabled = true;
        port = "http,https";
        filter = "nginx-http-auth";
        logpath = "/var/log/nginx/error.log";
        backend = "auto";
        maxretry = 3;
        findtime = 60; # 1 minute
        bantime = 3600; # 1 hour
      };

      # Nginx URL probing (wp-admin, phpmyadmin, .env, .git, etc)
      nginx-url-probe.settings = {
        enabled = true;
        port = "http,https";
        filter = "nginx-url-probe";
        logpath = "/var/log/nginx/access.log";
        backend = "auto";
        maxretry = 5;
        findtime = 600; # 10 minutes
        bantime = 86400; # 1 day
      };

      # Vaultwarden/Bitwarden login failures
      vaultwarden.settings = {
        enabled = true;
        port = "http,https";
        filter = "vaultwarden";
        logpath = "/var/log/vaultwarden/vaultwarden.log";
        backend = "auto";
        maxretry = 3;
        findtime = 3600; # 1 hour
        bantime = 86400; # 1 day
      };
    };
  };
}
