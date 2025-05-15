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
