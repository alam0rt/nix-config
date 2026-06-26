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
  farmvillage = pkgs.callPackage ./farmvillage {};
}
