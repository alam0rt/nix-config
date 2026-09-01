{pkgs, ...}: let
  # Dim to a fixed low level rather than a percentage of the current value, so
  # repeated dim/undim cycles can't walk the brightness down to nothing.
  dimLevel = "10%";
  brightness = "${pkgs.brightnessctl}/bin/brightnessctl --class=backlight";
in {
  xdg.configFile."niri/config.kdl".source = ./config.kdl;
  xdg.configFile."waybar/config.jsonc".source = ./waybar-config.jsonc;

  programs.fuzzel.enable = true; # Super+D in the default setting (app launcher)
  programs.swaylock.enable = true; # Super+Alt+L in the default setting (screen locker)
  programs.waybar.enable = true; # launch on startup in the default setting (bar)
  programs.waybar.systemd.enable = true;
  programs.waybar.style = ./waybar-style.css;
  services.mako.enable = true; # notification daemon

  # Idle handling. niri speaks ext-idle-notify and honours idle inhibitors, so
  # anything holding one (a fullscreen video, mpv, a game) stops these timers.
  # Audio playback alone doesn't inhibit anything, so sway-audio-idle-inhibit
  # below covers the "music/video playing in a background window" case too.
  services.swayidle = {
    enable = true;
    timeouts = [
      {
        timeout = 120;
        command = "${brightness} --save set ${dimLevel}";
        resumeCommand = "${brightness} --restore";
      }
      {
        timeout = 150;
        command = "${pkgs.niri}/bin/niri msg action power-off-monitors";
        # Any input wakes the monitors on its own, but ask explicitly so a
        # resume from a non-input source (e.g. dbus) doesn't leave them dark.
        resumeCommand = "${pkgs.niri}/bin/niri msg action power-on-monitors";
      }
    ];
  };

  # Holds a Wayland idle inhibitor while any sink is playing audio.
  systemd.user.services.sway-audio-idle-inhibit = {
    Unit = {
      Description = "Inhibit idle while audio is playing";
      PartOf = ["graphical-session.target"];
      After = ["graphical-session.target"];
    };
    Service = {
      ExecStart = "${pkgs.sway-audio-idle-inhibit}/bin/sway-audio-idle-inhibit";
      Restart = "on-failure";
    };
    Install.WantedBy = ["graphical-session.target"];
  };

  services.polkit-gnome.enable = true; # polkit
  home.packages = with pkgs; [
    brightnessctl # backlight control, also bound to the XF86MonBrightness keys
    swaybg # wallpaper
    xwayland-satellite # xwayland support
  ];
}
