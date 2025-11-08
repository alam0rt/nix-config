{pkgs, ...}: {
  home.packages = with pkgs; [brewtarget];
}
