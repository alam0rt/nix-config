{
  lib,
  pkgs,
  ...
}: let
  # Shared with nixos/sauron/bwapi — one hash, both consumers. Null until a copy
  # of the game has been added to the store; see pkgs/starcraft-1161/hash.nix.
  gameHash = import ../../pkgs/starcraft-1161/hash.nix;

  # Only forced under the mkIf below: requireFile asserts on a null hash during
  # evaluation, not at build time.
  gameZip = pkgs.callPackage ../../pkgs/starcraft-1161 {hash = gameHash;};

  starcraft = pkgs.callPackage ../../pkgs/starcraft {
    inherit gameZip;

    # Resolved on the laptop as a tailnet MagicDNS name, which works both at
    # home and away — unlike the LAN address, and unlike the public DNS, whose
    # AAAA record goes stale when sauron's DHCPv6 lease rotates. Change to
    # 192.168.1.110 if MagicDNS is ever off.
    serverAddress = "sauron";
    serverTitle = "WankNet";
  };
in
  lib.mkIf (gameHash != null) {
    environment.systemPackages = [starcraft];

    # StarCraft's own game traffic is peer-to-peer UDP on 6112 once a lobby
    # starts — PvPGN only brokers the lobby — so hosting a game needs the port
    # open inbound. Same range bwheadless uses for LAN play, which is what a bot
    # would join over (see nixos/sauron/bwapi/README.md).
    networking.firewall.interfaces = {
      tailscale0 = {
        allowedUDPPorts = [6111 6112];
        allowedTCPPorts = [6112];
      };
    };
  }
