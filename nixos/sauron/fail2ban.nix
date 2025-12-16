{
  config,
  lib,
  ...
}: {
  services.fail2ban = {
    enable = true;

    # Max retry before ban
    maxretry = 5;

    # Ban time (10 minutes default, increase for repeat offenders)
    bantime = "10m";

    # Time window to count failures
    findtime = "10m";

    # Ban repeat offenders for longer
    bantime-increment = {
      enable = true;
      multipliers = "1 2 4 8 16 32 64";
      maxtime = "168h"; # 1 week max
      overalljails = true; # count across all jails
    };

    # Ignore local and tailscale networks
    ignoreIP = [
      "127.0.0.0/8"
      "::1"
      "192.168.0.0/24"
      "100.64.0.0/10" # Tailscale CGNAT range
    ];

    jails = {
      # SSH jail (uses systemd journal)
      sshd = {
        settings = {
          enabled = true;
          port = "ssh";
          filter = "sshd";
          maxretry = 3;
          findtime = "1h";
          bantime = "1h";
        };
      };

      # Nginx bad bots and scanners
      nginx-botsearch = {
        settings = {
          enabled = true;
          port = "http,https";
          filter = "nginx-botsearch";
          logpath = "/var/log/nginx/access.log";
          maxretry = 2;
          findtime = "1m";
          bantime = "1d";
        };
      };

      # Nginx HTTP auth failures
      nginx-http-auth = {
        settings = {
          enabled = true;
          port = "http,https";
          filter = "nginx-http-auth";
          logpath = "/var/log/nginx/error.log";
          maxretry = 3;
          findtime = "1m";
          bantime = "1h";
        };
      };

      # Vaultwarden/Bitwarden login failures
      vaultwarden = {
        settings = {
          enabled = true;
          port = "http,https";
          filter = "vaultwarden";
          logpath = "/var/log/vaultwarden/vaultwarden.log";
          maxretry = 3;
          findtime = "1h";
          bantime = "1d";
        };
      };
    };
  };

  # Custom filter for Vaultwarden
  environment.etc."fail2ban/filter.d/vaultwarden.local".text = ''
    [Definition]
    failregex = ^.*Username or password is incorrect\. Try again\. IP: <ADDR>\. Username:.*$
    ignoreregex =
  '';
}
