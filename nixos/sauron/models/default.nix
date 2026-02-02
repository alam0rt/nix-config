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
}
