let
  nixpkgs = builtins.getFlake (toString ../.);
  pkgs = nixpkgs.legacyPackages.x86_64-linux;
in

pkgs.testers.runNixOSTest {
  name = "multi-machine-example";

  # Define multiple machines
  nodes = {
    server = {
      imports = [
        ../nixos/configuration.nix
        ../nixos/sauron/configuration.nix
      ];
    };
    
    client = {
      imports = [
        ../nixos/configuration.nix
        ../nixos/laptop/configuration.nix
      ];
    };
  };

  testScript = ''
    # Start all machines
    start_all()
    
    # Wait for both machines to boot
    server.wait_for_unit("default.target")
    client.wait_for_unit("default.target")
    
    # Verify both machines are running
    server.succeed("echo 'Server is up'")
    client.succeed("echo 'Client is up'")
    
    # Example: Test network connectivity between machines
    # server.wait_for_open_port(22)
    # client.succeed("ping -c 1 server")
    
    # Shutdown both machines
    server.shutdown()
    client.shutdown()
  '';
}
