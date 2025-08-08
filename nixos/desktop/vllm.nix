{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = {
    model = "Qwen/Qwen3-Coder-30B-A3B-Instruct";
    image = "rocm/vllm:latest";
    port = 8000;
  };
in {
  age.secrets.hugging-face-ro-token.file = ../../secrets/hugging-face-ro-token.age;
  virtualisation.oci-containers.containers = {
    vllm = {
      autoStart = true;
      preRunExtraOptions = [
        "--storage-driver=overlay" # not sure why, but this gets blanked out
      ];
      environmentFiles = [config.age.secrets.hugging-face-ro-token.path];
      environment = {
        PYTORCH_CUDA_ALLOC_CONF = "expandable_segments:True";
      };
      # https://docs.vllm.ai/en/v0.6.5/getting_started/amd-installation.html
      extraOptions = [
        "--ipc=host"
        "--network=host"
        "--group-add=video"
        "--cap-add=SYS_PTRACE"
        "--security-opt" "seccomp=unconfined"
        "--device" "/dev/kfd"
        "--device" "/dev/dri"
      ];
      cmd = [
        "vllm"
        "serve"
        cfg.model
        "--gpu-memory-utilization=0.8"
        "--cpu-offload-gb=8"
        "--enable-expert-parallel"
      ];
      image = cfg.image;
      ports = ["${toString cfg.port}:8000"];
    };
  };
}
