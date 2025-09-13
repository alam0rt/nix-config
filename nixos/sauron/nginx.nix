{
  config,
  ...
}: let
  cfg = config.server;
in {
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

  ## services
  services.tailscaleAuth = {
    enable = true;
  };

  users.users.nginx.isSystemUser = true;

  services.nginx = {
    enable = true;

    logError = "stderr info";

    # recommended settings
    recommendedProxySettings = true;
    recommendedTlsSettings = true;
    recommendedGzipSettings = true;
    recommendedOptimisation = true;

    # Only allow PFS-enabled ciphers with AES256
    sslCiphers = "AES256+EECDH:AES256+EDH:!aNULL";

    # whitelisting
    commonHttpConfig = ''
      # TODO: block known bad ranges
      #allow 192.168.0.0/24;
      #allow 10.0.0.0/16;
      #allow 173.245.48.0/20;
      #allow 103.21.244.0/22;
      #allow 103.22.200.0/22;
      #allow 103.31.4.0/22;
      #allow 141.101.64.0/18;
      #allow 108.162.192.0/18;
      #allow 190.93.240.0/20;
      #allow 188.114.96.0/20;
      #allow 197.234.240.0/22;
      #allow 198.41.128.0/17;
      #allow 162.158.0.0/15;
      #allow 104.16.0.0/13;
      #allow 104.24.0.0/14;
      #allow 172.64.0.0/13;
      #allow 131.0.72.0/22;
      #deny all;

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

    virtualHosts."www.iced.cool" = {
      # catch all
      forceSSL = true;
      enableACME = true;
      default = true;
      locations."/" = {
        return = 404;
      };
    };
    virtualHosts."open-webui.middleearth.samlockart.com" = {
      forceSSL = false;
      enableACME = false;
      locations."/" = {
        proxyPass = "http://127.0.0.1:${toString config.services.open-webui.port}";
        recommendedProxySettings = true;
      };
    };

    virtualHosts."sync.middleearth.samlockart.com" = {
      forceSSL = false;
      enableACME = false;
      locations."/" = {
        proxyPass = "http://127.0.0.1:8384";
      };
    };
  };
}
