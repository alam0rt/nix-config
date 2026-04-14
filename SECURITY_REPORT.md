# Security Audit Report — nix-config

Generated: 2026-03-29

---

## Summary

| Severity | Count | Fixed/Resolved |
|----------|-------|----------------|
| Critical | 3     | 3              |
| High     | 2     | 2              |
| Medium   | 7     | 4 (M3 open, M4 open, M5 open) |

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

### H2 — OpenClaw unrestricted Matrix access ✓ RESOLVED (service removed)
**File:** `nixos/sauron/openclaw/default.nix` (deleted)

OpenClaw has been entirely removed from the configuration (commit `a6131e4`). The service, its secrets (`openclaw-config.age`, `openclaw-env.age`), and the `scripts/openclaw.sh` wrapper were all deleted. This finding is no longer applicable.

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

### M3 — Known-insecure packages explicitly permitted
**File:** `nixos/sauron/configuration.nix:164-172`
```nix
dotnet-sdk-6.0.428       # EOL — Jackett
aspnetcore-runtime-6.0.36 # EOL — Jackett
olm-3.2.16               # vulnerable — Maubot
openssl-1.1.1w           # EOL — Home Assistant
```
These are acknowledged end-of-life/vulnerable packages. They expand the attack surface for services exposed to the internet (Matrix, Home Assistant).

All four entries remain in `permittedInsecurePackages`. Consider switching Jackett to Prowlarr (modern .NET) and checking if newer maubot has dropped the olm dependency.

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

### M6 — OpenClaw unrestricted Matrix access ✓ RESOLVED (service removed)
**File:** `nixos/sauron/openclaw/default.nix` (deleted)

OpenClaw has been entirely removed from the configuration (commit `a6131e4`). This finding is no longer applicable.

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
- **Borg backups** are encrypted (Blake2 + repokey) and managed via agenix.

---

## 2026-04-14 CSO Audit Update

A follow-up security audit identified and fixed two HIGH findings:

- **Home Assistant port 8123 was directly exposed** on all interfaces without nginx or Tailscale auth. Fixed: removed firewall port, added nginx reverse proxy with Tailscale auth at `home-assistant.middleearth.samlockart.com`.
- **Flaresolverr container had `--network=host` and used `:latest` with `pull=always`**. A compromised image could reach every localhost-bound service. Fixed: pinned to `v3.3.21`, removed host networking, bound to `127.0.0.1:8191`.

Remaining MEDIUM findings from the 2026-04-14 audit (see `.gstack/security-reports/2026-04-14-131300.json`):
- Unpinned container images (rarbg, unifi) still use `:latest`
- Multiple services still have `openFirewall = true` (overlaps with M4 above)
- EOL insecure packages (overlaps with M3 above)
- `initialHashedPassword` for sam user committed to public repo
