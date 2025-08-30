#!/usr/bin/env bash

nixos-rebuild build-vm --flake ~/nix-config#sauron

# Run the vm
# Accepts qemu args
result/bin/run-nixos-vm --nographics --memsize 4096 "$@"

# run borg backup
#
```bash
BORG_PASSCOMMAND='agenix -d borg.age' BORG_REPO='
