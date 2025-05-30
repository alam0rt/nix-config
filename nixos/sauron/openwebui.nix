{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.server;
in {
  services.open-webui = {
    enable = true;
    package = pkgs.unstable.open-webui;
    openFirewall = true;
    port = 11111;
    environment = {
      OLLAMA_API_BASE_URL = "http://desktop:11434";
      # for vllm use
      # OPENAI_API_BASE_URL = "http://desktop:8000";
      # ENABLE_OPENAI_API = "true";
      # todo: fill out with more of the settings i've overriden in the ui
    };
  };

  services.nginx.virtualHosts."open-webui.middleearth.samlockart.com" = {
    forceSSL = false;
    enableACME = false;
    locations."/" = {
      proxyPass = "http://127.0.0.1:${toString config.services.open-webui.port}";
      recommendedProxySettings = true;
      proxyWebsockets = true;
    };
  };
}
