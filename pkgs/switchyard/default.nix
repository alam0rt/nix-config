{
  lib,
  fetchFromGitHub,
  rustPlatform,
  cmake,
}:
rustPlatform.buildRustPackage (finalAttrs: {
  pname = "switchyard-server";
  version = "0.2.0";

  src = fetchFromGitHub {
    owner = "NVIDIA-NeMo";
    repo = "Switchyard";
    rev = "v${finalAttrs.version}";
    hash = "sha256-f3WYJc+WFxKw5bh9lSKJZhO8n7f23/EsEQMs0YrirCA=";
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
    changelog = "https://github.com/NVIDIA-NeMo/Switchyard/blob/v${finalAttrs.version}/CHANGELOG.md";
    license = lib.licenses.asl20;
    mainProgram = "switchyard-server";
    platforms = lib.platforms.linux ++ lib.platforms.darwin;
  };
})
