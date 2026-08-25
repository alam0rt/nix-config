{
  lib,
  fetchFromGitHub,
  rustPlatform,
  cmake,
}:
rustPlatform.buildRustPackage (finalAttrs: {
  pname = "switchyard-server";
  # Pre-alpha with no release carrying `forward_auth` yet (added 2026-08-14,
  # after v0.2.0). Pinned main snapshot; forward_auth lets the proxy run
  # without upstream credentials in its own environment.
  version = "0.2.0-unstable-2026-08-24";

  src = fetchFromGitHub {
    owner = "NVIDIA-NeMo";
    repo = "Switchyard";
    rev = "819e462cd63740ab2ce848c811d6618fc6bd1474";
    hash = "sha256-dEL0zUI/PdYzJjpPd6T6zAEzdCdjrIOmX7WG4uEZtKE=";
  };

  cargoLock.lockFile = "${finalAttrs.src}/Cargo.lock";

  # The workspace also ships library crates and Python bindings
  # (crates/switchyard-py); only build the standalone proxy binary.
  cargoBuildFlags = ["--package" "switchyard-server"];

  # aws-lc-sys (rustls TLS backend) compiles C code with cmake.
  nativeBuildInputs = [cmake];

  # Tests spin up mock upstreams on local sockets; upstream CI covers them.
  doCheck = false;

  meta = {
    description = "LLM traffic proxy: routes across providers and translates between OpenAI and Anthropic APIs";
    homepage = "https://github.com/NVIDIA-NeMo/Switchyard";
    changelog = "https://github.com/NVIDIA-NeMo/Switchyard/blob/main/CHANGELOG.md";
    license = lib.licenses.asl20;
    mainProgram = "switchyard-server";
    platforms = lib.platforms.linux ++ lib.platforms.darwin;
  };
})
