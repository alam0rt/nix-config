{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.vllm;

  # Convert serverArgs attrset to CLI flags
  # e.g. { enable-prefix-caching = true; max-num-seqs = 256; }
  # becomes [ "--enable-prefix-caching" "--max-num-seqs" "256" ]
  serverArgsToFlags = args:
    lib.flatten (lib.mapAttrsToList (name: value:
      if value == true
      then ["--${name}"]
      else if value == false
      then [] # Skip false booleans
      else if value == null
      then [] # Skip nulls
      else ["--${name}" (toString value)]
    ) args);
in {
  options.services.vllm = {
    enable = lib.mkEnableOption "vLLM inference server";

    model = lib.mkOption {
      type = lib.types.str;
      default = "Qwen/Qwen3-Coder-30B-A3B-Instruct";
      description = "The Hugging Face model to serve (ignored if modelPath is set)";
    };

    modelPath = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = ''
        Path to a local model directory to serve directly.
        When set, this takes precedence over the `model` option.
        The path will be mounted read-only into the container at /model.
      '';
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
      type = lib.types.nullOr lib.types.int;
      default = null;
      description = "Maximum model context length. If null, inferred from model config.";
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
      type = lib.types.enum ["rocm" "cuda" "cpu"];
      default = "rocm";
      description = "Backend: rocm for AMD GPUs, cuda for NVIDIA GPUs, cpu for CPU-only inference";
    };

    # CPU-specific options
    cpuKvCacheSpace = lib.mkOption {
      type = lib.types.nullOr lib.types.int;
      default = null;
      description = ''
        KV cache space in GiB for CPU backend. Larger values support more
        concurrent requests and longer context. Default is 4GB.
        Set based on available system memory.
      '';
    };

    cpuOmpThreadsBind = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "0-30";
      description = ''
        CPU cores to bind OpenMP threads to for CPU backend.
        Use 'auto' for automatic binding, or specify range like '0-30'.
        Reserve 1-2 cores for the serving framework.
      '';
    };

    huggingFaceTokenFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = ''
        Path to a file containing HF_TOKEN=xxx for Hugging Face authentication.
        Required for gated models.
      '';
    };

    # Common useful options as first-class citizens
    trustRemoteCode = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Trust remote code from HuggingFace (required for some models)";
    };

    enablePrefixCaching = lib.mkOption {
      type = lib.types.nullOr lib.types.bool;
      default = null;
      description = "Enable prefix caching for better performance with repeated prefixes";
    };

    enableChunkedPrefill = lib.mkOption {
      type = lib.types.nullOr lib.types.bool;
      default = null;
      description = "Enable chunked prefill for better memory efficiency";
    };

    quantization = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Quantization method (awq, gptq, squeezellm, fp8, etc.)";
    };

    tensorParallelSize = lib.mkOption {
      type = lib.types.int;
      default = 1;
      description = "Number of GPUs for tensor parallelism";
    };

    maxNumSeqs = lib.mkOption {
      type = lib.types.nullOr lib.types.int;
      default = null;
      description = "Maximum number of sequences to process in parallel";
    };

    kvCacheDtype = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "KV cache data type (auto, fp8, fp8_e4m3, fp8_e5m2)";
    };

    attentionBackend = lib.mkOption {
      type = lib.types.nullOr (lib.types.enum ["FLASHINFER" "FLASH_ATTN" "XFORMERS" "TRITON_ATTN" "ROCM_FLASH" "TORCH_SDPA"]);
      default = null;
      description = ''
        Attention backend to use. Useful for older GPUs that don't support Flash Attention 2.
        Flash Attention 2 requires compute capability 8.0+ (Ampere or newer).
        For older GPUs (Turing 7.5, Volta 7.0), use FLASHINFER or TRITON_ATTN.
      '';
    };

    maxNumBatchedTokens = lib.mkOption {
      type = lib.types.nullOr lib.types.int;
      default = null;
      description = "Maximum number of batched tokens per iteration (for chunked prefill)";
    };

    # Generic server args for any vLLM option not covered above
    # See: https://docs.vllm.ai/en/stable/cli/serve/
    serverArgs = lib.mkOption {
      type = lib.types.attrsOf (lib.types.oneOf [lib.types.bool lib.types.int lib.types.float lib.types.str]);
      default = {};
      example = {
        "swap-space" = 4;
        "disable-log-stats" = true;
        "max-logprobs" = 20;
      };
      description = ''
        Additional vLLM server arguments as an attribute set.
        Keys are flag names (without --), values are the flag values.
        Boolean true adds the flag, false omits it.
        See https://docs.vllm.ai/en/stable/cli/serve/
      '';
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
    # Enable podman for containers
    virtualisation.podman.enable = true;
    # Note: dockerCompat conflicts with virtualisation.docker.enable
    # If you need the `docker` command alias, set virtualisation.podman.dockerCompat = true
    # in your host config (only if docker is not enabled)

    # ROCm support for AMD GPUs
    hardware.graphics.extraPackages = lib.mkIf (cfg.backend == "rocm") (with pkgs; [
      rocmPackages.clr.icd
    ]);

    # NVIDIA Container Toolkit for CUDA GPUs (not needed for CPU backend)
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
        else if cfg.backend == "cpu"
        then "public.ecr.aws/q9t5s3a7/vllm-cpu-release-repo:latest"
        else "vllm/vllm-openai:latest";
      autoStart = true;

      # Environment files for HF token
      environmentFiles = lib.optional (cfg.huggingFaceTokenFile != null) cfg.huggingFaceTokenFile;

      environment =
        {
          # Hugging Face cache location inside container
          HF_HOME = "/root/.cache/huggingface";
        }
        // lib.optionalAttrs (cfg.backend != "cpu") {
          # PyTorch memory allocation optimization (GPU only)
          PYTORCH_CUDA_ALLOC_CONF = "expandable_segments:True";
        }
        // lib.optionalAttrs (cfg.attentionBackend != null) {
          # Override attention backend (useful for older GPUs without FA2 support)
          VLLM_ATTENTION_BACKEND = cfg.attentionBackend;
        }
        // lib.optionalAttrs (cfg.backend == "rocm") {
          HIP_VISIBLE_DEVICES = "0";
        }
        // lib.optionalAttrs (cfg.backend == "cpu") {
          # CPU backend specific settings
          VLLM_CPU_KVCACHE_SPACE = toString (if cfg.cpuKvCacheSpace != null then cfg.cpuKvCacheSpace else 4);
        }
        // lib.optionalAttrs (cfg.backend == "cpu" && cfg.cpuOmpThreadsBind != null) {
          VLLM_CPU_OMP_THREADS_BIND = cfg.cpuOmpThreadsBind;
        };

      # Persist model cache and optionally mount local model
      volumes = [
        "${cfg.cacheDir}:/root/.cache/huggingface"
      ] ++ lib.optionals (cfg.modelPath != null) [
        "${cfg.modelPath}:/model:ro"
      ];

      # vLLM serve command arguments
      # Model is passed as positional argument (preferred by vLLM 0.15+)
      cmd =
        [
          (if cfg.modelPath != null then "/model" else cfg.model)
          "--host"
          "0.0.0.0"
          "--port"
          "8000"
          "--dtype"
          cfg.dtype
        ]
        # GPU-specific options (not applicable for CPU backend)
        ++ lib.optionals (cfg.backend != "cpu") [
          "--gpu-memory-utilization"
          (toString cfg.gpuMemoryUtilization)
          "--tensor-parallel-size"
          (toString cfg.tensorParallelSize)
        ]
        # Optional flags
        ++ lib.optionals (cfg.maxModelLen != null) ["--max-model-len" (toString cfg.maxModelLen)]
        ++ lib.optionals (cfg.maxNumBatchedTokens != null) ["--max-num-batched-tokens" (toString cfg.maxNumBatchedTokens)]
        ++ lib.optionals cfg.trustRemoteCode ["--trust-remote-code"]
        ++ lib.optionals (cfg.enablePrefixCaching == true) ["--enable-prefix-caching"]
        ++ lib.optionals (cfg.enablePrefixCaching == false) ["--no-enable-prefix-caching"]
        ++ lib.optionals (cfg.enableChunkedPrefill == true) ["--enable-chunked-prefill"]
        ++ lib.optionals (cfg.enableChunkedPrefill == false) ["--no-enable-chunked-prefill"]
        ++ lib.optionals (cfg.quantization != null) ["--quantization" cfg.quantization]
        ++ lib.optionals (cfg.maxNumSeqs != null) ["--max-num-seqs" (toString cfg.maxNumSeqs)]
        ++ lib.optionals (cfg.kvCacheDtype != null) ["--kv-cache-dtype" cfg.kvCacheDtype]
        # Generic serverArgs
        ++ (serverArgsToFlags cfg.serverArgs);

      # Port mapping
      ports = ["${cfg.host}:${toString cfg.port}:8000"];

      # Device access based on backend
      extraOptions =
        if cfg.backend == "rocm"
        then [
          "--device=/dev/kfd"
          "--device=/dev/dri"
          "--ipc=host"
          "--group-add=video"
          "--security-opt=seccomp=unconfined"
        ]
        else if cfg.backend == "cpu"
        then [
          # CPU backend needs these for NUMA optimizations
          "--cap-add=SYS_NICE"
          "--security-opt=seccomp=unconfined"
          "--shm-size=4g"
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
