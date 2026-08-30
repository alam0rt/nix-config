{
  lib,
  buildHomeAssistantComponent,
  fetchFromGitHub,
}:
buildHomeAssistantComponent rec {
  owner = "agittins";
  domain = "bermuda";
  # Pinned below the latest release: 0.8.7's device_tracker imports
  # BaseScannerEntity from homeassistant.components.device_tracker, which only
  # exists from HA 2026.6 onwards (core PR #171063, merged after the 2026.5
  # branch cut). nixos-26.05 ships 2026.5.4, so 0.8.7 fails to set up with an
  # ImportError. See https://github.com/agittins/bermuda/issues/780. Bump this
  # once nixpkgs carries HA >= 2026.6.
  version = "0.8.6";

  src = fetchFromGitHub {
    owner = "agittins";
    repo = "bermuda";
    tag = "v${version}";
    hash = "sha256-BCIb/MnI5EzK7ZS7qCsZB0l9LUTUgLO2Z0ZK7TnYnLM=";
  };

  # manifest.json declares no python requirements; its `dependencies` are HA
  # components (bluetooth_adapters, device_tracker, private_ble_device) which
  # are pulled in via services.home-assistant.extraComponents instead.

  meta = {
    description = "Room-level BLE presence for Home Assistant via ESPHome Bluetooth proxies";
    homepage = "https://github.com/agittins/bermuda";
    license = lib.licenses.mit;
    maintainers = [];
  };
}
