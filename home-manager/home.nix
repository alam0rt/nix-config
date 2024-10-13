# This is your home-manager configuration file
# Use this to configure your home environment (it replaces ~/.config/nixpkgs/home.nix)
{
  inputs,
  outputs,
  lib,
  config,
  pkgs,
  ...
}: {
  # You can import other home-manager modules here
  imports = [
    # If you want to use modules your own flake exports (from modules/home-manager):
    # outputs.homeManagerModules.example

    # Or modules exported from other flakes (such as nix-colors):
    # inputs.nix-colors.homeManagerModules.default

    ./config/firefox.nix
    ./config/emacs.nix
    ./config/vscode.nix
    ./config/vim.nix
  ];

  nixpkgs = {
    # You can add overlays here
    overlays = [
      # Add overlays your own flake exports (from overlays and pkgs dir):
      outputs.overlays.additions
      outputs.overlays.modifications
      outputs.overlays.unstable-packages

      # You can also add overlays exported from other flakes:
      # neovim-nightly-overlay.overlays.default

      # Or define it inline, for example:
      # (final: prev: {
      #   hi = final.hello.overrideAttrs (oldAttrs: {
      #     patches = [ ./change-hello-to-hi.patch ];
      #   });
      # })
    ];
    # Configure your nixpkgs instance
    config = {
      # Disable if you don't want unfree packages
      allowUnfree = true;
    };
  };

  programs.direnv = {
    enable = true;
    enableBashIntegration = true;
    enableZshIntegration = true;
    nix-direnv.enable = true;
    };

  home = {
    username = "sam";
    homeDirectory = "/home/sam";
  };

  programs.zsh = {
    enable = true;
    initExtra = ''
      autoload -z edit-command-line
      zle -N edit-command-line
      bindkey "^X^E" edit-command-line

      # https://unix.stackexchange.com/questions/284105/zsh-hash-directory-completion
      setopt autocd cdable_vars

      # Make "kubecolor" borrow the same completion logic as "kubectl"
      compdef kubecolor=kubectl
      compdef ka=kubectl

      function ka() { 
          kubectl "$1" --as admin --as-group system:masters "''${@:2}";
      }
      if [[ -f "/home/sam/vault/kube" ]]; then
        export KUBECONFIG="/home/sam/vault/kube"
      fi
<<<<<<< HEAD
=======

     # Load session vars
     . ${config.home.profileDirectory}/etc/profile.d/hm-session-vars.sh
>>>>>>> origin/main
    '';
    shellAliases = {
      gst = "git status -s -b";
      gco = "git checkout";
      kubectl = "kubecolor";
      k = "kubectl";
      kgp = "kubectl get pods";
      glog = "git log -S";
    };
    dirHashes = {
      projects = "$HOME/projects";
    };
    history = {
      ignorePatterns = [
        "GITHUB_TOKEN"
      ];
    };
    autosuggestion = {
      enable = true;
    };
  };

  programs.fzf = {
    enable = true;
    enableZshIntegration = true;
  };

  home.file = {
    Docker.source = config.lib.file.mkOutOfStoreSymlink "${pkgs.podman}/bin/podman";
    Docker.target = "${config.home.homeDirectory}/.local/bin/docker";
  };

  home.packages = with pkgs; [
    # k8s
    kubectl
    kubectx
    kustomize
    kubecolor
    stern

    # core
    jq
    git
    gh
    yq
    ripgrep
    direnv

    # encryption
    gnupg
    sops

    # dev
    unstable.go
    podman
    qemu
    shellcheck
    jsonnet
<<<<<<< HEAD
    stern
    fzf
    unstable.go
    kustomize
    kubecolor
    direnv
    kitty
    nil # nix lsp
  ];

  programs.vscode = {
    enable = true;
    extensions = with pkgs.vscode-extensions; [
      dracula-theme.theme-dracula
      vscodevim.vim
      golang.go
      jnoortheen.nix-ide
    ];
  };
=======
    rust-analyzer

    # graphical
    keepassxc
  ];
>>>>>>> origin/main


  # terminal
  programs.kitty = {
    enable = true;
    #themeFile = "Ocean";
    shellIntegration = {
      enableZshIntegration = true;
    };
    settings = {
      window_padding_width = 10;
    };
    extraConfig = ''
      # Ocean
      # Theme ported from the Mac Terminal application.

      background #214fbc
      foreground #ffffff
      cursor #7f7f7f
      selection_background #216dff
      color0 #000000
      color8 #666666
      color1 #990000
      color9 #e50000
      color2 #00a600
      color10 #00d900
      color3 #999900
      color11 #e5e500
      color4 #0000b2
      color12 #0000ff
      color5 #b200b2
      color13 #e500e5
      color6 #00a6b2
      color14 #00e5e5
      color7 #bebebe
      color15 #e5e5e5
      selection_foreground #214fbc
    '';
  };

  # Enable home-manager and git
  programs.home-manager.enable = true;
  programs.git = {
    enable = true;
    userName = "alam0rt";
    userEmail = "sam@samlockart.com";
    aliases = {
      "new" = "!git checkout -b sam.lockart/$1 && :";
      "pl" = "!git fetch; git pull -r";
      "p" = "push";
      "untracked" = "ls-files --others --exclude-standard";
      "amend" = "commit -a --amend --no-edit";
      "rbm" = "!br=$((test -e .git/refs/remotes/origin/main && echo main) || echo master) && git fetch origin && git rebase origin/$br";
    };
    ignores = [
      ".idea/"
      "shell.nix"
      ".envrc"
      ".direnv/"
    ];
    extraConfig = {
      url."ssh://git@github.com/".insteadOf = "https://github.com/";
      push.autoSetupRemote = true;
      core.excludesfile = "${config.home.homeDirectory}/.gitignore";
    };
  };

  # Nicely reload system units when changing configs
  systemd.user.startServices = "sd-switch";

  # https://nixos.wiki/wiki/FAQ/When_do_I_update_stateVersion
  home.stateVersion = "23.05";
}
