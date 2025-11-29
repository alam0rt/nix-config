# Custom packages, that can be defined similarly to ones from nixpkgs
# You can build them using 'nix build .#example'
pkgs: {
  # example = pkgs.callPackage ./example { };
  sickle = pkgs.callPackage ./sickle {};
  rolecule = pkgs.callPackage ./rolecule {};
  scaffold = pkgs.callPackage ./scaffold {};
  opuslib-next = pkgs.callPackage ./opuslib-next {};
  protobuf3 = pkgs.callPackage ./protobuf3 {};
}
