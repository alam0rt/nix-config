{ pkgs, ... }:

{
  # ollama / LLM
  services.ollama = {
    enable = true;
    package = pkgs.unstable.ollama-rocm;
    port = 11434;
    host = "0.0.0.0";
    acceleration = "rocm";
    openFirewall = true;
    loadModels = [
      "deepseek-r1:14b"
      "gemma3:12b"
    ];
    environmentVariables = {
      OLLAMA_ORIGINS = "http://sauron.middleearth.samlockart.com";
      OLLAMA_DEBUG = "true";
      OLLAMA_FLASH_ATTENTION = "1";
    };
  };
}
