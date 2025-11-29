{pkgs, ...}: let
  selected = "nomic";
  port = 8000;
  models = {
    nomic = {
      model = "/opt/models/nomic.gguf";
      extraArgs = [
      ];
    };
    # You could define more models here:
    # llama-7b = { model = "..."; extraArgs = [ ... ]; };
  };
in {
  services.llama-cpp = {
    enable = true;
    package = pkgs.llamaPackages.llama-cpp;
    port = port;
    host = "0.0.0.0";
    openFirewall = true;
    model = models.${selected}.model;
    extraFlags = models.${selected}.extraArgs;
  };
}
