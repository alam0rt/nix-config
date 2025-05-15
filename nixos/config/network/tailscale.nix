{ config, pkgs, ... }:
let
  loginServer = "https://hs.samlockart.com";
in
{
  services.tailscale = {
    enable = true;
    openFirewall = true;
    extraUpFlags = ["--login-server=${loginServer}"];
  };
  networking.firewall.trustedInterfaces = [ config.services.tailscale.interfaceName ];
  networking.firewall.checkReversePath = "loose";
}
