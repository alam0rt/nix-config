# Security Audit Report — nix-config

Generated: 2026-03-29

---

## Summary

| Severity | Count | Fixed |
|----------|-------|-------|
| Critical | 3     | 3     |
| High     | 2     | 2     |
| Medium   | 7     | 2     |

The overall architecture is solid: Tailscale VPN gates most internal services, agenix-rekey with YubiKey FIDO2 manages secrets, SSH is key-only with no root login, and service accounts are isolated. The issues below are mostly around services binding to `0.0.0.0` or missing authentication where it should be present.

---

## Critical

### C1 — Syncthing GUI bound to all interfaces ✓ FIXED
**File:** `nixos/sauron/syncthing/default.nix:17`

Changed `guiAddress` from `http://0.0.0.0:8384` to `http://127.0.0.1:8384`. Nginx already proxied from loopback so behaviour is unchanged.

---

### C2 — Transmission RPC unauthenticated and bound to all interfaces ✓ FIXED
**File:** `nixos/sauron/transmission/default.nix`

Changed `rpc-bind-address` to `127.0.0.1` and enabled `rpc-authentication-required = true`. Credentials were already managed via agenix (`credentials.age`). Removed the now-redundant `rpc-whitelist`.

**Note:** Sonarr/Radarr/etc. must be configured with the Transmission credentials from the agenix secret, or they will fail to connect.

---

### C3 — Wyoming Whisper (speech-to-text) bound to all interfaces ✓ FIXED
**File:** `nixos/sauron/models/default.nix:51`

Changed `uri` from `tcp://0.0.0.0:10300` to `tcp://127.0.0.1:10300`. Home Assistant runs on the same host so Wyoming communication stays local.

---

## High

### H1 — MQTT broker allows anonymous connections ✓ FIXED
**File:** `nixos/sauron/home-assistant/default.nix`

Bound Mosquitto listener to `127.0.0.1` and removed the firewall rule for port 1883. Home Assistant and Mosquitto are co-located so all communication stays local. `allow_anonymous` left as-is since it's now only reachable from localhost.

**Note:** If any IoT devices connect to MQTT directly (rather than via ESPHome native API), they will stop working after deploy and will need to be migrated to the native API, or MQTT credentials added via agenix and the listener re-exposed on the Tailscale interface.

---

### H2 — OpenClaw unrestricted Matrix access ✓ FIXED (partially)
**File:** `nixos/sauron/openclaw/default.nix`

Restricted `dm.allowFrom` and `groupAllowFrom` to `["@sammm:chat.samlockart.com"]` and enabled `requireMention = true`. The bot now only responds to DMs and group mentions from the owner.

`dangerouslyDisableDeviceAuth = true` was left in place — the inline comment explains it is required by the `trusted-proxy` auth mode (Tailscale injects `x-webauth-user` to satisfy the device identity check; removing the flag would cause code=4008 errors on the Control UI). The effective auth boundary is Tailscale VPN membership.

---

## Medium

### M1 — NFS `insecure` export option
**File:** `nixos/sauron/nas/default.nix`

The `insecure` NFS export option permits clients to use unprivileged ports (>1024), bypassing the traditional root-only port restriction that provides weak client authentication.

**Fix:** Remove the `insecure` option; ensure all NFS clients use privileged ports or switch to `sec=krb5`.

---

### M2 — Samba guest access on shares
**File:** `nixos/sauron/nas/default.nix:67-72`

Downloads and media shares allow guest (unauthenticated) access, relying solely on `hosts allow` (LAN + Tailscale CGNAT) for isolation. A compromised device on the network gets full read/write without credentials.

**Fix:** Require authentication for all shares, or at minimum limit guest shares to read-only.

---

### M3 — Known-insecure packages explicitly permitted ✓ PARTIALLY FIXED
**File:** `nixos/sauron/configuration.nix`
```nix
dotnet-sdk-6.0.428       # EOL — Jackett
aspnetcore-runtime-6.0.36 # EOL — Jackett
olm-3.2.16               # vulnerable — Maubot
openssl-1.1.1w           # EOL — Home Assistant
```
These are acknowledged end-of-life/vulnerable packages. They expand the attack surface for services exposed to the internet (Matrix, Home Assistant).

Verified against the running system: `dotnet-sdk-6`, `aspnetcore-runtime-6`, and `openssl-1.1.1w` are no longer present in the system closure — nixpkgs has updated Jackett and Home Assistant to use newer runtimes. Those three entries have been removed. `olm-3.2.16` remains, still required by maubot → mautrix → python-olm.

---

### M4 — Multiple `openFirewall = true` services bypass nginx
Services including Jellyfin, Lidarr, Radarr, Sonarr, Jackett, Bazarr, Jellyseerr, OpenWebUI, Mumble, Unifi, and Home Assistant all open ports directly in addition to being proxied via nginx. Direct ports skip nginx-level auth, rate limiting, and security headers.

**Fix:** Where a service is only meant to be accessed via the nginx reverse proxy, remove `openFirewall = true` and rely on `127.0.0.1`/`localhost` binding.

---

### M5 — Container image policy set to `insecureAcceptAnything`
**File:** `home-manager/common.nix:286-291`
```nix
default = [{type = "insecureAcceptAnything";}];
```
The containers/policy.json config disables all image signature verification for Podman. Unsigned or tampered images will be pulled without warning.

**Fix:** Use `type = "reject"` as default and explicitly whitelist trusted registries with appropriate signature policies.

---

### M6 — OpenClaw unrestricted Matrix access
**File:** `nixos/sauron/openclaw/default.nix`
```nix
allowFrom = ["*"];         # DMs from anyone
groupAllowFrom = ["*"];    # group rooms unrestricted
requireMention = false;    # responds to all group messages
elevatedDefault = "full";  # full privileges by default
```
Any Matrix user (federated or local) can DM the bot or trigger it in shared rooms. With full elevated privileges as default, this is a significant blast radius.

**Fix:** Restrict `allowFrom` and `groupAllowFrom` to specific trusted Matrix IDs/rooms. Enable `requireMention`. Consider lowering `elevatedDefault`.

---

### M7 — Public internet services need rate limiting review ✓ FIXED
The following services are directly internet-accessible and should be audited for rate limiting and brute-force protection:

| Service | Domain |
|---------|--------|
| Vaultwarden | `pass.iced.cool` |
| Jellyfin | `tv.samlockart.com` |
| Jellyseerr | `requests.iced.cool` |
| Matrix (Synapse) | `iced.cool`, `x.iced.cool` |
| Mumble | `murmur.samlockart.com:64738` |
| Library (file listing) | `library.iced.cool` |

Added a `limit_req_zone login` (5r/m, burst=3) in `commonHttpConfig` and applied it to auth endpoints on each public service:
- Vaultwarden: `~/identity/connect/token` and `~/api/accounts/(login|prelogin|two-factor)`
- Jellyfin: `~* /Users/AuthenticateByName`
- Jellyseerr: `/api/v1/auth/local`

Matrix/Synapse skipped — it has built-in `rc_login` rate limiting.

---

## Informational

- **SSH hardening is good:** Key-only auth, no root login, `PubkeyAuthOptions verify-required` on sauron.
- **Agenix-rekey with 3 YubiKeys** is a strong secrets management approach. Ensure all three keys are stored in separate physical locations.
- **Tailscale correctly gates** internal tools (Transmission, Sonarr/Radarr/etc., Grafana, OpenWebUI, Maubot).
- **`sam` is in `docker`/`wireshark`/`dialout` groups** — expected for a dev workstation, but these groups allow container escapes and packet capture if the user account is compromised.
- **Systemd hardening on OpenClaw** is well-configured (ProtectSystem, NoNewPrivileges, capability bounding, namespace restrictions).
- **Borg backups** are encrypted (Blake2 + repokey) and managed via agenix.
