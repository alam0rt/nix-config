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
  services.wyoming.faster-whisper.servers."${selected}" = {
    enable = false; # too much memory to compile cuda ATM
    uri = "tcp://0.0.0.0:${toString port}";
    model = models.${selected}.model;
    language = models.${selected}.language;
  };
}
