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
  # Hardware: NVIDIA A1000 8GB (Ampere cc 8.6)
  #   - llama.cpp enumerates CUDA0=A1000, CUDA1=T1000 (CUDA's default
  #     FASTEST_FIRST order — opposite of nvidia-smi's PCIe-bus order).
  #     --main-gpu 0 therefore pins to A1000; leaves T1000 free.
  #   - Q4_K_XL (~7.0 GiB resident) + q8_0 KV @ 8K (~415 MiB) +
  #     compute pp buffer (~260 MiB at -ub 256) ≈ 7.7 GiB → fits 7.57 GiB free.
  #   - -ub 256 halves the default 512 microbatch so the compute buffer fits
  #     in the remaining VRAM. Bumping it back to 512 OOMs on cudaMalloc.
  #   - -fa 1 enables FlashAttention (Ampere supports FA2 natively)
  #
  # Sampler + template per Unsloth recommendations
  # (https://unsloth.ai/docs/models/gemma-4):
  #   - Google defaults: temp 1.0, top-p 0.95, top-k 64
  #   - Thinking mode ON (--reasoning on); client must NOT feed prior
  #     thought blocks back into the next turn — strip them before resending
  #   - To disable thinking instead: --reasoning off
  #   - Model's declared max ctx is 262144; we cap with -c due to 8GB VRAM
  #
  # KV cache strategy:
  #   - Gemma 4 uses ISWA (5:1 local:global, sliding window 1024) — most layers'
  #     KV is bounded by the window, not -c. At 8K ctx, fp16 KV is ~830 MiB.
  #   - q8_0 KV halves that with negligible quality loss on Gemma; q4_0 V cache
  #     has a known Gemma quality cliff (llama.cpp #21385) — avoid.
  #   - --cache-reuse 256 reuses prefix KV across multi-turn requests sharing
  #     the same system prompt, cutting TTFT significantly.
  #   - Do NOT add --swa-full: it disables the ISWA savings and breaks reuse.
  services.llama-cpp = {
    enable = true;
    package = pkgs.unstable.llama-cpp; # cudaSupport=true via overlay
    port = 8000; # matches OPENAI_API_BASE_URL in openwebui/default.nix
    host = "0.0.0.0"; # LAN-accessible; sauron is NAT'd, no public exposure
    openFirewall = true;
    model = "/var/cache/llama-cpp/gemma-4-12b-it-UD-Q4_K_XL.gguf";
    extraFlags = [
      "-ngl"
      "999"
      "--split-mode"
      "none"
      "--main-gpu"
      "0"
      "-fa"
      "1"
      "-ctk"
      "q8_0"
      "-ctv"
      "q8_0"
      "--cache-reuse"
      "256"
      "-c"
      "8192"
      "-ub"
      "256"
      "-np"
      "1"
      "--jinja"
      "--reasoning"
      "on"
      "--alias"
      "unsloth/gemma-4-12b-it-GGUF"
      "--temp"
      "1.0"
      "--top-p"
      "0.95"
      "--top-k"
      "64"
    ];
  };

  systemd.tmpfiles.rules = [
    "d /var/cache/llama-cpp 0755 root root -"
  ];

  # PrivateUsers=true (set by the module) breaks CUDA device access under systemd.
  # The DynamicUser can't see /dev/nvidia* in the private user namespace.
  systemd.services.llama-cpp.serviceConfig.PrivateUsers = lib.mkForce false;
}
