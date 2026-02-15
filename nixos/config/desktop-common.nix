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

  # platformio / embedded dev
  services.udev.packages = with pkgs; [
    platformio-core.udev
    openocd
  ];

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
  ];

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
