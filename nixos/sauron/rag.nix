{pkgs, ...}: let
  selected = "kitten-tts";
  port = 8001;
  models = {
    kitten-tts = {
      model = "/opt/models/kitten_tts_nano_v0_1.onnx";
      language = "en";
    };
    # You could define more models here:
    # llama-7b = { model = "..."; extraArgs = [ ... ]; };
  };
in {

  environment.systemPackages = with pkgs; [postgresql17Packages.pgvector];

  config.services.postgresql = {
    enable = true;
    extensions = [ "pgvector" ];
    ensureDatabases = [ "vector" ];
    authentication = pkgs.lib.mkOverride 10 ''
      #type database  DBuser  auth-method
      local all       all     trust
    '';
  };
}
