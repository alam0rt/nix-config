{
  pkgs,
  lib,
  ...
}: {
  # llama-server serving unsloth/gemma-4-12b-it-GGUF (UD-Q4_K_XL ~7.37 GB)
  # https://huggingface.co/unsloth/gemma-4-12b-it-GGUF
  #
  # Model file pre-downloaded with:
  #   sudo curl -L -C - -o /var/cache/llama-cpp/gemma-4-12b-it-UD-Q4_K_XL.gguf \
  #     https://huggingface.co/unsloth/gemma-4-12b-it-GGUF/resolve/main/gemma-4-12b-it-UD-Q4_K_XL.gguf
  #
  # Hardware: NVIDIA A1000 8GB (Ampere cc 8.6) — GPU index 1
  #   - Q4_K_XL (~7.37 GB) + ~512 MB KV cache @ 8K ctx fits cleanly
  #   - --split-mode none + --main-gpu 1 pins to A1000, leaves T1000 (idx 0) free
  #   - -fa 1 enables FlashAttention (Ampere supports FA2 natively)
  #
  # Sampler + template per Unsloth recommendations
  # (https://unsloth.ai/docs/models/gemma-4):
  #   - Google defaults: temp 1.0, top-p 0.95, top-k 64
  #   - Thinking mode ON (enable_thinking=true); client must NOT feed prior
  #     thought blocks back into the next turn — strip them before resending
  #   - To disable thinking instead: --chat-template-kwargs '{"enable_thinking":false}'
  #   - Model's declared max ctx is 262144; we cap with -c due to 8GB VRAM
  services.llama-cpp = {
    enable = true;
    package = pkgs.unstable.llama-cpp; # cudaSupport=true via overlay
    port = 8000; # matches OPENAI_API_BASE_URL in openwebui/default.nix
    host = "127.0.0.1";
    openFirewall = false;
    model = "/var/cache/llama-cpp/gemma-4-12b-it-UD-Q4_K_XL.gguf";
    extraFlags = [
      "-ngl"
      "999"
      "--split-mode"
      "none"
      "--main-gpu"
      "1"
      "-fa"
      "1"
      "-c"
      "8192"
      "-np"
      "1"
      "--jinja"
      "--alias"
      "unsloth/gemma-4-12b-it-GGUF"
      "--temp"
      "1.0"
      "--top-p"
      "0.95"
      "--top-k"
      "64"
      "--chat-template-kwargs"
      "{\"enable_thinking\":true}"
    ];
  };

  systemd.tmpfiles.rules = [
    "d /var/cache/llama-cpp 0755 root root -"
  ];

  # PrivateUsers=true (set by the module) breaks CUDA device access under systemd.
  # The DynamicUser can't see /dev/nvidia* in the private user namespace.
  systemd.services.llama-cpp.serviceConfig.PrivateUsers = lib.mkForce false;
}
