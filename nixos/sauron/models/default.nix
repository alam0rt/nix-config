{
  config,
  lib,
  pkgs,
  ...
}: {
  # vLLM was removed in favour of llama-cpp (services.llama-cpp in ./llama-cpp)
  # vLLM 0.17.1 does not support the qwen35 (Gated Delta Networks) architecture
  # used by OmniCoder-9B when loading from GGUF.

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
