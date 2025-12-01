# NixOS Integration Tests

This directory contains integration tests for the NixOS configurations using the NixOS VM testing framework.

## Available Tests

### laptop-boot-test

A simple test that verifies the laptop configuration can boot successfully and shut down cleanly.

### multi-machine-example

An example test demonstrating how to test multiple machines together (e.g., server and client). This is useful for testing network services, client-server interactions, or distributed systems.

## Running Tests

### Using the flake (recommended)

```bash
# Run the laptop boot test
nix build .#checks.x86_64-linux.laptop-boot-test

# The test will run and produce a result symlink if successful
```

### Using nix-build directly

```bash
# Run the standalone test file
nix-build tests/laptop-test.nix

# Run the multi-machine example
nix-build tests/multi-machine-example.nix
```

### Using Make targets

```bash
# Run the laptop boot test
make test-laptop

# Run the laptop test in interactive mode
make test-laptop-interactive
```

### Interactive mode

For debugging or development, you can run tests interactively:

```bash
# Build the interactive driver
$(nix-build -A driverInteractive .#checks.x86_64-linux.laptop-boot-test)/bin/nixos-test-driver

# Or for the standalone test:
$(nix-build -A driverInteractive tests/laptop-test.nix)/bin/nixos-test-driver
```

In the interactive Python shell, you can:

```python
# Start the machine
laptop.start()

# Wait for boot
laptop.wait_for_unit("default.target")

# Run commands
laptop.succeed("uname -a")

# Access an interactive shell
laptop.shell_interact()

# Run the full test script
test_script()

# Shutdown when done
laptop.shutdown()
```

## Writing New Tests

To create a new test:

1. Create a new `.nix` file in the `tests/` directory
2. Use the `pkgs.testers.runNixOSTest` function
3. Define your test nodes and test script
4. Optionally add it to the `checks` output in `flake.nix`

Example structure:

```nix
let
  nixpkgs = builtins.getFlake (toString ../.);
  pkgs = nixpkgs.legacyPackages.x86_64-linux;
in

pkgs.testers.runNixOSTest {
  name = "my-test";

  nodes.machine = {
    imports = [
      ../nixos/configuration.nix
      # Add your specific configuration
    ];
  };

  testScript = ''
    machine.start()
    machine.wait_for_unit("default.target")
    # Add your test commands
    machine.shutdown()
  '';
}
```

## Common Test Methods

- `machine.start()` - Start the virtual machine
- `machine.wait_for_unit("unit.service")` - Wait for a systemd unit
- `machine.succeed("command")` - Run a command that should succeed
- `machine.fail("command")` - Run a command that should fail
- `machine.wait_for_open_port(port)` - Wait for a network port to open
- `machine.shutdown()` - Shut down the machine cleanly
- `machine.shell_interact()` - Get an interactive shell

## Notes

- Tests run in QEMU virtual machines
- Hardware acceleration may not be available in CI environments
- See the [NixOS testing documentation](https://nix.dev/tutorials/nixos/integration-testing-using-virtual-machines) for more details
