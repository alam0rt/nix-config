let
  # Get the flake
  flake = builtins.getFlake (toString ../.);
  pkgs = flake.legacyPackages.x86_64-linux;
in

pkgs.testers.runNixOSTest {
  name = "laptop-boot-test";

  # Use the laptop configuration
  nodes.laptop = {
    imports = [
      ../nixos/configuration.nix
      ../nixos/laptop/configuration.nix
    ];
    _module.args = {
      inputs = flake.inputs;
      outputs = flake.outputs;
    };
  };

  testScript = ''
    # Start the machine and wait for it to boot
    laptop.start()
    laptop.wait_for_unit("default.target")
    
    # Verify the machine is running
    laptop.succeed("uname -a")
    
    # Shutdown the machine
    laptop.shutdown()
  '';
}
