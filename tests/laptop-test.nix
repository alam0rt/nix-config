{ pkgs, inputs, outputs }:

pkgs.testers.runNixOSTest {
  name = "laptop-boot-test";

  # Use the laptop configuration
  nodes.laptop = {
    imports = [
      ../nixos/configuration.nix
      ../nixos/laptop/configuration.nix
    ];
    _module.args = {
      inherit inputs outputs;
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
