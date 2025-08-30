# agenix

### Generate new key using yubikey FIDO2

```bash
age-plugin-fido2-hmac -g
```

### Rekey (after setting up identity)

```bash
agenix -r
```

### Decrypt using just age (and plugin)

Requires `age` and `age-plugin-fido2-hmac` installed.

```bash
nix-shell -p age age-plugin-fido2-hmac
age -d -j fido2-hmac ...
```
