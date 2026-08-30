# BLE presence proxies

Three ESP32-WROOM-32 nodes running ESPHome as Bluetooth proxies. Home Assistant
sees every BLE advertisement they hear; the `bermuda` custom component
(packaged in `pkgs/bermuda`) turns "which proxy heard it loudest" into
room-level presence.

`common.yaml` holds everything shared. Each `proxy-<room>.yaml` is just a name
and a `!include`.

## First flash (USB)

Only the first flash needs a cable; after that it is OTA over Wi-Fi.

```bash
nix develop                     # brings esphome onto PATH
$EDITOR esphome/secrets.yaml    # set wifi_password
esphome run esphome/proxy-lounge.yaml
```

Pick the serial port when prompted. On the WROOM-32 you may need to hold the
BOOT button as flashing begins.

## Later changes (OTA)

```bash
esphome run esphome/proxy-lounge.yaml   # auto-detects the node over the network
esphome logs esphome/proxy-lounge.yaml
```

## Adding a node

Copy any `proxy-<room>.yaml`, change the two substitutions. Nothing else.

## Renaming

`node_name` becomes the mDNS hostname and the ESPHome device ID, so changing it
after adoption makes HA see a *new* device. Settle on names before flashing.

## Notes on the WROOM-32

Wi-Fi and BLE share one radio on this chip, so these nodes are deliberately
dedicated to proxying — resist adding sensors to them. `power_save_mode: none`
and continuous scanning (`interval == window`) are both there to stop the Wi-Fi
side stealing airtime from BLE.

Each proxy supports three simultaneous BLE *connections*, but passive
advertisement listening — which is all Bermuda needs — is unlimited.

## Placement

Bermuda resolves to whichever proxy hears a device loudest, so one node per room
you care about beats three nodes in a line. Mains-powered, out in the open;
avoid inside metal enclosures, behind TVs, or right next to an AP.

## Tracking phones

iOS and Android rotate their BLE MAC every ~15 minutes, so a phone will appear
as an endless stream of one-off devices. The fix is the `private_ble_device`
integration (already enabled): give it the phone's **IRK** and HA resolves every
rotation back to one device.

Getting an IRK:

- **iOS** — pair the phone to HA over Bluetooth, or read it out of a paired
  Mac's keychain.
- **Android** — `/data/misc/bluedroid/bt_config.conf` (root required).

If that is more trouble than it is worth, a cheap BLE keyfob beacon broadcasts a
fixed address and needs no IRK at all.

Expect to calibrate: Bermuda's defaults for reference power and path loss are a
starting point, not a truth, and differ per device model.
