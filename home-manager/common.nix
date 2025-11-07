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
    ./config/kubernetes.nix
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

  # Required when using unstable branch
  home.enableNixpkgsReleaseCheck = false;
  home.sessionPath = [ "$HOME/.local/bin" "$HOME/go/bin" ];


  programs.zsh = {
    enable = true; # must also be enabled in nixos
    initContent = ''
      autoload -z edit-command-line
      zle -N edit-command-line
      bindkey "^X^E" edit-command-line

      # https://unix.stackexchange.com/questions/284105/zsh-hash-directory-completion
      setopt autocd cdable_vars

      # Make "kubecolor" borrow the same completion logic as "kubectl"
      compdef kubecolor=kubectl
      compdef ka=kubectl

      function ka () {
          kubectl "$1" --as admin --as-group system:masters "''${@:2}";
      }

      function kc () {
          kubectl get --as admin --as-group system:masters --raw "/api/v1/nodes/$1/proxy/configz" "''${@:2}" | jq .
      }

      if [[ -f "/home/sam/vault/kube" ]]; then
        export KUBECONFIG="/home/sam/vault/kube"
      fi

      export GOPRIVATE="github.com/alam0rt/*,github.com/zendesk/*"

      # Load session vars
      . ${config.home.profileDirectory}/etc/profile.d/hm-session-vars.sh

      if [ -e '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh' ]; then
        . '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh'
      fi
    '';
    history = {
      extended = true;
      share = true;
      append = true;
      save = 100000000;
      size = 100000000;
      ignoreSpace = true;
      ignoreDups = true;
      expireDuplicatesFirst = true;
    };
    shellAliases = {
      gst = "git status -s -b";
      gco = "git checkout";
      kubectl = "kubecolor";
      k = "kubectl";
      kgp = "kubectl get pods";
      glog = "git log -S";
      s = "kitten ssh";
    };
    dirHashes = {
      projects = "$HOME/projects";
    };
    history = {
      ignorePatterns = ["GITHUB_TOKEN"];
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
    Docker.source = config.lib.file.mkOutOfStoreSymlink "${pkgs.unstable.podman}/bin/podman";
    Docker.target = "${config.home.homeDirectory}/.local/bin/docker";
  };

  home.sessionVariables = {
    EDITOR = "vim";
  };

  home.packages = with pkgs; [
    # k8s
    kubectl
    kubectx
    kustomize
    kubectl-explore
    kubernetes-helm
    kubecolor
    stern
    fluxcd
    buildah

    # core
    jq
    git
    gh
    ast-grep
    yq-go
    ripgrep
    direnv

    # encryption
    gnupg
    sops
    yubikey-manager

    # dev
    unstable.go
    unstable.podman
    unstable.podman-compose

    qemu
    shellcheck
    go-jsonnet # preferred over jsonnet
    fzf
    hyperfine
    fd
    bat
    unstable.go
    direnv
    unstable.delve
    nil # nix lsp
    rust-analyzer
    uv

    # terminals
    kitty

    # trying out
    duckdb

    # graphical
    p7zip-rar

    # CAD / 3d
    openscad
    openscad-lsp

    comma
  ] ++ lib.optionals stdenv.isDarwin [
    # macOS only packages

    unstable.vfkit # for podman

    iterm2
    obsidian
    saml2aws
    awscli2
    vendir
    ssm-session-manager-plugin
    amazon-ecr-credential-helper
    rolecule
    scaffold
    argocd

  ] ++ lib.optionals stdenv.isLinux [
    # design and 3d
    super-slicer-latest
    freecad

    # development
    gdb

    # embedded development
    platformio
    esptool
    # inputs.pcsx-redux.packages.${system}.pcsx-redux

  ];

  # terminal
  programs.kitty = {
    enable = true;
    shellIntegration = {
      enableZshIntegration = true;
    };
    settings = {
      window_padding_width = 10;
    };
  };

  programs.jujutsu.enable = true;
  programs.jujutsu.settings.user.name = config.programs.git.userName;
  programs.jujutsu.settings.user.email = config.programs.git.userEmail;
  programs.jujutsu.settings.git.push-new-bookmarks = true;

  # Enable home-manager and git
  programs.home-manager.enable = true;

  xdg = {
    configFile = {
      "containers/policy.json" = {
        enable = true;
        text = builtins.toJSON {
          # https://github.com/containers/image/blob/main/docs/containers-policy.json.5.md
          default = [{type = "insecureAcceptAnything";}];
        };
      };
    };
  };

  programs.git = {
    enable = true;
    lfs.enable = true;
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
      ".DS_Store"
    ];
    extraConfig = {
      url = {
        "ssh://git@github.com/" = {
          insteadOf = "https://github.com/";
        };
      };
      safe.directory = "/nix/store/*";
      push.autoSetupRemote = true;
      core.excludesfile = "${config.home.homeDirectory}/.gitignore";
    };
  };

  # Nicely reload system units when changing configs
  systemd.user.startServices = "sd-switch";

  # https://nixos.wiki/wiki/FAQ/When_do_I_update_stateVersion
  home.stateVersion = "24.11";
}
