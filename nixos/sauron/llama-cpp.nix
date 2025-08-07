{pkgs, ...}:
let 
  selected = "gpt-oss-20b";
  port = 8000;
  models = {
    gpt-oss-20b = {
      model = "/opt/models/gpt-oss-20b-F16.gguf";
      extraArgs = [
        "--jinja"
        "-ngl" "10" # default is 99 but 10 fits into 8Gi
        "--threads" "-1"
        "--ctx-size" "16384"
        "--temp" "1.0"
        "--top-p" "1.0"
        "--top-k" "0"
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
