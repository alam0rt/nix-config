{pkgs, ...}: let
  selected = "nomic";
  port = 8000;
  models = {
    nomic = {
      model = "/opt/models/nomic.gguf";
      extraArgs = [
        "-c"
	"8192"
	"-b"
	"8192"
	"-ub"
	"8192"
	"--rope-scaling"
	"yarn"
	"--rope-freq-scale"
	".75"
        "--embeddings"
        "--pooling"
        "last"
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
