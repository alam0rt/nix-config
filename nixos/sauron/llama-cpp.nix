{pkgs, ...}:
let 
  selected = "DeepSeek-R1-0528-Qwen3-8B-Q6_K";
  port = 8000;
  models = {
    DeepSeek-R1-0528-Qwen3-8B-Q6_K = {
      model = "/opt/models/DeepSeek-R1-0528-Qwen3-8B-Q6_K.gguf";
      extraArgs = [
        "--cache-type-k" "q4_0"
        "--threads" "-1"
        "--n-gpu-layers" "99"
        "--prio" "3"
        "--temp" "0.6"
        "--top_p" "0.95"
        "--min_p" "0.01"
        "--ctx-size" "8192"
        "--seed" "3407"
        "-ot" ".ffn_.*_exps.=CPU"
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
