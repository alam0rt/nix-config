{
  inputs,
  outputs,
  lib,
  config,
  pkgs,
  ...
}: {
  imports = [./common.nix];

  nixpkgs = {
    overlays = [
      outputs.overlays.additions
      outputs.overlays.modifications
      outputs.overlays.unstable-packages

      inputs.nixpkgs-firefox-darwin.overlay
    ];
    config = {
      allowUnfree = true;
    };
  };

  home = {
    username = lib.mkForce "sam.lockart";
    homeDirectory = lib.mkForce "/Users/sam.lockart";
    sessionPath = ["$HOME/.local/bin"];
  };

  # Nicely reload system units when changing configs
  systemd.user.startServices = "sd-switch";

  # https://nixos.wiki/wiki/FAQ/When_do_I_update_stateVersion
  home.stateVersion = "24.11";
}
