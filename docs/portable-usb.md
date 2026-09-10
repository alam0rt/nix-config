# Portable USB (the `portable` host)

A live NixOS image carrying the same desktop as `laptop`/`desktop` - niri,
greetd, pipewire, the home-manager config for `sam` - with no hardware
assumptions, so it boots whatever machine you push it into.

It is deliberately **stateless**. Nothing you do on the stick survives a
reboot, and nothing sensitive sits on it unencrypted. What the stick needs to
know about the world - wifi PSKs, a tailscale key, an ssh key - rides along as
ciphertext that only a YubiKey can open, and anything you want to *keep* goes
to NFS on sauron, mounted by hand.

## Build and write

```bash
nix build .#portable-iso                 # or: make iso
sudo dd if=result/iso/nixos-portable.iso of=/dev/sdX bs=4M status=progress conv=fsync
```

`/dev/sdX` is the whole disk, not a partition. The image is a hybrid ISO, so
it boots under both UEFI and legacy BIOS and needs no partitioning.

## Secrets

Every `*.age` file in `nixos/portable/secrets/` is baked into the image at
`/etc/portable/secrets/`, encrypted to the three YubiKey FIDO2-HMAC master
identities in `nixos/config/secrets/pubkeys/`. A lost stick is a lost pile of
ciphertext.

On the running system:

```bash
sudo portable-unlock          # touch the key once
```

That decrypts into tmpfs (`/run/portable-secrets`) and installs what it
recognises from the `state.tar` bundle: wifi connections into NetworkManager,
ssh keys into `~sam/.ssh`, and `tailscale up` with the bundled auth key.
Anything else is left decrypted under `/run/portable-secrets` for you to use.
The greetd login screen carries a reminder that the command exists.

Build the bundle from a staging directory:

```bash
scripts/portable-pack-state.sh ~/portable-state   # -> nixos/portable/secrets/state.tar.age
git add nixos/portable/secrets/state.tar.age      # flakes only see tracked files
nix build .#portable-iso
```

Encrypting is public-key only, so *building* an image never needs a YubiKey -
only using one does. See `nixos/portable/secrets/README.md` for the bundle
layout and where to get each piece.

This intentionally sidesteps agenix. agenix-rekey re-encrypts secrets to a
host key, and this host's key would have to live unencrypted on the same
stick, which would defeat the point; `portable` is therefore not registered
with agenix-rekey in `flake.nix` and ships master-encrypted files instead.

## State

There is nowhere on the stick to put it. The NFS shares from
`nfs_mounts.nix` are `noauto` here - no automount, since the stick is usually
nowhere near home - so mounting is deliberate:

```bash
sudo mount /mnt/share/sam
```

## What you get

- Log in as `sam` at the greetd prompt with your normal password
  (`initialHashedPassword` from `nixos/config/common/users.nix`), landing in
  niri with the full home-manager environment.
- `root` and `sam` are the only accounts. This is not the nixpkgs installer
  profile - no passwordless `nixos` user, no bundled channel - it is our own
  system with `installer/cd-dvd/iso-image.nix` bolted on.
- Wifi via NetworkManager (`nmtui`), either typed in or restored by
  `portable-unlock`.

## What you don't

The store on the stick is a read-only squashfs with a tmpfs overlay, so every
boot starts from the image:

- `nixos-rebuild switch` cannot work. Change the config, rebuild the ISO,
  rewrite the stick.
- `/home/sam`, ssh host keys, browser profiles and `/var/lib/tailscale` are
  gone at poweroff. `portable-unlock` is how you get back to a working
  network and identity, not a restore of your last session.
- The rootfs itself is not encrypted - it cannot be, it is the boot medium -
  but it holds nothing but public nixpkgs output. The only private material in
  the image is the `*.age` files.

## Size

Steam is disabled here (`programs.steam.enable = lib.mkForce false`) - several
GB of image for something you would not do off a live stick. To find the next
offender: `nix path-info -Sh .#portable-iso` and
`nix why-depends .#portable-iso <pkg>`.

## Files

- `nixos/portable/configuration.nix` - the generic host (no
  `hardware-configuration.nix`, no nvidia, all firmware, latest kernel)
- `nixos/portable/iso.nix` - the live-media layer
- `nixos/portable/secrets.nix` + `portable-unlock.sh` - the encrypted bundle
  and the unlock command
- `scripts/portable-pack-state.sh` - builds the bundle
- `flake.nix` - `nixosConfigurations.portable`, `packages.x86_64-linux.portable-iso`
