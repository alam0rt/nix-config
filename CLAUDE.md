# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

### Format
```bash
nix fmt
# or via make:
make fmt
```

### Build a host
```bash
# Build for current hostname (default)
make build

# Build for a specific host
TARGET_HOST=sauron make build
# Builds are offloaded to sauron (BUILD_HOST)
```

### Apply NixOS config locally
```bash
sudo nixos-rebuild switch --flake .#<hostname>
```

### Apply home-manager config
```bash
home-manager switch --flake .#<username>
```

### Debug / inspect the flake
```bash
nix repl
> :lf .
```

### Secrets management (agenix-rekey)
```bash
# Edit a secret
nix run '.#agenix-rekey.x86_64-linux.edit-view' -- secrets/some-secret.age

# Rekey all secrets (after adding hosts or changing keys)
nix run '.#agenix-rekey.x86_64-linux.rekey'

# Generate a new secret
nix run '.#agenix-rekey.x86_64-linux.generate'
```

## Architecture

This is a NixOS + home-manager flake managing multiple hosts and a shared home environment.

### Flake structure
- **`flake.nix`** — defines inputs, NixOS configurations for `sauron`, `desktop`, `laptop`, and a default dev shell with `agenix-rekey`
- **`overlays/`** — three overlays applied everywhere: `additions` (custom pkgs), `modifications` (package patches), `unstable-packages` (exposes `pkgs.unstable` from nixpkgs-unstable)
- **`pkgs/`** — custom package derivations imported via the `additions` overlay
- **`modules/nixos`** and **`modules/home-manager`** — reusable exported modules (e.g. `vllm`)

### NixOS layer (`nixos/`)
- **`nixos/configuration.nix`** — shared base: overlays, nix settings, SSH, boot loader, zsh, agenix
- **`nixos/config/common/`** — nix GC/optimise, users, server defaults
- **`nixos/config/secrets/`** — agenix-rekey configuration; rekeyed secrets stored in `secrets/rekeyed/<hostname>/`
- **`nixos/<hostname>/configuration.nix`** — host-specific config that imports the shared base plus host services
- `sauron` is the primary server and runs many services (Matrix, Nginx, NAS, media, monitoring, mail, Home Assistant, vaultwarden, mumble, transmission, etc.)
- `desktop` and `laptop` are workstation configs

### Home-manager layer (`home-manager/`)
- **`home-manager/common.nix`** — shared home config: zsh, git, fzf, direnv, kitty, jujutsu, packages
- **`home-manager/linux.nix`** — Linux-specific home additions
- **`home-manager/config/`** — per-app configs (firefox, emacs, vscode, vim, kubernetes, ghostty, niri, etc.)
- Packages from `pkgs.unstable` (e.g. `go`, `podman`, `claude-code`) are accessed via the `unstable-packages` overlay

### Secrets
Secrets use [agenix-rekey](https://github.com/oddlama/agenix-rekey) with YubiKey FIDO2-HMAC master identities. Rekeyed secrets are committed to git under `nixos/config/secrets/rekeyed/`. See `nixos/config/secrets/agenix.md` for full workflow.

### Key conventions
- Use `pkgs.unstable.<name>` for packages that need to track nixpkgs-unstable
- `alejandra` is the Nix formatter (`nix fmt`)
- Channels are disabled; all inputs go through the flake
- `nix-ld` is enabled system-wide for running unpatched binaries

## Skill routing

When the user's request matches an available skill, ALWAYS invoke it using the Skill
tool as your FIRST action. Do NOT answer directly, do NOT use other tools first.
The skill has specialized workflows that produce better results than ad-hoc answers.

Key routing rules:
- Product ideas, "is this worth building", brainstorming → invoke office-hours
- Bugs, errors, "why is this broken", 500 errors → invoke investigate
- Ship, deploy, push, create PR → invoke ship
- QA, test the site, find bugs → invoke qa
- Code review, check my diff → invoke review
- Update docs after shipping → invoke document-release
- Weekly retro → invoke retro
- Design system, brand → invoke design-consultation
- Visual audit, design polish → invoke design-review
- Architecture review → invoke plan-eng-review
- Save progress, checkpoint, resume → invoke checkpoint
- Code quality, health check → invoke health
