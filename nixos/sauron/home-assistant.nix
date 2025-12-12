{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.server;
in {
  # Mosquitto only accessible from localhost/tailscale (trusted interface)
  # Home Assistant accessed via nginx reverse proxy with tailscaleAuth

  services.mosquitto = {
    enable = true;
    listeners = [
      {
        address = "127.0.0.1"; # bind to localhost only
        port = 1883;
        acl = ["pattern readwrite #"];
        omitPasswordAuth = true;
        settings.allow_anonymous = true; # safe since bound to localhost
      }
    ];
  };

  services.home-assistant = {
    enable = true;
    extraComponents = [
      # Components required to complete the onboarding
      "esphome"
      "met"
      "radio_browser"
      "mqtt"
      "jellyfin"
      "unifi"
    ];
    config = {
      mqtt = {};
      # Includes dependencies for a basic setup
      # https://www.home-assistant.io/integrations/default_config/
      default_config = {};
      http = {
        server_host = "127.0.0.1"; # bind to localhost, accessed via nginx
        use_x_forwarded_for = true;
        trusted_proxies = ["127.0.0.1" "::1"];
      };
    };
  };

  # nginx reverse proxy for Home Assistant with tailscaleAuth
  services.nginx.virtualHosts."ha.middleearth.samlockart.com" = {
    forceSSL = false;
    enableACME = false;
    locations."/" = {
      proxyPass = "http://127.0.0.1:8123";
      proxyWebsockets = true;
      recommendedProxySettings = true;
    };
  };

  # Add to tailscaleAuth protected hosts
  services.nginx.tailscaleAuth.virtualHosts = [
    "ha.middleearth.samlockart.com"
  ];
}
