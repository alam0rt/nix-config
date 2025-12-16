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
