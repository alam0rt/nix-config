{
  config,
  lib,
  pkgs,
  ...
}: {
  # vLLM inference server - Tesslate OmniCoder-9B (GGUF Q4_K_M)
  # https://huggingface.co/Tesslate/OmniCoder-9B-GGUF
  # https://docs.vllm.ai/en/stable/features/quantization/gguf/
  #
  # Model: OmniCoder-9B, quantized to Q4_K_M (~5.7 GB) via GGUF.
  # File pre-downloaded to /srv/share/public/models/OmniCoder-9B-GGUF/
  # with: curl -L -C - -o .../omnicoder-9b-q4_k_m.gguf \
  #   https://huggingface.co/Tesslate/OmniCoder-9B-GGUF/resolve/main/omnicoder-9b-q4_k_m.gguf
  #
  # The --tokenizer flag is required for GGUF: vLLM cannot reliably
  # convert the tokenizer from the GGUF file itself, so we point it at
  # the base (non-quantized) HuggingFace repo instead.
  #
  # If vLLM cannot infer the model architecture config from the GGUF
  # header alone, add to serverArgs:
  #   "hf-config-path" = "Tesslate/OmniCoder-9B";
  #
  # Example curl:
  #   curl http://localhost:8000/v1/chat/completions \
  #     -H "Content-Type: application/json" \
  #     -d '{"model": "omnicoder-9b-q4_k_m.gguf",
  #          "messages": [{"role": "user", "content": "Write a Rust TCP server"}]}'
  #
  # Hardware notes for NVIDIA T1000 8GB (Turing, compute capability 7.5):
  #   - Does not support bfloat16; use float16
  #   - Flash Attention 2 requires compute 8.0+; use FLASHINFER instead
  #   - Q4_K_M ~5.7 GB fits in 8 GB VRAM with gpuMemoryUtilization = 0.85
  #
  services.vllm = {
    enable = true;
    # Serve the local GGUF file directly - mounted as /model:ro in the container
    modelPath = "/srv/share/public/models/OmniCoder-9B-GGUF/omnicoder-9b-q4_k_m.gguf";
    backend = "cuda";
    port = 8000; # matches OPENAI_API_BASE_URL in openwebui/default.nix

    # GGUF quantization - pin exact quant file to avoid ambiguity
    quantization = "gguf";

    # Force float16 for Turing GPUs (T1000 doesn't support bfloat16)
    dtype = "float16";

    # 5.7 GB model needs more headroom than LFM2.5 did
    gpuMemoryUtilization = 0.85;
    cacheDir = "/srv/data/vllm"; # persist on ZFS

    # Use FLASHINFER backend via --attention-backend CLI flag
    # FA2 requires compute 8.0+ (Ampere), FLASHINFER works on Turing 7.5
    attentionBackend = "FLASHINFER";

    # Prefix caching is incompatible with chunked prefill for GGUF
    enablePrefixCaching = false;
    enableChunkedPrefill = true; # better memory efficiency

    # Context length for a coding assistant; reduce if OOM at startup
    maxModelLen = 8192;
    maxNumBatchedTokens = 512;
    maxNumSeqs = 2; # single-user server

    # See: https://docs.vllm.ai/en/stable/cli/serve/
    serverArgs = {
      # Required for GGUF: use the base (non-quantized) repo for tokenizer
      "tokenizer" = "Tesslate/OmniCoder-9B";
      # qwen35 architecture not supported in transformers' GGUF parser yet;
      # fetch model config from HF instead of reading from the GGUF header
      "hf-config-path" = "Tesslate/OmniCoder-9B";
      "disable-log-stats" = true; # reduce log noise
      "enforce-eager" = true; # disable CUDA graphs to save memory (Turing)
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
