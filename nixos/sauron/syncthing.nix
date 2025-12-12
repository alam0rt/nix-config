{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.server;
in {
  services.syncthing = {
    enable = true;
    user = "syncthing";
    dataDir = "/srv/vault"; # Default folder for new synced folders
    configDir = "/srv/data/syncthing"; # Folder for Syncthing's settings and keys
    overrideDevices = true; # overrides any devices added or deleted through the WebUI
    openDefaultPorts = true;
    overrideFolders = true; # overrides any folders added or deleted through the WebUI
    guiAddress = "http://0.0.0.0:8384";
    settings = {
      # TODO: use declarative node configuration
      # https://wiki.nixos.org/wiki/Syncthing
      devices = {
        "laptop" = {
          id = "5ATZ7LD-C3AYIMS-EXQZILG-2A743HY-4Y7ULQY-RODJR7F-GO43W6X-CLXDAAA";
        };
        "desktop" = {
          id = "F7G62MY-FWFWFNY-PYVBZQE-S4EXYDX-IIPF4AQ-YAKJVP3-4TZXCKT-NAUTJQU";
        };
      };
      folders = {
        "vault" = {
          # Name of folder in Syncthing, also the folder ID
          path = "/srv/vault"; # Which folder to add to Syncthing
          devices = [
            "laptop"
            "desktop"
          ]; # Which devices to share the folder with
        };
      };
    };
  };
  users.users = {
    syncthing = {
      isSystemUser = true;
      group = "syncthing";
    };
  };

  services.nginx.virtualHosts."sync.middleearth.samlockart.com" = {
    forceSSL = true;
    useACMEHost = "middleearth.samlockart.com";
    locations."/" = {
      proxyPass = "http://127.0.0.1:8384";
    };
  };
}
