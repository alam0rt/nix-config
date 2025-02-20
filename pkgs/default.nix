# Custom packages, that can be defined similarly to ones from nixpkgs
# You can build them using 'nix build .#example'
pkgs: {
  # example = pkgs.callPackage ./example { };

  my-custom-vscode-extension = pkgs.vscode-utils.buildVscodeExtension {
    name = "cline";
    vscodeExtPublisher = "yt3trees";
    vscodeExtUniqueId = "yt3trees.cline";
    vscodeExtName = "cline";
    version = "pr-1705";
    src = pkgs.fetchgit {
      url = "https://github.com/yt3trees/cline.git";
      rev = "pr-1705";
      sha256 = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
    };
  };
}
