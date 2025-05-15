{ pkgs, ... }:
{
  xdg = {
    # emacs requires XDG_CONFIG_HOME to be set
    # example:
    #   '. ${config.home.profileDirectory}/etc/profile.d/hm-session-vars.sh'
    enable = true;
    configFile."emacs" = {
      source = ./emacs;
      recursive = true;
    };
  };
  home.packages = with pkgs; [
    inconsolata # font of choice
    nodejs # for copilot.el
  ];
  programs.emacs = {
    enable = true;
    extraPackages =
      epkgs: with epkgs; [
        doom-themes
        spacemacs-theme

        highlight-indent-guides
        evil
        company
        magit
        flycheck
        geiser-guile
        geiser
        smartparens
        evil-smartparens
        lsp-mode
        exec-path-from-shell
        elpy
        company-quickhelp
        rustic
        which-key
        markdown-mode
        projectile
        go-mode
        slime
        rg
        use-package
        org
        org-roam
        org-roam-ui
        emacsql
        direnv
      ];
  };
}
