{
  config,
  lib,
  ...
}: let
  cfg = config.server;

  # Assertion: ensure all middleearth vhosts are protected by tailscale auth
  allVhosts = builtins.attrNames config.services.nginx.virtualHosts;
  middleearthVhosts =
    builtins.filter
    (name: lib.hasSuffix ".${cfg.domain}" name)
    allVhosts;
  tailscaleVhosts = config.services.nginx.tailscaleAuth.virtualHosts;
  missingVhosts =
    builtins.filter
    (name: !(builtins.elem name tailscaleVhosts))
    middleearthVhosts;
in {
  assertions = [
    {
      assertion = missingVhosts == [];
      message = ''
        The following ${cfg.domain} virtualHosts are not protected by tailscaleAuth:
          ${lib.concatStringsSep "\n    " missingVhosts}
        Add them to services.nginx.tailscaleAuth.virtualHosts in nginx.nix
      '';
    }
  ];
  networking.firewall = {
    allowedTCPPorts = [
      80
      443
      8080
      8443
    ];
  };

  # accept the EULA
  security.acme.defaults.email = "sam@samlockart.com";
  security.acme.acceptTerms = true;

  age.secrets.cloudflare-api-token.rekeyFile = ./cloudflare-api-token.age;

  security.acme = {
    certs = {
      "${cfg.domain}" = {
        domain = "*.${cfg.domain}";
        group = "nginx";
        dnsProvider = "cloudflare";
        # location of your CLOUDFLARE_DNS_API_TOKEN=[value]
        # https://www.freedesktop.org/software/systemd/man/latest/systemd.exec.html#EnvironmentFile=
        environmentFile = config.age.secrets.cloudflare-api-token.path;
      };
    };
  };

  ## services
  services.tailscaleAuth = {
    enable = true;
  };

  users.users.nginx.isSystemUser = true;

  services.nginx = {
    enable = true;

    logError = "stderr info";

    tailscaleAuth = {
      enable = true;
      virtualHosts = [
        "jackett.${cfg.domain}"
        "sonarr.${cfg.domain}"
        "radarr.${cfg.domain}"
        "bazarr.${cfg.domain}"
        "lidarr.${cfg.domain}"
        "open-webui.${cfg.domain}"
        "maubot.${cfg.domain}"
        "sync.${cfg.domain}"
        "transmission.${cfg.domain}"
        "grafana.${cfg.domain}"
        "tv.${cfg.domain}"
      ];
    };

    # recommended settings
    recommendedProxySettings = true;
    recommendedTlsSettings = true;
    recommendedGzipSettings = true;
    recommendedOptimisation = true;

    # Only allow PFS-enabled ciphers with AES256
    sslCiphers = "AES256+EECDH:AES256+EDH:!aNULL";

    # whitelisting
    commonHttpConfig = ''
      # Add HSTS header with preloading to HTTPS requests.
      # Adding this header to HTTP requests is discouraged
      map $scheme $hsts_header {
          https   "max-age=31536000; includeSubdomains; preload";
      }
      add_header Strict-Transport-Security $hsts_header;

      # Enable CSP for your services.
      #add_header Content-Security-Policy "script-src 'self'; object-src 'none'; base-uri 'none';" always;

      # Minimize information leaked to other domains
      add_header 'Referrer-Policy' 'origin-when-cross-origin';

      # Disable embedding as a frame
      # breaks jellyfin on webOS
      # https://jellyfin.org/docs/general/networking/nginx/
      # - saml
      # add_header X-Frame-Options DENY;

      # Prevent injection of code in other mime types (XSS Attacks)
      add_header X-Content-Type-Options nosniff;

      # Enable XSS protection of the browser.
      # May be unnecessary when CSP is configured properly (see above)
      add_header X-XSS-Protection "1; mode=block";

      # This might create errors - might be breaking Grafana
      # proxy_cookie_path / "/; secure; HttpOnly; SameSite=strict";
    '';

    # Localhost-only status endpoint for prometheus nginx exporter
    virtualHosts."localhost" = {
      listen = [
        { addr = "127.0.0.1"; port = 80; }
        { addr = "[::1]"; port = 80; }
      ];
      locations."/nginx_status" = {
        extraConfig = ''
          stub_status on;
          access_log off;
          allow 127.0.0.1;
          allow ::1;
          deny all;
        '';
      };
    };

    virtualHosts."www.iced.cool" = {
      # catch all
      forceSSL = true;
      enableACME = true;
      default = true;
      locations."/" = {
        return = 404;
      };
    };
  };
}
