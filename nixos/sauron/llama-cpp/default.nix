{pkgs, ...}: {
  # llama-server serving OmniCoder-9B Q4_K_M via llama.cpp
  # https://huggingface.co/Tesslate/OmniCoder-9B-GGUF
  #
  # vLLM 0.17.1 doesn't support the qwen35 (Gated Delta Networks) architecture
  # in GGUF format; llama.cpp handles it natively.
  #
  # Model file pre-downloaded with:
  #   curl -L -C - -o /srv/share/public/models/OmniCoder-9B-GGUF/omnicoder-9b-q4_k_m.gguf \
  #     https://huggingface.co/Tesslate/OmniCoder-9B-GGUF/resolve/main/omnicoder-9b-q4_k_m.gguf
  #
  # Hardware: NVIDIA T1000 8GB (Turing, compute capability 7.5)
  #   - Flash Attention (-fa 1) works fine with llama.cpp on Turing
  #   - Full GPU offload (-ngl 999)
  #   - 64k context with Q4_K_M (~5.7 GB) + q4_0 V cache fits in 8 GB VRAM
  #     reduce -c to 32768 if VRAM is tight at startup
  #
  # Example curl:
  #   curl http://localhost:8000/v1/chat/completions \
  #     -H "Content-Type: application/json" \
  #     -d '{"model": "omnicoder-9b-q4_k_m",
  #          "messages": [{"role": "user", "content": "Write a Rust TCP server"}]}'
  #
  services.llama-cpp = {
    enable = true;
    package = pkgs.unstable.llama-cpp; # b8255 — qwen35 arch support; cudaSupport=true via overlay
    port = 8000; # matches OPENAI_API_BASE_URL in openwebui/default.nix
    host = "127.0.0.1";
    openFirewall = false;
    model = "/srv/share/public/models/OmniCoder-9B-GGUF/omnicoder-9b-q4_k_m.gguf";
    # Server-level flags (not model-specific)
    extraFlags = [
      "-ngl" "999"            # full GPU offload — REQUIRED, default is 0 (CPU only)
      "--fit-target" "512"    # VRAM margin for --fit auto-adjust (default 1024); T1000 has 921 MiB free at idle
      "-np" "1"               # 1 parallel slot — auto defaults to 4, making KV cache 4x larger and OOMing VRAM
      "-dio"                  # Direct I/O — fixes hangs/slowdowns in llama-server vs llama-bench (issue #19745)
      "-t" "8"                # CPU threads (for non-GPU ops)
      "-fa" "1"               # flash attention (works on Turing with llama.cpp)
      "-b" "2048"             # batch size
      "-ub" "512"             # micro-batch size
      "-c" "49152"            # context size (48k; fits T1000 8GB; >41k needed for openclaw compaction)
      "--cache-type-k" "f16"  # KV cache precision
      "--cache-type-v" "q4_0" # compressed V cache to save VRAM
      "--ctx-checkpoints" "1" # reuse KV cache across slots for shared prompt prefixes
      "--temp" "0.4"
      "--top-p" "0.95"
      "--top-k" "20"
      "--jinja"
    ];
  };

  # PrivateUsers=true (set by the module) breaks CUDA device access under systemd.
  # The DynamicUser can't see /dev/nvidia* in the private user namespace.
  systemd.services.llama-cpp.serviceConfig.PrivateUsers = pkgs.lib.mkForce false;
}
