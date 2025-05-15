{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.server;
in {
  services.pvpgn = {
    enable = true;
    bnetd = {
      servername = "WankNet";
      logFile = "/var/log/bnetd.log";
    };
    localStateDir = "/srv/data/pvpgn";
    openFirewall = true;
    news = ''
      {2024-10-16}

      Welcome to the jungle.
    '';
  };
}
