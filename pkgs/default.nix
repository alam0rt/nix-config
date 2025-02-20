# Custom packages, that can be defined similarly to ones from nixpkgs
# You can build them using 'nix build .#example'
pkgs: {
  # example = pkgs.callPackage ./example { };

  my-custom-vscode-extension = pkgs.vscode-utils.buildVscodeExtension {
    name = "cline";
    vscodeExtPublisher = "yt3trees";
    vscodeExtUniqueId = "yt3trees.cline";
    vscodeExtName = "cline";
    version = "azureopenai-o3mini";
    src = pkgs.fetchgit {
      url = "https://github.com/yt3trees/cline.git";
      rev = "refs/heads/azureopenai-o3mini";
      sha256 = "sha256-V9z2PfVnH4Q60K2LWFnqXIHdbYDmSNJUFmb0SrqbBms=";
    };
  };
}
