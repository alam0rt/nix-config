{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.server;
  # services.nginx.tailscaleAuth hardcodes an `internal` `location /auth` for its
  # auth_request endpoint. That is a *prefix* match, so it also captures Home
  # Assistant's own /auth/authorize, /auth/token and /auth/login_flow — and
  # `internal` makes nginx answer external requests to them with 404, which
  # breaks both login and onboarding. No other vhost hits this because no other
  # proxied app serves its own /auth/* namespace.
  #
  # `^~ /auth/` is a longer prefix and takes precedence for /auth/<anything>,
  # while the auth_request subrequest URI is exactly `/auth` (no trailing
  # slash), so it still lands on the module's internal location.
  tailscaleAuthRequest = ''
    auth_request /auth;
    auth_request_set $auth_user $upstream_http_tailscale_user;
    auth_request_set $auth_name $upstream_http_tailscale_name;
    auth_request_set $auth_login $upstream_http_tailscale_login;
    auth_request_set $auth_tailnet $upstream_http_tailscale_tailnet;
    auth_request_set $auth_profile_picture $upstream_http_tailscale_profile_picture;

    proxy_set_header X-Webauth-User "$auth_user";
    proxy_set_header X-Webauth-Name "$auth_name";
    proxy_set_header X-Webauth-Login "$auth_login";
    proxy_set_header X-Webauth-Tailnet "$auth_tailnet";
    proxy_set_header X-Webauth-Profile-Picture "$auth_profile_picture";
  '';
in {
  services.nginx.virtualHosts."home-assistant.${cfg.domain}" = {
    forceSSL = true;
    useACMEHost = cfg.domain;
    locations."/" = {
      proxyPass = "http://127.0.0.1:8123";
      proxyWebsockets = true;
      recommendedProxySettings = true;
    };
    locations."^~ /auth/" = {
      proxyPass = "http://127.0.0.1:8123";
      proxyWebsockets = true;
      recommendedProxySettings = true;
      extraConfig = tailscaleAuthRequest;
    };
    extraConfig = ''
      proxy_buffering off;
    '';
  };

  services.mosquitto = {
    enable = true;
    listeners = [
      {
        address = "127.0.0.1";
        acl = ["pattern readwrite #"];
        omitPasswordAuth = true;
        settings.allow_anonymous = true;
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
      # Discovery (SSDP/MQTT) keeps opening config flows for these; without the
      # component installed the flow raises UnknownHandler, which breaks the
      # onboarding "integration" step and spams the log.
      "denonavr"
      "roborock"
      # google_translate TTS config entry fails to set up without gtts.
      "google_translate"
      # Room-level BLE presence. bermuda's manifest declares these three as
      # hard dependencies; private_ble_device is what resolves the rotating
      # BLE addresses that iOS/Android use, via each device's IRK.
      "bluetooth"
      "bluetooth_adapters"
      "private_ble_device"
    ];

    # Bermuda is not in pkgs.home-assistant-custom-components, so it is
    # packaged locally in pkgs/bermuda and exposed by the `additions` overlay.
    customComponents = [pkgs.bermuda];
    config = {
      mqtt = {};
      http = {
        server_host = "127.0.0.1";
        trusted_proxies = ["127.0.0.1"];
        use_x_forwarded_for = true;
      };
      # Includes dependencies for a basic setup
      # https://www.home-assistant.io/integrations/default_config/
      default_config = {};
    };
  };
}
