{pkgs, ...}: {
  programs.ghostty = {
    enable = true;
    package = if pkgs.stdenv.isDarwin then pkgs.ghostty-bin else pkgs.ghostty;

    # quick start-up
    systemd.enable = if pkgs.stdenv.isDarwin then false else true;

    installVimSyntax = true;
    enableZshIntegration = true;

    settings = {
      theme = "Abernathy";
      background-opacity = "0.95";
    };
  };
}
