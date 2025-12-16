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
      sshd.settings = {
        enabled = true;
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
    };
  };
}
