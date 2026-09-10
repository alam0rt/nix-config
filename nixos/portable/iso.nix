# Turns the `portable` host into a bootable live ISO.
#
#   nix build .#portable-iso
#   sudo dd if=result/iso/nixos-portable.iso of=/dev/sdX bs=4M status=progress conv=fsync
#
# iso-image.nix supplies the file systems (a squashfs store on the medium with
# a tmpfs overlay on top), so nothing on the running system is persistent: the
# store is read-only, /home and /var start empty on every boot, and
# `nixos-rebuild switch` cannot work. Rebuild the ISO instead.
{
  lib,
  modulesPath,
  ...
}: {
  imports = [
    (modulesPath + "/installer/cd-dvd/iso-image.nix")
  ];

  # The shared base installs systemd-boot onto a real ESP; the ISO carries its
  # own GRUB/syslinux payload and must not try.
  boot.loader.systemd-boot.enable = lib.mkForce false;
  boot.loader.efi.canTouchEfiVariables = lib.mkForce false;

  # BIOS booting is already on by default for x86; these two are what make the
  # image boot on UEFI machines and from a USB stick rather than only a CD.
  isoImage.makeEfiBootable = true;
  isoImage.makeUsbBootable = true;

  # The default zstd level 19 spends a very long time on a desktop-sized
  # closure for a few percent of size.
  isoImage.squashfsCompression = "zstd -Xcompression-level 6";

  # Volume ID doubles as the root=LABEL= stage-1 looks for; max 32 chars.
  isoImage.volumeID = "NIXOS-PORTABLE";
  image.baseName = "nixos-portable";
}
