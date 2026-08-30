{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.server;
in {
  services.nginx.virtualHosts."home-assistant.${cfg.domain}" = {
    forceSSL = true;
    useACMEHost = cfg.domain;
    locations."/" = {
      proxyPass = "http://127.0.0.1:8123";
      proxyWebsockets = true;
      recommendedProxySettings = true;
    };
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
      # Includes dependencies for a basic setup
      # https://www.home-assistant.io/integrations/default_config/
      default_config = {};
    };
  };
}
