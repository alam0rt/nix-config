{pkgs, ...}: {
  environment.systemPackages = [
    (pkgs.callPackage ../../pkgs/starcraft {
      gameZip = pkgs.starcraft-1161;

      # Resolved as a tailnet MagicDNS name, which works both at home and away —
      # unlike the LAN address, and unlike the public DNS, whose AAAA record goes
      # stale when sauron's DHCPv6 lease rotates. Change to 192.168.1.110 if
      # MagicDNS is ever off.
      serverAddress = "sauron";
      serverTitle = "WankNet";
    })
  ];

  # StarCraft's own game traffic is peer-to-peer UDP on 6112 once a lobby starts
  # — PvPGN only brokers the lobby — so hosting a game needs the port open
  # inbound. Same range bwheadless uses for LAN play, which is what a bot would
  # join over (see nixos/sauron/bwapi/README.md).
  networking.firewall.interfaces.tailscale0 = {
    allowedUDPPorts = [6111 6112];
    allowedTCPPorts = [6112];
  };
}
