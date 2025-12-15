# agenix-rekey

This configuration uses [agenix-rekey](https://github.com/oddlama/agenix-rekey) for secrets management.

## Master Identities

Two YubiKey FIDO2-HMAC identities are configured as master identities:
- `yubikey-22916238.pub`
- `yubikey-15498888.pub`

## Commands

### Edit a secret

```bash
nix run '.#agenix-rekey.aarch64-darwin.edit-view' -- secrets/some-secret.age
# or on x86_64-linux:
nix run '.#agenix-rekey.x86_64-linux.edit-view' -- secrets/some-secret.age
```

### Rekey all secrets

After adding/modifying secrets or changing host keys, rekey for all hosts:

```bash
nix run '.#agenix-rekey.aarch64-darwin.rekey'
# or on x86_64-linux:
nix run '.#agenix-rekey.x86_64-linux.rekey'
```

This will re-encrypt secrets for each host's public key and store them in `secrets/rekeyed/<hostname>/`.

### Generate a new secret

```bash
nix run '.#agenix-rekey.aarch64-darwin.generate'
```

### Update master keys in existing secrets

If you add new master identities:

```bash
nix run '.#agenix-rekey.aarch64-darwin.update-masterkeys'
```

## Generate new YubiKey identity

```bash
age-plugin-fido2-hmac -g
```

Save the output to a new `yubikey-<serial>.pub` file.

## Decrypt manually with age

Requires `age` and `age-plugin-fido2-hmac` installed:

```bash
nix-shell -p age age-plugin-fido2-hmac
age -d -j fido2-hmac secrets/some-secret.age
```

## Storage Mode

Using `local` storage mode - rekeyed secrets are stored in git at `secrets/rekeyed/<hostname>/`.
