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
  # Hardware: NVIDIA A1000 8GB (Ampere cc 8.6) + T1000 8GB (Turing cc 7.5)
  #   - llama.cpp enumerates CUDA0=A1000, CUDA1=T1000 (CUDA's default
  #     FASTEST_FIRST order — opposite of nvidia-smi's PCIe-bus order).
  #   - --split-mode layer distributes the 48 transformer layers across both
  #     GPUs (default ~50/50 by free VRAM). At 49K ctx each slot uses ~3-4 GiB
  #     KV, fitting alongside the ~7 GiB model thanks to mixed-precision KV
  #     (q4_1 K / q8_0 V) and ISWA bounding 38/48 layers to a 1024-token window.
  #   - --main-gpu 0 makes A1000 host embeddings/output/compute scratch.
  #   - -ub 256 halves the default 512 microbatch so compute pp buffer fits.
  #   - -b 1024 increases prefill batch to amortize PCIe sync overhead.
  #   - -fa 1 enables FlashAttention; mixed-arch is OK (per-device selection).
  #
  # Throughput cost of dual-GPU: ~30-50% slower decode vs single-GPU due to
  # PCIe sync per token + slower T1000. Cold prompt-processing at 49K ≈ 6-7
  # min worst-case; --cache-reuse 256 makes follow-up turns near-instant on shared prefix.
  #
  # Sampler + template per Unsloth recommendations
  # (https://unsloth.ai/docs/models/gemma-4):
  #   - Google defaults: temp 1.0, top-p 0.95, top-k 64
  #   - Thinking mode OFF (--reasoning off); reasoning is externalized into
  #     the agentic tool-call loop (each Ghidra MCP round-trip = one step).
  #     With thinking on, 12B spirals indefinitely on RE tasks (13 min for a
  #     trivial struct). To re-enable: --reasoning on (strip thought blocks
  #     from multi-turn history per Unsloth docs).
  #   - Model's declared max ctx is 262144; we cap at 49K to bound KV cache (~3-4 GiB/slot) and prefill time
  #
  # KV cache strategy:
  #   - Gemma 4 uses ISWA (5:1 local:global, sliding window 1024) — most layers'
  #     KV is bounded by the window, not -c. At 8K ctx, fp16 KV is ~830 MiB.
  #   - Mixed-precision KV: q4_1 K-cache (keys tolerate quantization well on
  #     hybrid SWA models per #21385) + q8_0 V-cache (values are sensitive;
  #     q4_0 V has a known Gemma quality cliff). Saves ~400-500 MiB vs q8_0/q8_0.
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
      "layer"
      "--main-gpu"
      "0"
      "-fa"
      "1"
      "-ctk"
      "q4_1"
      "-ctv"
      "q8_0"
      "--cache-reuse"
      "256"
      "-c"
      "49152"
      "-b"
      "1024"
      "-ub"
      "256"
      "-np"
      "1"
      "--jinja"
      "--reasoning"
      "off"
      # Server-side agentic tools (read_file, file_glob_search, grep_search).
      # Safe here: DynamicUser + ProtectHome/ProtectSystem confine reads to
      # /nix/store + the service's own cache; LAN-only exposure.
      "--tools"
      "all"
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
