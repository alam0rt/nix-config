{ config
, lib
, pkgs
, ... }:
let cfg = config.server;
in {
  networking.firewall.allowedTCPPorts = [
    6443 # k3s: required so that pods can reach the API server (running on port 6443 by default)
  ];
  services.k3s.enable = true;
  services.k3s.role = "server";
}
