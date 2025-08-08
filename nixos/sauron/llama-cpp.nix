{pkgs, ...}:
let 
  selected = "DeepSeek-R1-0528-Qwen3-8B-BF16";
  port = 8000;
  models = {
    DeepSeek-R1-0528-Qwen3-8B-BF16 = {
      model = "/opt/models/DeepSeek-R1-0528-Qwen3-8B-BF16.gguf";
      extraArgs = [
        "--jinja"
        # "-ngl" "8"
        "--threads" "-1"
        "--n-cpu-moe" "6"
        "--ctx-size" "32684"
        "--temp" "0.7"
        "--min-p" "0.0"
        "--top-p" "0.80"
        "--top-k" "20"
        "--repeat-penalty" "1.05"
      ];
    };
    gpt-oss-20b-F16 = {
      model = "/opt/models/gpt-oss-20b-F16.gguf";
      extraArgs = [
        "--jinja"
        "-ngl" "8" # offload 8 layers to GPU
        "--n-cpu-moe" "16" # remaining can go to CPU
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
