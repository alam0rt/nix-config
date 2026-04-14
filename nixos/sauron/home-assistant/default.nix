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
    ];
    config = {
      mqtt = {};
      # Includes dependencies for a basic setup
      # https://www.home-assistant.io/integrations/default_config/
      default_config = {};
    };
  };
}
