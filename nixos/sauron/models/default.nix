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
  services.vllm = {
    enable = true;
    model = "LiquidAI/LFM2.5-1.2B-Instruct";
    backend = "cuda";
    port = 8100;
    dtype = "auto"; # as recommended by Liquid AI docs
    maxModelLen = 4096;
    gpuMemoryUtilization = 0.90;
    cacheDir = "/srv/data/vllm"; # persist on ZFS
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
