# Custom packages, that can be defined similarly to ones from nixpkgs
# You can build them using 'nix build .#example'
pkgs: {
  # example = pkgs.callPackage ./example { };

  my-custom-vscode-extension = pkgs.vscode-utils.buildVscodeExtension {
    pname = "my-custom-plugin";
    version = "0.1.0";
    src = pkgs.fetchurl {
      url = "https://example.com/my-plugin.vsix";
      sha256 = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
    };
  };
}
