{pkgs, ...}: {
  services.greetd = {
    enable = true;
    settings = {
      default_session = {
        command = "${pkgs.greetd}/bin/agreety --cmd \'${pkgs.uwsm}/bin/uwsm start -- niri-uwsm.desktop\'";
      };
    };
  };
  fonts.fontconfig = {
    defaultFonts = {
      sansSerif = ["Noto Sans" "Liberation Sans"];
      monospace = ["Drafting Mono"];
      emoji = ["Font Awesome"];
    };
  };

  services.gvfs.enable = true; # enables support for virtual filesystems (e.g. network shares, trash, etc.) in file managers
  services.udisks2.enable = true; # enables support for external drives and media

  # bluetooth
  services.blueman.enable = true;
  hardware.bluetooth.enable = true; # enables support for Bluetooth
  hardware.bluetooth.powerOnBoot = true; # powers up the default Bluetooth controller on boot

  # audio - PipeWire setup per https://wiki.nixos.org/wiki/PipeWire
  security.rtkit.enable = true; # allows PipeWire to use realtime scheduler
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true; # for 32-bit apps like Steam
    pulse.enable = true;
    # jack.enable = true; # uncomment if JACK apps needed
  };

  # Bluetooth audio codecs for better quality
  services.pipewire.wireplumber.extraConfig."10-bluez" = {
    "monitor.bluez.properties" = {
      "bluez5.enable-sbc-xq" = true;
      "bluez5.enable-msbc" = true;
      "bluez5.enable-hw-volume" = true;
      "bluez5.roles" = ["hsp_hs" "hsp_ag" "hfp_hf" "hfp_ag"];
    };
  };

  # steam
  programs.steam = {
    enable = true;
    remotePlay.openFirewall = true; # Open ports in the firewall for Steam Remote Play
    dedicatedServer.openFirewall = true; # Open ports in the firewall for Source Dedicated Server
    localNetworkGameTransfers.openFirewall = true; # Open ports in the firewall for Steam Local Network Game Transfers
  };

  services.udev.packages = with pkgs; [
    # platformio / embedded dev
    platformio-core.udev
    openocd
    # Lets brightnessctl (idle dimming, XF86MonBrightness keys) write the
    # backlight as a user instead of going through the logind D-Bus path.
    brightnessctl
  ];

  # SmartLink SL6801 USB service modes, for the yp3box Rockbox port.
  #
  #   301a:2800  the boot ROM's download service - flash, dump, exec
  #   301a:2801  the vendor firmware's card-reader mode
  #
  # smtlink_dump talks to these over libusb, which needs write access to
  # /dev/bus/usb/*, and it also detaches the kernel usb-storage driver from
  # 2801 (USBDEVFS_DISCONNECT), which needs the same. Without a rule that is
  # root-only, so every flash, dump and log read went through sudo.
  #
  # Both handles are given because they cover different sessions: uaccess is a
  # logind ACL for whoever is on the local seat, which is the normal case and
  # needs no group; the dialout group covers a session with no seat, such as
  # ssh, and sam is already in it.
  services.udev.extraRules = ''
    SUBSYSTEM=="usb", ENV{DEVTYPE}=="usb_device", ATTR{idVendor}=="301a", ATTR{idProduct}=="2800", MODE="0660", GROUP="dialout", TAG+="uaccess"
    SUBSYSTEM=="usb", ENV{DEVTYPE}=="usb_device", ATTR{idVendor}=="301a", ATTR{idProduct}=="2801", MODE="0660", GROUP="dialout", TAG+="uaccess"
  '';

  # Avahi for mDNS / Zeroconf service discovery (e.g. for Chromecast support in media players)
  services.avahi.enable = true;

  programs.wireshark = {
    enable = true;
  };

  security.pam.services.swaylock.text = ''
    # Account management.
    account required pam_unix.so

    # Authentication management.
    auth sufficient pam_unix.so   likeauth try_first_pass
    auth required pam_deny.so

    # Password management.
    password sufficient pam_unix.so nullok sha512

    # Session management.
    session required pam_env.so conffile=/etc/pam/environment readenv=0
    session required pam_unix.so
  '';

  programs.uwsm = {
    enable = true;
    waylandCompositors = {
      niri = {
        prettyName = "Niri";
        comment = "Dynamic, scrollable tiling Wayland compositor";
        binPath = "/run/current-system/sw/bin/niri-session";
      };
    };
  };

  environment.systemPackages = with pkgs; [
    niri
    kdePackages.dolphin
    kdePackages.dolphin-plugins
    pavucontrol # PulseAudio-compatible volume control (works with PipeWire)
    pwvucontrol # native PipeWire volume control
    jmtpfs # MTP file manager for Android devices
  ];

  # KDE Connect ports (set up in home-manager/linux.nix for user services.kdeconnect.enable)
  networking.firewall = rec {
    allowedTCPPortRanges = [
      {
        from = 1714;
        to = 1764;
      }
    ];
    allowedUDPPortRanges = allowedTCPPortRanges;
  };

  fonts.packages = with pkgs; [
    font-awesome
    # serif mono
    drafting-mono
    # fun small font
    fairfax
    fairfax-hd
    # nerd-fonts is a collection so map over all keys
    nerd-fonts.inconsolata
    nerd-fonts.noto
    nerd-fonts.meslo-lg
    nerd-fonts.dejavu-sans-mono
    nerd-fonts.departure-mono
    noto-fonts-cjk-sans
    noto-fonts-color-emoji
    liberation_ttf
    fira-code
    fira-code-symbols
    mplus-outline-fonts.githubRelease
    dina-font
    proggyfonts
  ];
}
