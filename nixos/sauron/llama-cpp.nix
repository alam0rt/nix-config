{pkgs, ...}:
let 
  selected = "qwen3-coder";
  port = 8000;
  models = {
    qwen3-coder = {
      model = "unsloth/Qwen3-Coder-30B-A3B-Instruct-GGUF:UD-Q4_K_XL";
      extraArgs = [
        "--jinja"
        "-ngl" "99"
        "--threads" "-1"
        "--n-cpu-moe" "2"
        "--ctx-size" "32684"
        "--temp" "0.7"
        "--min-p" "0.0"
        "--top-p" "0.80"
        "--top-k" "20"
        "--repeat-penalty" "1.05"
      ];
    };
    gpt-oss-20b = {
      model = "/opt/models/gpt-oss-20b-F16.gguf";
      extraArgs = [
        "--jinja"
        "-ngl" "99"
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
