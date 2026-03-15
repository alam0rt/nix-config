{pkgs, ...}: {
  # llama-server serving Qwen3.5-4B Q4_K_M via llama.cpp
  # https://huggingface.co/unsloth/Qwen3.5-4B-GGUF
  #
  # Architecture: qwen35 (Gated Delta Networks + sparse MoE hybrid)
  # vLLM doesn't support this arch in GGUF; llama.cpp handles it natively.
  #
  # Model file pre-downloaded with:
  #   curl -L -C - -o /srv/share/public/models/Qwen3.5-4B-GGUF/qwen3.5-4b-q4_k_m.gguf \
  #     https://huggingface.co/unsloth/Qwen3.5-4B-GGUF/resolve/main/Qwen3.5-4B-Q4_K_M.gguf
  #
  # Hardware: NVIDIA T1000 8GB (Turing, compute capability 7.5)
  #   - 4B Q4_K_M (~2.74 GB) leaves ~4.5 GB free for KV cache
  #   - Full GPU offload (-ngl 999), flash attention (-fa 1)
  #   - 128k context comfortably fits with this model size
  #
  # Example curl:
  #   curl http://localhost:8000/v1/chat/completions \
  #     -H "Content-Type: application/json" \
  #     -d '{"model": "qwen3.5-4b-q4_k_m",
  #          "messages": [{"role": "user", "content": "Write a Rust TCP server"}]}'
  #
  services.llama-cpp = {
    enable = true;
    package = pkgs.unstable.llama-cpp; # b8255 — qwen35 arch support; cudaSupport=true via overlay
    port = 8000; # matches OPENAI_API_BASE_URL in openwebui/default.nix
    host = "127.0.0.1";
    openFirewall = false;
    model = "/srv/share/public/models/Qwen3.5-4B-GGUF/qwen3.5-4b-q4_k_m.gguf";
    # Server-level flags (not model-specific)
    extraFlags = [
      "-ngl" "999"            # full GPU offload — REQUIRED, default is 0 (CPU only)
      "--fit-target" "512"    # VRAM margin for --fit auto-adjust (default 1024)
      "-np" "1"               # 1 parallel slot — auto=4 makes KV cache 4x larger, OOMing VRAM
      "-no-kvu"               # disable unified KV buffer — issues with qwen35 SSM state management
      "-dio"                  # Direct I/O — fixes hangs/slowdowns in llama-server (issue #19745)
      "-t" "8"                # CPU threads (for non-GPU ops)
      "-fa" "1"               # flash attention (works on Turing with llama.cpp)
      "-b" "2048"             # batch size
      "-ub" "512"             # micro-batch size
      "-c" "131072"           # 128k context — fits easily with 4B model (~2.74 GB weights)
      "--cache-type-k" "f16"  # KV cache precision
      "--cache-type-v" "q4_0" # compressed V cache to save VRAM
      "--ctx-checkpoints" "0" # disabled — CPU overhead on restore with qwen35 SSM arch
      "--temp" "0.6"          # recommended for thinking mode / coding tasks
      "--top-p" "0.95"
      "--top-k" "20"
      "--jinja"
    ];
  };

  # PrivateUsers=true (set by the module) breaks CUDA device access under systemd.
  # The DynamicUser can't see /dev/nvidia* in the private user namespace.
  systemd.services.llama-cpp.serviceConfig.PrivateUsers = pkgs.lib.mkForce false;
}
