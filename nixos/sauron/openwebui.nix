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
      # OLLAMA_API_BASE_URL = "http://desktop:11434";
      OPENAI_API_BASE_URL = "http://127.0.0.1:8000";
      # WHISPER_MODEL = "/opt/models/kitten_tts_nano_v0_1.onnx";
      AUDIO_TTS_OPENAI_API_BASE_URL = "http://127.0.0.1:8001" # whisper.nix
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
