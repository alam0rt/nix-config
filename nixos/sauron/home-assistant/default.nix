{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.server;
in {
  networking.firewall.allowedTCPPorts = [
    8123 # remove once setup with reverse proxy
  ];

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
    ];
    config = {
      mqtt = {};
      # Includes dependencies for a basic setup
      # https://www.home-assistant.io/integrations/default_config/
      default_config = {};
    };
  };
}
