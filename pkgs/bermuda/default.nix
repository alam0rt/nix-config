{
  lib,
  buildHomeAssistantComponent,
  fetchFromGitHub,
}:
buildHomeAssistantComponent rec {
  owner = "agittins";
  domain = "bermuda";
  version = "0.8.7";

  src = fetchFromGitHub {
    owner = "agittins";
    repo = "bermuda";
    tag = "v${version}";
    hash = "sha256-UY4Cd0yt7yAbsYHr+KsLUan3dJSv80hhEPRmoy+8nO4=";
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
