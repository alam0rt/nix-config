{pkgs, ...}: {
  programs.vscode = {
    enable = true;
    package = pkgs.unstable.vscode;
    profiles.default = {
      enableExtensionUpdateCheck = false;
      enableUpdateCheck = false;
      userSettings = {
        "files.insertFinalNewline" = true;
      };
      extensions = with pkgs.vscode-extensions; [
        # core
        dracula-theme.theme-dracula
        vscodevim.vim

        # golang
        golang.go

        # rust
        rust-lang.rust-analyzer

        # ruby
        shopify.ruby-lsp

        # nix
        jnoortheen.nix-ide

        # terraform
        hashicorp.hcl

        # system
        timonwong.shellcheck
        coolbear.systemd-unit-file

        # openscad
        antyos.openscad

        # extras
        signageos.signageos-vscode-sops
        ms-vscode-remote.remote-ssh
        github.copilot
        github.copilot-chat
        ms-vscode.makefile-tools
      ];
    };
  };
}
