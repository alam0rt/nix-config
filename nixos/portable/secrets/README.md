# Portable secrets

Every `*.age` file here is copied into the ISO at `/etc/portable/secrets/` and
decrypted on demand into `/run/portable-secrets`, which is an automount: any
access asks for a YubiKey touch. One touch decrypts the whole directory. See
`docs/portable-usb.md`.

They are encrypted directly to the three YubiKey master identities in
`nixos/config/secrets/pubkeys/`, *not* rekeyed to a host key - a host key for
this image would have to sit unencrypted on the same stick.

## Names carry meaning

| name | what the stick does with it |
| --- | --- |
| `nm-env.age` | environment file for the declarative wifi profiles; `WIFI_PSK_*=...` lines. Lives in `nixos/config/network/`, not here - laptop and desktop rekey from the same file - and is shipped into the image from there |
| `ssh-<file>.age` | installed as `/home/sam/.ssh/<file>` by `portable-restore.service` |
| `tailscale-authkey.age` | `services.tailscale.authKeyFile` reads it directly |
| anything else | decrypted under its own name, yours to use by hand |

Add one with:

```bash
scripts/portable-secret.sh <name> [file]     # reads stdin if no file
git add nixos/portable/secrets/<name>.age    # a flake only sees tracked files
```

Encryption is public-key only, so this needs no token - only the stick does.
The `.gitignore` here lets `*.age` through and blocks everything else, so a
staged plaintext cannot be committed by accident.

## Reusing a secret that already exists

Everything under `nixos/sauron/**.age` is already encrypted to these same
three YubiKeys, so baking one in is a copy - no decryption, no token:

```bash
cp nixos/sauron/tailscale/authkey.age nixos/portable/secrets/tailscale-authkey.age
```

Check the key is still live first; sauron's may be spent or expired.

## Where to get the pieces

- **wifi**:

  ```bash
  sudo scripts/portable-wifi-psks.sh | scripts/portable-secret.sh nm-env - nixos/config/network
  nix run '.#agenix-rekey.x86_64-linux.rekey'   # so laptop/desktop get it too
  ```

  reads the PSKs out of this laptop's own NetworkManager profiles and pipes
  them straight into the encryptor, so the plaintext never hits disk. The
  SSIDs themselves live in `nixos/config/network/wifi.nix` in the clear.
- **ssh**: the `sk-` keys are stubs - the private half lives on the YubiKey and
  every use needs a touch - which is why those are the ones to carry.
- **tailscale**: a fresh, short-lived pre-authorised key from
  <https://hs.samlockart.com>. Single-use keys are spent on first boot.
