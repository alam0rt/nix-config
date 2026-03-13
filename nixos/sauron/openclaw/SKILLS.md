# OpenClaw Gateway — Sauron Admin Notes

## Running CLI commands against the gateway

The `openclaw` user runs the gateway. Since the gateway binds to the tailnet IP
(`100.64.0.4:18789`), the CLI can't auto-discover it on loopback. Use the
wrapper below to run any `openclaw` subcommand as the `openclaw` user:

```bash
sudo -u openclaw \
  OPENCLAW_STATE_DIR=/var/lib/openclaw \
  OPENCLAW_CONFIG_PATH=/var/lib/openclaw/openclaw.json \
  $(cat /proc/$(pgrep -f 'openclaw gateway')/cmdline | tr '\0' ' ' | awk '{print $1}' | sed 's|/bin/openclaw.*|/bin/openclaw|') \
  <subcommand>
```

Or use the symlink in the current system profile:

```bash
sudo -u openclaw \
  OPENCLAW_STATE_DIR=/var/lib/openclaw \
  OPENCLAW_CONFIG_PATH=/var/lib/openclaw/openclaw.json \
  /run/current-system/sw/bin/openclaw <subcommand>
```

### Useful commands

```bash
# Gateway + channel status
sudo -u openclaw OPENCLAW_STATE_DIR=/var/lib/openclaw OPENCLAW_CONFIG_PATH=/var/lib/openclaw/openclaw.json /run/current-system/sw/bin/openclaw status

# List paired devices
sudo -u openclaw OPENCLAW_STATE_DIR=/var/lib/openclaw OPENCLAW_CONFIG_PATH=/var/lib/openclaw/openclaw.json /run/current-system/sw/bin/openclaw devices list

# Approve latest pending device pairing
sudo -u openclaw OPENCLAW_STATE_DIR=/var/lib/openclaw OPENCLAW_CONFIG_PATH=/var/lib/openclaw/openclaw.json /run/current-system/sw/bin/openclaw devices approve --latest

# Show gateway token
sudo -u openclaw OPENCLAW_STATE_DIR=/var/lib/openclaw OPENCLAW_CONFIG_PATH=/var/lib/openclaw/openclaw.json /run/current-system/sw/bin/openclaw devices token

# View live logs
journalctl -u openclaw-gateway.service -f
```

## Connecting from a remote machine (tailnet)

The gateway listens on `ws://100.64.0.4:18789` (plain WS, tailnet-only).

On your laptop (connected to tailnet), set in `~/.openclaw/openclaw.json`:

```json
{
  "gateway": {
    "mode": "remote",
    "remote": {
      "url": "ws://sauron.middleearth.samlockart.com:18789",
      "transport": "direct",
      "token": "<your-device-token-from-devices-token>"
    }
  }
}
```

And set env vars:

```bash
export OPENCLAW_ALLOW_INSECURE_PRIVATE_WS=1
```

Then run `openclaw` via the flake:

```bash
nix shell --impure github:openclaw/nix-openclaw#openclaw
```
