{ pkgs, ... }: {
  xdg = {
    enable = true;
    configFile."emacs" = {
      source = ./emacs;
      recursive = true;
    };
  };
  programs.emacs = {
    enable = true;
    extraPackages = epkgs: with epkgs; [
      doom-themes
      spacemacs-theme

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
#      straight-el
      use-package
      org
      org-roam
      org-roam-ui
      emacsql
      direnv
    ];
  };
}
