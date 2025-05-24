{
  inputs,
  outputs,
  ...
}: {
  imports = [
    # Import home-manager's NixOS module
    inputs.home-manager.nixosModules.home-manager
  ];

  # required by sway
  # https://nixos.wiki/wiki/Sway
  security.polkit.enable = true;
  programs.light.enable = true;

  home-manager = {
    extraSpecialArgs = {
      inherit inputs outputs;
    };
    users = {
      # Import your home-manager configuration
      sam = import ../../home-manager/linux.nix;
    };
  };
}
