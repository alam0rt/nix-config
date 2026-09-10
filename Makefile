TARGET_HOST ?= $(shell hostname)
BUILD_HOST := sauron

fmt:
	nix-shell -p alejandra --run "alejandra ."
.PHONY: fmt

build:
	nixos-rebuild build \
		--flake github:alam0rt/nix-config\#$(TARGET_HOST) \
		--target-host $(USER)@$(TARGET_HOST) \
		--build-host $(USER)@$(BUILD_HOST) \
		--use-remote-sudo

diff: build
	nvd diff /run/current-system result
.PHONY: diff

# Live USB image of the generic `portable` host.
# Writing it: sudo dd if=result/iso/nixos-portable.iso of=/dev/sdX bs=4M status=progress conv=fsync
# Offload with: make iso NIX_FLAGS="--builders ssh://$(USER)@$(BUILD_HOST)"
# (the image still has to come back here to be written to the stick).
iso:
	nix build .#portable-iso $(NIX_FLAGS)
.PHONY: iso
