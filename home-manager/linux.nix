# This is your home-manager configuration file
# Use this to configure your home environment (it replaces ~/.config/nixpkgs/home.nix)
{
  inputs,
  outputs,
  lib,
  config,
  pkgs,
  ...
}: {
  # You can import other home-manager modules here
  imports = [./common.nix];

  nixpkgs = {
    # You can add overlays here
    overlays = [
      # Add overlays your own flake exports (from overlays and pkgs dir):
      outputs.overlays.additions
      outputs.overlays.modifications
      outputs.overlays.unstable-packages
    ];
    # Configure your nixpkgs instance
    config = {
      # Disable if you don't want unfree packages
      allowUnfree = true;
    };
  };

  xdg = {
    configFile = {
      "containers/policy.json" = {
        enable = true;
        text = builtins.toJSON {
          # https://github.com/containers/image/blob/main/docs/containers-policy.json.5.md
          default = [{type = "insecureAcceptAnything";}];
        };
      };
    };
  };

  home.packages = with pkgs; [
    # CAD / 3d
    super-slicer-latest # doesn't build on darwin
    inputs.pcsx-redux.packages.${system}.pcsx-redux
    # nix-shell -p ghidra -I nixpkgs=https://github.com/NixOS/nixpkgs/archive/21808d22b1cda1898b71cf1a1beb524a97add2c4.tar.gz
  ];

  # Nicely reload system units when changing configs
  systemd.user.startServices = "sd-switch";

  # https://nixos.wiki/wiki/FAQ/When_do_I_update_stateVersion
  home.stateVersion = "24.11";
}
