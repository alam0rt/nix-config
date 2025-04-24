{ pkgs, ... }:
# Stole from https://github.com/damiankorcz/nix-config/commit/7c1b82bf27b38ca0e1afc5ff8b699ff624b63feb
# Provides AMD-GPU overclocking and mesa overrides.

{
  environment.systemPackages = with pkgs; [
    lact
  ];

  # Enable the LACT Daemon
  systemd.services.lact = {
    description = "LACT Daemon";
    after = [ "multi-user.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      ExecStart = "${pkgs.lact}/bin/lact daemon";
    };
    enable = true;
  };

  chaotic = {
    # For mesa 25
    mesa-git = {
      enable = true;
    };
    nyx.cache.enable = true;
  };