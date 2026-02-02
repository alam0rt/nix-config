{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.vllm;
in {
  options.services.vllm = {
    enable = lib.mkEnableOption "vLLM inference server";

    model = lib.mkOption {
      type = lib.types.str;
      default = "Qwen/Qwen3-Coder-30B-A3B-Instruct";
      description = "The Hugging Face model to serve";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 8000;
      description = "Port to expose the OpenAI-compatible API";
    };

    host = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      description = "Host to bind the API to (use 0.0.0.0 for external access)";
    };

    maxModelLen = lib.mkOption {
      type = lib.types.int;
      default = 4096;
      description = "Maximum model context length";
    };

    gpuMemoryUtilization = lib.mkOption {
      type = lib.types.float;
      default = 0.90;
      description = "GPU memory utilization (0.0-1.0)";
    };

    dtype = lib.mkOption {
      type = lib.types.str;
      default = "auto";
      description = "Data type for model weights (auto, float16, bfloat16)";
    };

    backend = lib.mkOption {
      type = lib.types.enum ["rocm" "cuda"];
      default = "rocm";
      description = "GPU backend: rocm for AMD, cuda for NVIDIA";
    };

    huggingFaceTokenFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = ''
        Path to a file containing HF_TOKEN=xxx for Hugging Face authentication.
        Required for gated models.
      '';
    };

    extraArgs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "Extra arguments to pass to vLLM";
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Whether to open the firewall for the vLLM port";
    };

    cacheDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/cache/vllm";
      description = "Directory for caching downloaded models";
    };
  };

  config = lib.mkIf cfg.enable {
    # Enable podman for rootless containers
    virtualisation.podman = {
      enable = true;
      dockerCompat = true;
    };

    # ROCm support for AMD GPUs
    hardware.graphics.extraPackages = lib.mkIf (cfg.backend == "rocm") (with pkgs; [
      rocmPackages.clr.icd
    ]);

    # NVIDIA Container Toolkit for CUDA GPUs
    hardware.nvidia-container-toolkit.enable = lib.mkIf (cfg.backend == "cuda") true;

    # Ensure cache directory exists
    systemd.tmpfiles.rules = [
      "d ${cfg.cacheDir} 0755 root root -"
    ];

    # vLLM container service
    virtualisation.oci-containers.backend = "podman";
    virtualisation.oci-containers.containers.vllm = {
      image =
        if cfg.backend == "rocm"
        then "rocm/vllm:latest"
        else "vllm/vllm-openai:latest";
      autoStart = true;

      # Environment files for HF token
      environmentFiles = lib.optional (cfg.huggingFaceTokenFile != null) cfg.huggingFaceTokenFile;

      environment =
        {
          # PyTorch memory allocation optimization
          PYTORCH_CUDA_ALLOC_CONF = "expandable_segments:True";
          # Hugging Face cache location inside container
          HF_HOME = "/root/.cache/huggingface";
        }
        // lib.optionalAttrs (cfg.backend == "rocm") {
          HIP_VISIBLE_DEVICES = "0";
        };

      # Persist model cache
      volumes = [
        "${cfg.cacheDir}:/root/.cache/huggingface"
      ];

      # vLLM serve command arguments
      cmd =
        [
          "--model"
          cfg.model
          "--host"
          "0.0.0.0"
          "--port"
          "8000"
          "--max-model-len"
          (toString cfg.maxModelLen)
          "--gpu-memory-utilization"
          (toString cfg.gpuMemoryUtilization)
          "--dtype"
          cfg.dtype
        ]
        ++ cfg.extraArgs;

      # Port mapping
      ports = ["${cfg.host}:${toString cfg.port}:8000"];

      # GPU device access
      extraOptions =
        if cfg.backend == "rocm"
        then [
          "--device=/dev/kfd"
          "--device=/dev/dri"
          "--ipc=host"
          "--group-add=video"
          "--security-opt=seccomp=unconfined"
        ]
        else [
          "--gpus=all"
          "--ipc=host"
        ];

      # Pull latest image on restart
      pull = "always";
    };

    # Open firewall if requested
    networking.firewall.allowedTCPPorts = lib.mkIf cfg.openFirewall [cfg.port];
  };
}
