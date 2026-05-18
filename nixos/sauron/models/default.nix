{
  config,
  lib,
  pkgs,
  ...
}: {
  # vLLM was removed in favour of llama-cpp (services.llama-cpp in ./llama-cpp)
  # vLLM 0.17.1 does not support the qwen35 (Gated Delta Networks) architecture
  # used by OmniCoder-9B when loading from GGUF.

  # EmbeddingGemma 300M — text embedding model from Google (Gemma 3 backbone)
  # Architecture: Gemma3TextModel (natively supported by vLLM as pooling/embedding model)
  # Docs: https://huggingface.co/google/embeddinggemma-300m
  # vLLM architecture: Gemma3TextModelC  (see vLLM supported-models#embedding)
  #
  # Notes:
  #  - float16 is NOT supported by EmbeddingGemma activations; use float32 or bfloat16
  #  - T1000 (Turing cc 7.5) has no native bfloat16, so float32 is used (~1.2 GB VRAM)
  #  - Served on port 8001 (8000 is reserved for llama-cpp / OmniCoder)
  #  - OpenWebUI and other clients can use this for RAG / semantic search
  #
  services.vllm = {
    enable = true;
    backend = "cuda";
    modelPath = "/srv/share/public/models/embeddinggemma-300m";
    runner = "pooling"; # embedding / pooling model
    port = 8001;
    host = "127.0.0.1";
    openFirewall = false;
    dtype = "float32"; # bfloat16 requires Ampere+; float16 unsupported by EmbeddingGemma
    gpuMemoryUtilization = 0.25; # ~2 GB; leaves VRAM headroom for OmniCoder on llama-cpp
    maxModelLen = 2048; # EmbeddingGemma max context
    enablePrefixCaching = false; # prefix caching not meaningful for embedding models
    cacheDir = "/var/cache/vllm-embedding";
    serverArgs = {
      # Give the model a stable name instead of the container-internal path "/model"
      "served-model-name" = "embeddinggemma-300m";
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
