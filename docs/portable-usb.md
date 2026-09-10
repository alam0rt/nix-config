# Portable USB (the `portable` host)

A live NixOS image that carries the same desktop as `laptop`/`desktop` - niri,
greetd, pipewire, the home-manager config for `sam`, tailscale, the NFS
automounts - but with no hardware assumptions, so it boots on whatever machine
you push it into.

## Build and write

```bash
nix build .#portable-iso                 # or: make iso  (offloads to sauron)
sudo dd if=result/iso/nixos-portable.iso of=/dev/sdX bs=4M status=progress conv=fsync
```

`/dev/sdX` is the whole disk, not a partition. The image is a hybrid ISO, so
it boots on both UEFI and legacy BIOS, and needs no partitioning of the stick.

## What you get

- Log in as `sam` at the greetd prompt with your normal password
  (`initialHashedPassword` from `nixos/config/common/users.nix`), which lands
  you in niri via uwsm, with the full home-manager environment.
- `root` and `sam` are the only accounts; there is no passwordless `nixos`
  installer user, because this is not the nixpkgs installer profile - it is
  our own system with `installer/cd-dvd/iso-image.nix` bolted on.
- Wifi via NetworkManager (`nmtui`, or the applet); `sam` is in the
  `networkmanager` group.

## What you do *not* get

Nothing persists. The Nix store on the stick is a read-only squashfs with a
tmpfs overlay, so every boot starts from the image:

- `nixos-rebuild switch` cannot work. Change the config, rebuild the ISO,
  rewrite the stick.
- Wifi passwords, SSH host keys, browser profiles and `/home/sam` are gone at
  poweroff.
- Tailscale needs `tailscale up` (against `hs.samlockart.com`) on every boot;
  its state lives in `/var/lib/tailscale`.
- No agenix secrets. `portable` has no host key and is not registered with
  `agenix-rekey` in `flake.nix`; nothing in its module set asks for a secret.

If any of that becomes annoying, the next step is either a persistent
partition mounted over `/home`, or a real install on the stick built with the
`image.repart` module - both are bigger changes than this.

## Size

The closure is desktop-sized. Steam alone is several GB; set
`programs.steam.enable = false` in `nixos/portable/configuration.nix` if the
image needs to fit a smaller stick.

## Files

- `nixos/portable/configuration.nix` - the generic host (no
  `hardware-configuration.nix`, no nvidia, all firmware, latest kernel)
- `nixos/portable/iso.nix` - the live-media layer (iso-image.nix, bootloader
  overrides, volume ID)
- `flake.nix` - `nixosConfigurations.portable` and `packages.x86_64-linux.portable-iso`
