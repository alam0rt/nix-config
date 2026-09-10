# A generic, hardware-agnostic version of the laptop/desktop config.
#
# Everything here has to hold on a machine we have never seen before, so:
#   - no ./hardware-configuration.nix (no UUIDs, no swap device, no per-box
#     kernel modules) - the media module supplies the file systems instead
#   - no vendor GPU driver: the in-tree kernel drivers (i915/amdgpu/nouveau)
#     plus modesetting cover whatever we land on, whereas the nvidia module
#     on unknown hardware is a black screen
#   - no nixos-hardware profile, no syncthing (its device IDs are per-host)
#
# Built as a live ISO by ./iso.nix; see docs/portable-usb.md.
{
  lib,
  pkgs,
  ...
}: {
  imports = [
    ../config/common
    ../config/network
    ../config/network/nfs_mounts.nix
    ../config/home-manager.nix
    ../config/desktop-common.nix
  ];

  networking.hostName = "portable";
  networking.hostId = "0fbadc0d"; # only read by ZFS, which we don't use here

  networking.networkmanager.enable = true;
  networking.wireless.userControlled = true;
  networking.firewall.enable = true;

  # We don't know the target platform, so ask for every driver and every
  # firmware blob rather than the detected-hardware subset.
  nixpkgs.hostPlatform = "x86_64-linux";
  hardware.enableAllHardware = true;
  hardware.enableAllFirmware = true;

  # Newer kernel than the default: this stick is expected to boot machines
  # newer than the config, and the LTS default drops recent laptops.
  boot.kernelPackages = pkgs.linuxPackages_latest;

  hardware.graphics = {
    enable = true;
    enable32Bit = true;
  };

  # No swap partition on a live stick, and the machines this ends up in may
  # be short on RAM.
  zramSwap.enable = true;

  # Steam is the single largest thing in desktop-common (several GB of the
  # image). Set this to false if the ISO needs to fit a smaller stick - it
  # needs the mkForce, because desktop-common enables it outright.
  programs.steam.enable = lib.mkForce true;

  # On the fixed hosts sam is only ever in the local seat's polkit rules for
  # this; on a stick that boots strange machines it is worth being explicit,
  # since re-joining wifi is the first thing that happens after boot.
  users.users.sam.extraGroups = ["networkmanager" "video"];

  system.stateVersion = "26.05";
}
