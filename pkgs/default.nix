# Custom packages, that can be defined similarly to ones from nixpkgs
# You can build them using 'nix build .#example'
pkgs: {
  # example = pkgs.callPackage ./example { };
  sickle = pkgs.callPackage ./sickle {};
  rolecule = pkgs.callPackage ./rolecule {};
  scaffold = pkgs.callPackage ./scaffold {};
  opuslib-next = pkgs.callPackage ./opuslib-next {};
  protobuf3 = pkgs.callPackage ./protobuf3 {};
  ghidra-psx-ldr = pkgs.callPackage ./ghidra-psx-ldr {};
  ghidra-mcp = pkgs.callPackage ./ghidra-mcp {};
  freecad-mcp = pkgs.callPackage ./freecad-mcp {};
  pi = pkgs.callPackage ./pi {};
  jellyfin-plugin-oidc = pkgs.callPackage ./jellyfin-plugin-oidc {};
  # Uses nixpkgs-unstable's rustPlatform: Switchyard's Cargo.toml requires
  # rustc/cargo >= 1.96.1 while the pinned stable nixpkgs ships 1.95.0.
  switchyard = pkgs.unstable.callPackage ./switchyard {};
  bermuda = pkgs.callPackage ./bermuda {};
}
