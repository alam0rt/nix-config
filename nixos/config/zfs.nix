{
  config,
  pkgs,
  ...
}: {
  boot = {
    initrd.supportedFilesystems = ["zfs"];
    supportedFilesystems = ["zfs"];
    zfs.package = pkgs.zfs_unstable;
  };

  services.udev.extraRules = ''
    ACTION=="add|change", KERNEL=="sd[a-z]*[0-9]*|mmcblk[0-9]*p[0-9]*|nvme[0-9]*n[0-9]*p[0-9]*", ENV{ID_FS_TYPE}=="zfs_member", ATTR{../queue/scheduler}="none"
  ''; # zfs already has its own scheduler. without this my(@Artturin) computer froze for a second when i nix build something.

  services.zfs = {
    autoSnapshot.enable = true;
    autoScrub.enable = true;
  };
}
