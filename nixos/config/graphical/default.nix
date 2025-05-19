{...}: {
  # Enable the X11 windowing system.
  services.xserver = {
    enable = true;
    xkb.layout = "us";
    desktopManager = {
      xterm.enable = false;
      xfce.enable = true;
    };
  };

  # enable XFCE as the default desktop manager
  services.displayManager.defaultSession = "xfce";
}
