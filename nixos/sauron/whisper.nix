{pkgs, ...}:
let 
  selected = "kitten-tts";
  # disabled cuda for now as system crashed with: 'download buffer is full; consider increasing the 'download-buffer-size' setting'
  device = "cpu";
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
    enable = true; 
    uri = "tcp://0.0.0.0:${toString port}";
    device = device;
    model = models.${selected}.model;
    language = models.${selected}.language;
  };
}
