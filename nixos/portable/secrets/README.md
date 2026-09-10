# Portable secrets

Every `*.age` file in this directory is copied into the ISO at
`/etc/portable/secrets/` and decrypted on the running stick by
`sudo portable-unlock`.

They are encrypted directly to the three YubiKey master identities in
`nixos/config/secrets/pubkeys/`, *not* rekeyed to a host key - a host key for
this image would have to sit unencrypted on the same stick.

## The state bundle

`portable-unlock` gives `state.tar.age` special treatment: it extracts it and
installs what it recognises.

```
state.tar
├── NetworkManager/system-connections/*.nmconnection   -> /etc/NetworkManager/system-connections
├── ssh/*                                              -> /home/sam/.ssh
└── tailscale/authkey                                  -> tailscale up --auth-key
```

Build it from a staging directory of that shape:

```bash
scripts/portable-pack-state.sh ~/portable-state
```

Encryption is public-key only, so packing needs no YubiKey - only unlocking
does. One touch opens the whole bundle.

`git add` the result before building: a flake in a git repo only sees tracked
files, so an uncommitted bundle is silently absent from the image. The
`.gitignore` here lets `*.age` through and blocks everything else, so a
staged plaintext `state.tar` cannot be committed by accident.

Any other `*.age` file here is simply decrypted to `/run/portable-secrets/`
under its own name, for you to use by hand. That costs one touch per file.

## Where to get the pieces

- wifi: `sudo cp /etc/NetworkManager/system-connections/*.nmconnection ~/portable-state/NetworkManager/system-connections/`
  from a host that already knows the networks (they contain the PSKs, hence
  the encryption).
- tailscale: a fresh, ideally short-lived, pre-authorised key from
  <https://hs.samlockart.com>. Single-use keys are spent on first boot.
- ssh: whichever key you want the stick to authenticate with. The sk-backed
  keys in `nixos/config/common/users.nix` need the YubiKey anyway, so a
  `*_sk` key here is a stub the token still has to sign for.
