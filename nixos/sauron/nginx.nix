<<<<<<< HEAD
{
  config,
  pkgs,
  ...
}: let
=======
{config, lib, ...}: let
>>>>>>> main
  cfg = config.server;

  # Assertion: ensure all middleearth vhosts are protected by tailscale auth
  allVhosts = builtins.attrNames config.services.nginx.virtualHosts;
  middleearthVhosts = builtins.filter
    (name: lib.hasSuffix ".middleearth.samlockart.com" name)
    allVhosts;
  tailscaleVhosts = config.services.nginx.tailscaleAuth.virtualHosts;
  missingVhosts = builtins.filter
    (name: !(builtins.elem name tailscaleVhosts))
    middleearthVhosts;
in {
  assertions = [{
    assertion = missingVhosts == [];
    message = ''
      The following middleearth.samlockart.com virtualHosts are not protected by tailscaleAuth:
        ${lib.concatStringsSep "\n    " missingVhosts}
      Add them to services.nginx.tailscaleAuth.virtualHosts in nginx.nix
    '';
  }];
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

    tailscaleAuth = {
      enable = true;
      virtualHosts = [
        "jackett.middleearth.samlockart.com"
        "sonarr.middleearth.samlockart.com"
        "radarr.middleearth.samlockart.com"
        "bazarr.middleearth.samlockart.com"
        "lidarr.middleearth.samlockart.com"
        "open-webui.middleearth.samlockart.com"
        "maubot.middleearth.samlockart.com"
        "sync.middleearth.samlockart.com"
        "transmission.middleearth.samlockart.com"
        "grafana.middleearth.samlockart.com"
        "tv.middleearth.samlockart.com"
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
