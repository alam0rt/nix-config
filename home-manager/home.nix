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

  programs.neovim = {
    enable = true;
    viAlias = true;
    vimAlias = true;
    extraConfig = ''
      set number

      set tabstop     =4
      set softtabstop =4
      set shiftwidth  =4
      set expandtab

    '';
    plugins = [
        {
            plugin = pkgs.vimPlugins.vim-sneak;
            config = "let g:sneak#label = 1";
        }
    ];
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

     # Load session vars
     . ${config.home.profileDirectory}/etc/profile.d/hm-session-vars.sh
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
    rust-analyzer

    # graphical
    keepassxc
  ];

  programs.vscode = {
    enable = true;
      extensions = with pkgs.vscode-extensions; [
        # core
        dracula-theme.theme-dracula
        vscodevim.vim

        # golang
        golang.go

        # rust
        rust-lang.rust-analyzer

        # ruby
        shopify.ruby-lsp

        # nix
        jnoortheen.nix-ide

        # terraform
        hashicorp.hcl

        # linux
        timonwong.shellcheck
        coolbear.systemd-unit-file

        # extras
        signageos.signageos-vscode-sops
        ms-vscode-remote.remote-ssh
        github.copilot
        github.copilot-chat
        ms-vscode.makefile-tools
    ];
  };

  # Enable home-manager and git
  programs.home-manager.enable = true;
  programs.git = {
    enable = true;
    userName = "alam0rt";
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
