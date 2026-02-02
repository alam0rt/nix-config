{
  config,
  lib,
  pkgs,
  ...
}: {
  # vLLM inference server - Liquid AI LFM2.5 model
  # https://docs.liquid.ai/docs/inference/vllm
  #
  # Recommended client-side sampling params for LFM2.5:
  #   temperature: 0.3
  #   min_p: 0.15
  #   repetition_penalty: 1.05
  #   max_tokens: 512
  #
  # Example curl:
  #   curl http://localhost:8100/v1/chat/completions \
  #     -H "Content-Type: application/json" \
  #     -d '{"model": "LiquidAI/LFM2.5-1.2B-Instruct",
  #          "messages": [{"role": "user", "content": "Hello!"}],
  #          "temperature": 0.3, "min_p": 0.15, "repetition_penalty": 1.05}'
  #
  # Hardware notes for NVIDIA T1000 8GB (Turing, compute capability 7.5):
  #   - Does not support bfloat16, vLLM auto-casts to float16
  #   - Flash Attention 2 requires compute 8.0+, use FLASHINFER instead
  #   - Limited VRAM, use conservative memory settings
  #
  services.vllm = {
    enable = true;
    modelPath = "/srv/share/public/models/LFM2.5-1.2B-Instruct";
    backend = "cuda";
    port = 8100;

    # Force float16 for Turing GPUs (T1000 doesn't support bfloat16)
    dtype = "float16";

    # Memory settings for 8GB VRAM - minimal for simple chatbot
    gpuMemoryUtilization = 0.70;
    cacheDir = "/srv/data/vllm"; # persist on ZFS

    # Use FLASHINFER backend - compatible with compute capability 7.5
    # FA2 requires compute 8.0+ (Ampere), FLASHINFER works on Turing
    attentionBackend = "FLASHINFER";

    # Performance optimizations
    enablePrefixCaching = false; # disable to save memory
    enableChunkedPrefill = true; # better memory efficiency

    # Minimal context for simple chatbot use case
    # Short conversations don't need much context
    maxModelLen = 2048;
    maxNumBatchedTokens = 512;
    maxNumSeqs = 2; # single user chatbot

    # Any other vLLM flags can be passed via serverArgs
    # See: https://docs.vllm.ai/en/stable/cli/serve/
    serverArgs = {
      "disable-log-stats" = true; # reduce log noise
      "enforce-eager" = true; # disable CUDA graphs to save memory
    };
  };

  # Wyoming Faster Whisper - Speech-to-Text server
  # Uses Wyoming protocol for Home Assistant integration
  # Available at tcp://localhost:10300
  #
  # Models: tiny-int8, base-int8, small-int8, medium-int8 (quantized)
  #         tiny, base, small, medium, large, large-v2, large-v3, turbo
  #         distil-small.en, distil-medium.en, distil-large-v2, distil-large-v3
  #
  services.wyoming.faster-whisper.servers.whisper = {
    enable = true;
    uri = "tcp://0.0.0.0:10300";
    model = "small-int8"; # good balance of speed/accuracy
    language = "en";
    device = "cpu"; # CUDA has nixpkgs compilation issues
  };
}
