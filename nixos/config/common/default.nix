{ pkgs, ... }:

{
  imports = [ ./users.nix ];

  # enable zsh integration with nix
  programs.zsh = {
    enable = true;
  };

  services.smartd = {
    enable = true;
  };
}
