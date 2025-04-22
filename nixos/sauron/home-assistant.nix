{ config
, lib
, pkgs
, ... }:
let cfg = config.server;
in {
  networking.firewall.allowedTCPPorts = [
    8123 # remove once setup with reverse proxy
    1883 # mosquitto
  ];

  services.mosquitto = {
    enable = true;
    listeners = [
      {
        acl = [ "pattern readwrite #" ];
        omitPasswordAuth = true;
        settings.allow_anonymous = true; # TODO: lock down
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