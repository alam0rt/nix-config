# https://github.com/icewind1991/nvidia-patch-nixos
{
  pkgs,
  config,
  ...
}: let
  # nvidia package to patch
  package = config.boot.kernelPackages.nvidiaPackages.production;
in {
  hardware.nvidia.package = pkgs.nvidia-patch.patch-nvenc (pkgs.nvidia-patch.patch-fbc package);
}