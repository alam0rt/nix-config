{
  inputs,
  outputs,
  lib,
  config,
  pkgs,
  ...
}:
{
  # You can import other home-manager modules here
  imports = [ ./common.nix ];

  nixpkgs = {
    # You can add overlays here
    overlays = [
      # Add overlays your own flake exports (from overlays and pkgs dir):
      outputs.overlays.additions
      outputs.overlays.modifications
      outputs.overlays.unstable-packages

      inputs.nixpkgs-firefox-darwin.overlay

      # You can also add overlays exported from other flakes:
      # neovim-nightly-overlay.overlays.default

      # Or define it inline, for example:
      # (final: prev: {
      #   hi = final.hello.overrideAttrs (oldAttrs: {
      #     patches = [ ./change-hello-to-hi.patch ];
      #   });
      # })
    ];
    # Configure your nixpkgs instance
    config = {
      # Disable if you don't want unfree packages
      allowUnfree = true;
    };
  };

  home = {
    username = lib.mkForce "sam.lockart";
    homeDirectory = lib.mkForce "/Users/sam.lockart";
    sessionPath = [ "$HOME/.local/bin" ];
  };

  home.packages = with pkgs; [
    iterm2
    obsidian
    unstable.jetbrains.goland
    unstable.jetbrains.ruby-mine
    saml2aws
    awscli2
    vendir
    ssm-session-manager-plugin
    amazon-ecr-credential-helper
  ];

  # Enable home-manager and git
  programs.home-manager.enable = true;
  programs.git.enable = true;

  # Nicely reload system units when changing configs
  systemd.user.startServices = "sd-switch";

  # https://nixos.wiki/wiki/FAQ/When_do_I_update_stateVersion
  home.stateVersion = "24.11";
}
