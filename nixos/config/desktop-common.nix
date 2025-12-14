{pkgs, ...}: {
  services.greetd = {
    enable = true;
    settings = {
      default_session = {
        command = "${pkgs.greetd}/bin/agreety --cmd \'${pkgs.niri}/bin/niri --session\'";
      };
    };
  };
  fonts.fontconfig = {
    defaultFonts = {
      sansSerif = [ "Noto Sans" "Liberation Sans" ];
      monospace = [ "Drafting Mono"];
      emoji = [ "Font Awesome" ];
    };
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
