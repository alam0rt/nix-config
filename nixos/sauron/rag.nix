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
  config.environment.systemPackages = with pkgs; [ pkgs.postgresql_16 ]; # for psql
  config.services.postgresql = {
    enable = true;
    extensions = [ pkgs.postgresql16Packages.pgvector ];
    package = pkgs.postgresql_16;
    ensureDatabases = [ "vector" ];
    authentication = pkgs.lib.mkOverride 10 ''
      #type database  DBuser  auth-method
      local all       all     trust
    '';
  };
}
