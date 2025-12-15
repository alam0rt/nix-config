{
  description = "Your new nix config";

  inputs = {
    # Nixpkgs
    nixpkgs.url = "github:nixos/nixpkgs/nixos-25.11";
    # You can access packages and modules from different nixpkgs revs
    # at the same time. Here's an working example:
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";
    # Also see the 'unstable-packages' overlay at 'overlays/default.nix'.

    # Home manager
    home-manager.url = "github:nix-community/home-manager/release-25.11";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    # s3cr3ts
    agenix.url = "github:ryantm/agenix";
    agenix-rekey.url = "github:oddlama/agenix-rekey";
    # Make sure to override the nixpkgs version to follow your flake,
    # otherwise derivation paths can mismatch (when using storageMode = "derivation"),
    # resulting in the rekeyed secrets not being found!
    agenix-rekey.inputs.nixpkgs.follows = "nixpkgs";

    # pvpgn
    pvpgnix.url = "github:alam0rt/pvpgnix";
    pvpgnix.inputs.nixpkgs.follows = "nixpkgs";

    # pcsx-redux
    pcsx-redux.url = "github:grumpycoders/pcsx-redux";
    pcsx-redux.inputs.nixpkgs.follows = "nixpkgs-unstable";

    # nvidia-patch
    nvidia-patch.url = "github:icewind1991/nvidia-patch-nixos";
    nvidia-patch.inputs.nixpkgs.follows = "nixpkgs";

    # ai
    llama-cpp.url = "github:ggml-org/llama.cpp";

    # hardware modules
    nixos-hardware.url = "github:NixOS/nixos-hardware/master";

    nur = {
      url = "github:nix-community/NUR";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = {
    self,
    nixpkgs,
    home-manager,
    nixos-hardware,
    ...
  } @ inputs: let
    inherit (self) outputs;
    # Supported systems for your flake packages, shell, etc.
    systems = [
      "aarch64-linux"
      "i686-linux"
      "x86_64-linux"
      "aarch64-darwin"
      "x86_64-darwin"
    ];
    # This is a function that generates an attribute by calling a function you
    # pass to it, with each system as an argument
    forAllSystems = nixpkgs.lib.genAttrs systems;
  in {
    # Your custom packages
    # Accessible through 'nix build', 'nix shell', etc
    packages = forAllSystems (system: import ./pkgs nixpkgs.legacyPackages.${system});
    # Formatter for your nix files, available through 'nix fmt'
    # Other options beside 'alejandra' include 'nixpkgs-fmt'
    formatter = forAllSystems (system: nixpkgs.legacyPackages.${system}.alejandra);

    # Your custom packages and modifications, exported as overlays
    overlays = import ./overlays {inherit inputs;};
    # Reusable nixos modules you might want to export
    # These are usually stuff you would upstream into nixpkgs
    nixosModules = import ./modules/nixos;
    # Reusable home-manager modules you might want to export
    # These are usually stuff you would upstream into home-manager
    homeManagerModules = import ./modules/home-manager;

    # NixOS configuration entrypoint
    # Available through 'nixos-rebuild --flake .#your-hostname'
    nixosConfigurations = {
      sauron = nixpkgs.lib.nixosSystem {
        specialArgs = {
          inherit inputs outputs;
        };
        modules = [
          # removed pvpgn
          ./nixos/configuration.nix
          ./nixos/sauron/configuration.nix
          inputs.agenix.nixosModules.default
          inputs.agenix-rekey.nixosModules.default
        ];
      };
      desktop = nixpkgs.lib.nixosSystem {
        specialArgs = {
          inherit inputs outputs;
        };
        modules = [
          ./nixos/configuration.nix
          ./nixos/desktop/configuration.nix
          inputs.agenix.nixosModules.default
          inputs.agenix-rekey.nixosModules.default
        ];
      };
      laptop = nixpkgs.lib.nixosSystem {
        specialArgs = {
          inherit inputs outputs;
        };
        modules = [
          ./nixos/configuration.nix
          ./nixos/laptop/configuration.nix
          inputs.agenix.nixosModules.default
          inputs.agenix-rekey.nixosModules.default
          nixos-hardware.nixosModules.lenovo-thinkpad-x1-extreme-gen2
        ];
      };
      frodo = nixpkgs.lib.nixosSystem {
        specialArgs = {
          inherit inputs outputs;
        };
        modules = [
          ./nixos/configuration.nix
          ./nixos/frodo/configuration.nix
          inputs.agenix.nixosModules.default
          inputs.agenix-rekey.nixosModules.default
        ];
      };
    };

    agenix-rekey = inputs.agenix-rekey.configure {
      userFlake = self;
      # Only include hosts that use secrets
      nixosConfigurations = {
        inherit (self.nixosConfigurations) sauron laptop frodo desktop;
      };
    };

    devShells = forAllSystems (system: let
      pkgs = import nixpkgs {
        inherit system;
        overlays = [inputs.agenix-rekey.overlays.default];
      };
    in {
      default = pkgs.mkShell {
        packages = [pkgs.agenix-rekey];
      };
    });
  };
}
