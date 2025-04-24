{ pkgs, ... }:

{
  imports =
    [
      ./users.nix
    ];

  # enable zsh integration with nix
  programs.zsh = {
    enable = true;
  };

  services.smartd = {
    enable = true;
  };

  nix = {
    # Optimisation of the Nix Store
    optimise.automatic = true;
    optimise.dates = [ "weekly" ];

    # Garbage colection (Removes Old Snapshots)
    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 7d";
    };

    channel.enable = false;

  };
}
