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

  # Custom filters
  environment.etc = {
    # Filter for Vaultwarden login failures
    "fail2ban/filter.d/vaultwarden.local".text = ''
      [Definition]
      failregex = ^.*Username or password is incorrect\. Try again\. IP: <ADDR>\. Username:.*$
      ignoreregex =
    '';

    # Filter for URL probing attacks
    "fail2ban/filter.d/nginx-url-probe.local".text = ''
      [Definition]
      failregex = ^<HOST>.*(GET /(wp-|admin|boaform|phpmyadmin|\.env|\.git)|\.(dll|so|cfm|asp)|(\?|&)(=PHPB8B5F2A0-3C92-11d3-A3A9-4C7B08C10000|=PHPE9568F36-D428-11d2-A769-00AA001ACF42|=PHPE9568F35-D428-11d2-A769-00AA001ACF42|=PHPE9568F34-D428-11d2-A769-00AA001ACF42)|\\x[0-9a-zA-Z]{2})
      ignoreregex =
    '';
  };
}
