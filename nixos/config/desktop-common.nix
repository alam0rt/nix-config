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
      monospace = ["Fira Code" "Noto Mono" "Liberation Mono"];
      emoji = ["Noto Color Emoji"];
    };
  };

  security.pam.services.swaylock = {};

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
