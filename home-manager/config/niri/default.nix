{pkgs, ...}: let
  # Dim to a fixed low level rather than a percentage of the current value, so
  # repeated dim/undim cycles can't walk the brightness down to nothing.
  dimLevel = "10%";
  brightness = "${pkgs.brightnessctl}/bin/brightnessctl --class=backlight";
  niri = "${pkgs.niri}/bin/niri";
  swaylock = "${pkgs.swaylock-effects}/bin/swaylock";

  # Idle timings, in seconds from the start of the idle period (swayidle counts
  # every timeout from idle start, not from the previous step). Shaped like
  # macOS: dim as a warning, lock a little later, then blank the panel. macOS
  # uses a far shorter chain on battery than on mains, so each step exists
  # twice and is guarded on the current power source.
  timings = {
    battery = {
      dim = 30;
      lock = 90;
      blank = 120;
    };
    mains = {
      dim = 540;
      lock = 600;
      blank = 630;
    };
  };

  # Sourced by every idle script.
  #
  # /sys/class/power_supply/AC/online is 1 on mains and 0 on battery. An
  # unreadable path is treated as mains so a machine with no battery takes the
  # long timings instead of blanking after 30 seconds.
  #
  # The flag file makes dimming idempotent. Both profiles' dim steps can fire
  # in one idle period if the charger is plugged or pulled while idle, and a
  # second `--save` would record the already-dimmed 10% as the real brightness
  # and strand the backlight there on resume.
  prelude = ''
    flag="''${XDG_RUNTIME_DIR:-/tmp}/niri-idle-dimmed"
    online=$(cat /sys/class/power_supply/AC/online 2>/dev/null || echo 1)
  '';
  onlyOn = profile:
    if profile == "battery"
    then ''[ "$online" = "0" ] || exit 0''
    else ''[ "$online" = "1" ] || exit 0'';

  dimScript = profile:
    pkgs.writeShellScript "niri-idle-dim-${profile}" ''
      ${prelude}
      ${onlyOn profile}
      [ -e "$flag" ] && exit 0
      ${brightness} --save set ${dimLevel}
      : > "$flag"
    '';

  blankScript = profile:
    pkgs.writeShellScript "niri-idle-blank-${profile}" ''
      ${prelude}
      ${onlyOn profile}
      ${niri} msg action power-off-monitors
    '';

  # swaylock is a singleton, so check before starting one: a duplicate would
  # otherwise appear on top of an instance that already has a password typed
  # into it. -f forks, so swayidle's -w doesn't block on the lock staying up.
  lockScript = pkgs.writeShellScript "niri-lock" ''
    ${pkgs.procps}/bin/pgrep -x swaylock > /dev/null && exit 0
    exec ${swaylock} -f
  '';

  lockScriptFor = profile:
    pkgs.writeShellScript "niri-idle-lock-${profile}" ''
      ${prelude}
      ${onlyOn profile}
      exec ${lockScript}
    '';

  # Resume commands are deliberately *not* guarded on the power source: if the
  # charger state changed while idle, the guard would skip the undim and leave
  # the backlight at 10%. Both are harmless to run when nothing was dimmed or
  # blanked.
  undimScript = pkgs.writeShellScript "niri-idle-undim" ''
    ${prelude}
    [ -e "$flag" ] || exit 0
    rm -f "$flag"
    ${brightness} --restore
  '';

  idleSteps = profile: let
    t = timings.${profile};
  in [
    {
      timeout = t.dim;
      command = "${dimScript profile}";
      resumeCommand = "${undimScript}";
    }
    {
      timeout = t.lock;
      command = "${lockScriptFor profile}";
    }
    {
      timeout = t.blank;
      command = "${blankScript profile}";
      # Any input wakes the monitors on its own, but ask explicitly so a
      # resume from a non-input source (e.g. dbus) doesn't leave them dark.
      resumeCommand = "${niri} msg action power-on-monitors";
    }
  ];

  # A wl-paste watcher feeding one MIME type into the cliphist store.
  cliphistWatch = type: {
    Unit = {
      Description = "Store ${type} clipboard selections in cliphist";
      PartOf = ["graphical-session.target"];
      After = ["graphical-session.target"];
    };
    Service = {
      ExecStart = "${pkgs.wl-clipboard}/bin/wl-paste --type ${type} --watch ${pkgs.cliphist}/bin/cliphist store";
      Restart = "on-failure";
    };
    Install.WantedBy = ["graphical-session.target"];
  };
in {
  xdg.configFile."niri/config.kdl".source = ./config.kdl;
  xdg.configFile."waybar/config.jsonc".source = ./waybar-config.jsonc;

  programs.fuzzel.enable = true; # Super+D in the default setting (app launcher)

  # swaylock-effects is a fork of swaylock that can use a screenshot of the
  # session as the lock background and run it through blur/vignette, and draw a
  # clock in the indicator. Its binary is still called `swaylock`, so the
  # security.pam.services.swaylock stack in nixos/config/desktop-common.nix
  # keeps applying unchanged.
  programs.swaylock = {
    enable = true; # Super+Alt+L, and the swayidle chain below
    package = pkgs.swaylock-effects;
    settings = {
      screenshots = true;
      clock = true;
      indicator = true;
      indicator-radius = 100;
      indicator-thickness = 7;
      effect-blur = "7x5";
      effect-vignette = "0.5:0.5";
      fade-in = 0.2;
      # Swallow the stray keypress that wakes the machine instead of counting
      # it as a failed attempt.
      ignore-empty-password = true;
      show-failed-attempts = true;
    };
  };
  programs.waybar.enable = true; # launch on startup in the default setting (bar)
  programs.waybar.systemd.enable = true;
  programs.waybar.style = ./waybar-style.css;
  services.mako.enable = true; # notification daemon

  # Idle handling. niri speaks ext-idle-notify and honours idle inhibitors, so
  # anything holding one (a fullscreen video, mpv, a game) stops these timers.
  # Audio playback alone doesn't inhibit anything, so sway-audio-idle-inhibit
  # below covers the "music/video playing in a background window" case too.
  #
  # The lock step comes *before* the blank step on purpose. swaylock-effects
  # screenshots the session to build its background, so starting it after the
  # panel is already off would blur a black frame.
  services.swayidle = {
    enable = true;
    timeouts = idleSteps "battery" ++ idleSteps "mains";
    events = {
      # Lock before suspending, so a resume never flashes the desktop. swayidle
      # runs with -w, which makes it wait for this to finish first.
      before-sleep = "${lockScript}";
      # `loginctl lock-session`, and anything else that asks logind to lock.
      lock = "${lockScript}";
      after-resume = "${niri} msg action power-on-monitors";
    };
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

  # Clipboard history. wl-paste --watch fires on every new selection and hands
  # it to cliphist, which keeps a small database in ~/.cache/cliphist. Mod+P
  # (see config.kdl) pipes `cliphist list` through fuzzel to pick an entry.
  #
  # Two watchers are needed because `wl-paste --watch` is per-MIME-type: one
  # for text, one for images. Without the image one, screenshots and copied
  # images are simply not recorded.
  systemd.user.services.cliphist-text = cliphistWatch "text";
  systemd.user.services.cliphist-image = cliphistWatch "image";

  services.polkit-gnome.enable = true; # polkit
  home.packages = with pkgs; [
    brightnessctl # backlight control, also bound to the XF86MonBrightness keys
    swaybg # wallpaper
    xwayland-satellite # xwayland support
    wl-clipboard # wl-copy / wl-paste, also the clipboard history watchers above
    cliphist # clipboard history store, picked through fuzzel on Mod+P
    playerctl # the XF86Audio* binds in config.kdl call this
  ];
}
