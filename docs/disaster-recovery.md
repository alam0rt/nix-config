# Disaster Recovery Plan

**Last updated:** 2026-03-31

---

## Table of Contents

1. [Infrastructure Overview](#1-infrastructure-overview)
2. [What Is Backed Up (and What Isn't)](#2-what-is-backed-up-and-what-isnt)
3. [Recovery Prerequisites](#3-recovery-prerequisites)
4. [Scenario A: Full Server Loss (sauron)](#4-scenario-a-full-server-loss)
5. [Scenario B: ZFS Pool Loss (mordor)](#5-scenario-b-zfs-pool-loss)
6. [Scenario C: Root NVMe Failure](#6-scenario-c-root-nvme-failure)
7. [Scenario D: Individual Service Recovery](#7-scenario-d-individual-service-recovery)
8. [Scenario E: YubiKey Loss](#8-scenario-e-yubikey-loss)
9. [Scenario F: rsync.net Account Compromise or Loss](#9-scenario-f-rsyncnet-account-compromise-or-loss)
10. [Borg Operations Reference](#10-borg-operations-reference)
11. [Gaps and Recommendations](#11-gaps-and-recommendations)

---

## 1. Infrastructure Overview

### Hosts

| Host | Role | Storage |
|------|------|---------|
| **sauron** | Primary server, runs all services | NVMe root (ext4, 234G) + ZFS pool `mordor` (raidz2, ~29T raw) |
| **desktop** | Workstation | Local disk, Syncthing to `/home/sam/vault` |
| **laptop** | Workstation | Local disk, Syncthing to `/home/sam/vault` |

### ZFS Pool: `mordor`

Two raidz2 vdevs (8+4 disks). Can survive 2 disk failures per vdev.

| Dataset | Mount | Quota | Used | Backed Up |
|---------|-------|-------|------|-----------|
| `mordor/data` | `/srv/data` | 60G | 26.5G | Hourly (Borg) |
| `mordor/vault` | `/srv/vault` | 5G | 17.6M | Daily (Borg) + Syncthing |
| `mordor/share/sam` | `/srv/share/sam` | 750G | 640G | Daily (Borg) |
| `mordor/share/emma` | `/srv/share/emma` | 200G | 123G | Daily (Borg) |
| `mordor/share/public` | `/srv/share/public` | 1.2T | 1.18T | **NOT BACKED UP** |
| `mordor/media` | `/srv/media` | ~21.6T | 21.6T | **NOT BACKED UP** |

### Root NVMe (ext4, `/dev/nvme0n1p2`)

234G total, 180G used (82%). Contains:

- `/var/lib/postgresql/16/` — **Matrix Synapse database (NOT BACKED UP)**
- `/var/lib/hass/` — **Home Assistant state (NOT BACKED UP)**
- `/var/lib/matrix-synapse/` — Synapse signing keys
- `/var/lib/acme/` — TLS certificates (auto-renewable)
- `/var/lib/containers/` — Podman container storage
- `/var/lib/grafana/`, `/var/lib/prometheus2/` — Monitoring data (rebuildable)

### Offsite Backups: rsync.net

- Account: `hk1068@hk1068.rsync.net`
- Tool: Borg (repokey-blake2 encryption, zstd compression)
- Remote borg version: `borg14`

### Secrets: agenix-rekey with 3 YubiKeys

- Serial `22916238`, `15498888`, `18103415`
- Any **one** YubiKey can decrypt all secrets
- 14 encrypted secrets for sauron (borg keys, API tokens, SMTP, Tailscale, etc.)

---

## 2. What Is Backed Up (and What Isn't)

### Borg Backup Jobs (rsync.net)

| Job | Source | Schedule | Repo Path |
|-----|--------|----------|-----------|
| `mordor-vault` | `/srv/vault` | Daily | `mordor/vault` |
| `mordor-srv-data` | `/srv/data` | Hourly | `mordor/srv/data` |
| `mordor-share-sam` | `/srv/share/sam` | Daily | `mordor/share/sam` |
| `mordor-share-emma` | `/srv/share/emma` | Daily | `mordor/share/emma` |

**Exclusions from `mordor-srv-data`:** `*.db-wal`, `*.db-shm` (SQLite temp files).

**No retention/prune policy is configured** — archives accumulate indefinitely on rsync.net.

### ZFS Auto-Snapshots (local only)

247 snapshots across all datasets. Frequencies: frequent (15m), hourly, daily, weekly, monthly.

### NOT Backed Up

| Data | Location | Risk |
|------|----------|------|
| **PostgreSQL (Matrix Synapse)** | `/var/lib/postgresql/16/` (root NVMe) | Low (not actively used yet) |
| **Home Assistant** | `/var/lib/hass/` (root NVMe) | Low (not actively used yet) |
| **Media files** | `/srv/media` (21.6T) | Low — re-downloadable, but time-consuming |
| **Public share** | `/srv/share/public` (1.18T) | Low — AI models re-downloadable, containers rebuildable |
| **Prometheus metrics** | `/var/lib/prometheus2/` (root NVMe) | Low — 30-day retention, informational only |
| **Grafana state** | `/var/lib/grafana/` (root NVMe) | Low — dashboards are declarative in Nix |
| **TLS certificates** | `/var/lib/acme/` (root NVMe) | None — auto-renewed by ACME |

### Also Protected (non-backup)

- **`/srv/vault`** is replicated via Syncthing to desktop and laptop
- **All Nix config** is in this git repo (the source of truth for rebuilding)
- **All secrets** are encrypted in git under `nixos/config/secrets/rekeyed/`

---

## 3. Recovery Prerequisites

### You Will Need

1. **At least one YubiKey** (serials: 22916238, 15498888, or 18103415)
2. **A machine with:**
   - `nix` installed (or a NixOS installer USB)
   - `age` and `age-plugin-fido2-hmac` (for manual secret decryption)
   - `git` to clone this repo
3. **Network access** to `hk1068.rsync.net` (for Borg restores)
4. **SSH access** — your `~/.ssh/id_rsa` must be authorized on rsync.net, OR you must decrypt the `borg-ssh` key from agenix

### Decrypting a Secret Manually

```bash
nix-shell -p age age-plugin-fido2-hmac
age -d -j fido2-hmac nixos/config/secrets/rekeyed/sauron/<secret>.age
# Tap YubiKey when prompted
```

### Getting Borg Access Without a Running sauron

The `scripts/borg.sh` wrapper works from any machine with agenix available:

```bash
nix develop  # enter dev shell with agenix-rekey
./scripts/borg.sh mordor/srv/data list --last 5
```

If that doesn't work (e.g. fresh machine), decrypt the borg passphrase and SSH key manually:

```bash
# Decrypt borg passphrase
age -d -j fido2-hmac nixos/sauron/borg/borg.age > /tmp/borg-pass

# Decrypt borg SSH key
age -d -j fido2-hmac nixos/sauron/borg/borg-ssh.age > /tmp/borg-ssh
chmod 600 /tmp/borg-ssh

# Use borg directly
export BORG_PASSCOMMAND="cat /tmp/borg-pass"
export BORG_RSH="ssh -i /tmp/borg-ssh"
borg --remote-path borg14 list hk1068@hk1068.rsync.net:mordor/srv/data
```

**Clean up `/tmp/borg-pass` and `/tmp/borg-ssh` immediately after use.**

---

## 4. Scenario A: Full Server Loss

Total loss of sauron hardware. Starting from bare metal.

### Step 1: Install NixOS

1. Boot NixOS installer USB
2. Partition disks:
   - NVMe: GPT with 512M EFI (`/boot`) + ext4 root + 32G swapfile
   - HDD array: Create ZFS pool `mordor` with two raidz2 vdevs matching the original layout
   - Set `networking.hostId = "acfb04f9"` (required for ZFS import)
3. Create ZFS datasets:
   ```bash
   zfs create -o compression=zstd -o quota=60G mordor/data
   zfs create -o compression=lz4 mordor/vault
   zfs create -o compression=zstd mordor/share
   zfs create -o compression=zstd -o quota=750G mordor/share/sam
   zfs create -o compression=zstd -o quota=200G mordor/share/emma
   zfs create -o compression=zstd mordor/share/public
   zfs create -o compression=lz4 -o recordsize=1M mordor/media
   ```
4. Mount datasets to `/srv/*` as per `hardware-configuration.nix`

### Step 2: Deploy NixOS Config

```bash
git clone <this-repo> /etc/nixos  # or wherever you work from
nixos-install --flake .#sauron
```

This will fail to start services that need secrets/data, which is expected.

### Step 3: Restore Secrets

The agenix-rekey secrets are already in the git repo (encrypted). After `nixos-install`, the system will have its SSH host key. You need to:

1. **Rekey secrets for the new host key** (if the host SSH key changed):
   - Update the host pubkey in `nixos/sauron/configuration.nix`
   - Run `nix run '.#agenix-rekey.x86_64-linux.rekey'` (needs YubiKey)
   - Rebuild: `nixos-rebuild switch --flake .#sauron`

2. **Or preserve the original host key** by restoring `/etc/ssh/ssh_host_*` from a backup (if you have one — see [Gap G1](#11-gaps-and-recommendations)).

### Step 4: Restore Data from Borg

```bash
# Set up borg environment (secrets should be in /run/agenix/ after rebuild)
export BORG_PASSCOMMAND='cat /run/agenix/borg'
export BORG_RSH='ssh -i /run/agenix/borg-ssh'
export BORG_REMOTE_PATH=borg14

# List available archives
borg list hk1068@hk1068.rsync.net:mordor/srv/data

# Restore /srv/data (most critical — all service databases)
cd /
borg extract hk1068@hk1068.rsync.net:mordor/srv/data::ARCHIVE_NAME

# Restore /srv/vault
borg extract hk1068@hk1068.rsync.net:mordor/vault::ARCHIVE_NAME

# Restore user shares
borg extract hk1068@hk1068.rsync.net:mordor/share/sam::ARCHIVE_NAME
borg extract hk1068@hk1068.rsync.net:mordor/share/emma::ARCHIVE_NAME
```

Replace `ARCHIVE_NAME` with the latest archive from `borg list`.

### Step 5: Restore PostgreSQL (Matrix Synapse)

PostgreSQL data is on the root NVMe and is NOT in any Borg job. If the NVMe is recoverable, copy `/var/lib/postgresql/16/` from it. Otherwise, Matrix Synapse data is lost. **Currently low impact — Matrix is not actively used.** See [Gap G2](#11-gaps-and-recommendations) for when this needs addressing.

### Step 6: Fix Ownership and Restart Services

```bash
# Fix service directory ownership (borg restores as root)
chown -R jellyfin:jellyfin /srv/data/jellyfin
chown -R sonarr:sonarr /srv/data/sonarr
chown -R radarr:radarr /srv/data/radarr
chown -R lidarr:lidarr /srv/data/lidarr
chown -R jackett:jackett /srv/data/jackett
chown -R transmission:transmission /srv/data/transmission
chown -R syncthing:syncthing /srv/data/syncthing
chown -R vaultwarden:vaultwarden /srv/data/vaultwarden
chown -R maubot:maubot /srv/data/maubot

# Rebuild and restart everything
nixos-rebuild switch --flake .#sauron
```

### Step 7: Post-Recovery Verification

- [ ] Vaultwarden accessible at `pass.iced.cool`
- [ ] Jellyfin serving media at `tv.iced.cool`
- [ ] Matrix Synapse federating (check `/_matrix/federation/v1/version`)
- [ ] Borg backup timers active: `systemctl list-timers 'borgbackup-*'`
- [ ] Syncthing connected to desktop/laptop
- [ ] Tailscale connected
- [ ] ACME certificates renewed
- [ ] Monitoring dashboards loading at `grafana.iced.cool`

---

## 5. Scenario B: ZFS Pool Loss

`mordor` pool is degraded or destroyed, but root NVMe is fine.

### If Degraded (1-2 disk failures per vdev)

```bash
# Check status
zpool status mordor

# Replace failed disk
zpool replace mordor <old-disk-wwn> <new-disk-wwn>

# Wait for resilver to complete
zpool status mordor  # watch resilver progress
```

raidz2 tolerates 2 failures per vdev. You have time but should replace promptly. The ZFS scrub runs automatically; the last scrub completed `2026-03-01` with 0 errors.

**Note:** `zpool status` currently shows a historical unrecoverable error on one disk in `raidz2-1` (`wwn-0x5000cca05c76cbd8` has 4 write errors). Monitor this disk — it may need replacement.

### If Pool Is Lost

Follow [Scenario A](#4-scenario-a-full-server-loss) steps 4-7, but skip NixOS installation since the root NVMe is intact. Recreate the ZFS pool and datasets, then restore from Borg.

---

## 6. Scenario C: Root NVMe Failure

The NVMe dies. ZFS pool `mordor` is fine.

### What's Lost

- PostgreSQL (Matrix Synapse) — **see [Gap G2](#11-gaps-and-recommendations)**
- Home Assistant state
- Boot loader, NixOS system
- Prometheus/Grafana data (rebuildable)
- ACME certificates (auto-renewable)

### Recovery

1. Install NixOS on a new NVMe (same partitioning)
2. Import the existing ZFS pool: `zpool import mordor`
3. `nixos-install --flake .#sauron`
4. Rekey secrets if host key changed (see Scenario A, Step 3)
5. Rebuild: `nixos-rebuild switch --flake .#sauron`
6. All `/srv/*` data is intact — services should start normally
7. Matrix Synapse will start with an empty database (low impact — not actively used yet)

---

## 7. Scenario D: Individual Service Recovery

### Restoring a Single Service from Borg

```bash
export BORG_PASSCOMMAND='cat /run/agenix/borg'
export BORG_RSH='ssh -i /run/agenix/borg-ssh'

# List archives
borg --remote-path borg14 list hk1068@hk1068.rsync.net:mordor/srv/data

# Stop the service
systemctl stop <service>

# Extract only that service's directory
cd /
borg --remote-path borg14 extract \
  hk1068@hk1068.rsync.net:mordor/srv/data::ARCHIVE_NAME \
  srv/data/<service>/

# Fix ownership
chown -R <service-user>:<service-group> /srv/data/<service>

# Restart
systemctl start <service>
```

### Service Data Locations Quick Reference

| Service | Data Path | User:Group | Notes |
|---------|-----------|------------|-------|
| Jellyfin | `/srv/data/jellyfin` | `jellyfin:jellyfin` | Library metadata, watch progress |
| Sonarr | `/srv/data/sonarr` | `sonarr:sonarr` | TV database, custom formats |
| Radarr | `/srv/data/radarr` | `radarr:radarr` | Movie database, custom formats |
| Lidarr | `/srv/data/lidarr` | `lidarr:lidarr` | Music database |
| Jackett | `/srv/data/jackett` | `jackett:jackett` | Indexer configs |
| Transmission | `/srv/data/transmission` | `transmission:transmission` | Torrent state |
| Syncthing | `/srv/data/syncthing` | `syncthing:syncthing` | Device keys, folder config |
| Vaultwarden | `/srv/data/vaultwarden` | `vaultwarden:vaultwarden` | Password vault (SQLite) |
| Maubot | `/srv/data/maubot` | `maubot:maubot` | Matrix bot DB and plugins |
| UniFi | `/srv/data/unifi` | `unifi:unifi` | Network controller state |

### Restoring from ZFS Snapshot (faster, local)

```bash
# List snapshots for a dataset
zfs list -t snapshot -o name,creation mordor/data | tail -20

# Restore a single file/directory from snapshot
cp -a /srv/data/.zfs/snapshot/zfs-auto-snap_hourly-2026-03-31-07h00/<service>/ \
      /srv/data/<service>.restored

# Or rollback the entire dataset (DESTRUCTIVE — loses all changes after snapshot)
# zfs rollback mordor/data@<snapshot-name>
```

### Vaultwarden (Password Vault) — Priority Recovery

If Vaultwarden is corrupted:

1. Stop service: `systemctl stop vaultwarden`
2. Restore from Borg (hourly backup, max 1 hour of data loss):
   ```bash
   cd /
   borg --remote-path borg14 extract \
     hk1068@hk1068.rsync.net:mordor/srv/data::LATEST \
     srv/data/vaultwarden/
   chown -R vaultwarden:vaultwarden /srv/data/vaultwarden
   ```
3. Restart: `systemctl start vaultwarden`

---

## 8. Scenario E: YubiKey Loss

### Lost 1 YubiKey (2 remain)

1. Remove the lost key's public key from `nixos/config/secrets/pubkeys/yubikey-<serial>.pub`
2. Run `nix run '.#agenix-rekey.x86_64-linux.update-masterkeys'` with a remaining YubiKey
3. Commit the change

No secrets are compromised — the lost YubiKey alone cannot decrypt anything without physical interaction (FIDO2-HMAC requires touch).

### Lost 2 YubiKeys (1 remains)

Same as above, but **urgently** provision a replacement:

```bash
# Generate new YubiKey identity
age-plugin-fido2-hmac -g
# Save output to nixos/config/secrets/pubkeys/yubikey-<new-serial>.pub

# Re-encrypt all secrets with new key set
nix run '.#agenix-rekey.x86_64-linux.update-masterkeys'
```

### Lost All 3 YubiKeys

**All agenix-encrypted secrets are permanently unrecoverable.** You must:

1. Generate new YubiKey identities on new keys
2. Manually recreate every secret:
   - Borg passphrase — **if lost, all Borg archives are permanently inaccessible** (repokey-blake2 requires the passphrase)
   - SSH keys for rsync.net — regenerate and re-authorize
   - All API tokens — regenerate from each service's UI
   - SMTP credentials — obtain from email provider
   - Tailscale auth key — regenerate from Tailscale admin
   - Cloudflare API token — regenerate from Cloudflare dashboard
3. Run `nix run '.#agenix-rekey.x86_64-linux.rekey'`
4. Rebuild all hosts

**This is a catastrophic scenario. Keep YubiKeys in separate physical locations.**

---

## 9. Scenario F: rsync.net Account Compromise or Loss

### Account Compromised

1. Change rsync.net password immediately
2. Rotate SSH authorized keys on rsync.net
3. Regenerate borg SSH keypair: `nix run '.#agenix-rekey.x86_64-linux.generate'`
4. Authorize new key: `agenix decrypt nixos/sauron/borg/borg-ssh-public.age | ssh hk1068@hk1068.rsync.net 'dd of=.ssh/authorized_keys'`
5. Borg data remains safe — encrypted with repokey-blake2 (attacker would need the passphrase)

### Account Lost / rsync.net Down

All offsite backups are unavailable. You still have:
- ZFS snapshots (local, on `mordor` pool)
- Syncthing replication of `/srv/vault` to desktop/laptop
- This git repo with all Nix config and encrypted secrets

**Provision a new offsite backup target urgently.**

---

## 10. Borg Operations Reference

### Environment Setup (on sauron)

```bash
export BORG_PASSCOMMAND='cat /run/agenix/borg'
export BORG_RSH='ssh -i /run/agenix/borg-ssh'
export BORG_REMOTE_PATH=borg14
```

### Common Commands

```bash
REPO=hk1068@hk1068.rsync.net

# List all archives in a repo
borg list $REPO:mordor/srv/data

# Show archive details
borg info $REPO:mordor/srv/data::ARCHIVE_NAME

# List files in an archive
borg list $REPO:mordor/srv/data::ARCHIVE_NAME | head -50

# Extract specific path from archive
cd /
borg extract $REPO:mordor/srv/data::ARCHIVE_NAME srv/data/jellyfin/

# Extract everything from an archive
cd /
borg extract $REPO:mordor/srv/data::ARCHIVE_NAME

# Dry-run extract (show what would be extracted)
borg extract --dry-run --list $REPO:mordor/srv/data::ARCHIVE_NAME
```

### From a Non-sauron Machine

Use `scripts/borg.sh`:
```bash
nix develop
./scripts/borg.sh mordor/srv/data list --last 5
./scripts/borg.sh mordor/vault list
```

---

## 11. Gaps and Recommendations

### G1: SSH Host Keys Not Backed Up

**Risk:** If sauron's NVMe dies, the SSH host key is lost. All agenix secrets must be rekeyed for the new host key. Clients will see SSH host key warnings.

**Recommendation:** Back up `/etc/ssh/ssh_host_*` to the Borg vault job or to `/srv/vault/` (which is already backed up). Example:

```bash
cp /etc/ssh/ssh_host_* /srv/vault/ssh-host-keys/
```

Or add a systemd service to copy them periodically.

### G2: PostgreSQL (Matrix Synapse) Not Backed Up

**Risk:** Matrix Synapse's PostgreSQL database lives on the root NVMe at `/var/lib/postgresql/16/`. It is not on ZFS and not in any Borg job. **Currently low priority — Matrix is not actively used yet.** When it becomes active, add a backup.

**Recommendation (when needed):** Add a `pg_dump` pre-backup hook or move the dataDir to ZFS:

```nix
# Option A: pg_dump to /srv/data (gets picked up by hourly Borg)
systemd.services.postgres-backup = {
  script = ''
    ${pkgs.postgresql}/bin/pg_dumpall -U postgres | ${pkgs.gzip}/bin/gzip > /srv/data/postgres-backup.sql.gz
  '';
  serviceConfig.User = "postgres";
  startAt = "hourly";
};

# Option B: Move PostgreSQL dataDir to ZFS
services.postgresql.dataDir = "/srv/data/postgresql/16";
```

### G3: Home Assistant State Not Backed Up

**Risk:** Home Assistant data at `/var/lib/hass/` is on the root NVMe. **Currently low priority — Home Assistant is not actively used yet.**

**Recommendation (when needed):** Either move `configDir` to `/srv/data/hass/` or add a backup job.

### G4: No Borg Prune/Retention Policy

**Risk:** Archives accumulate forever on rsync.net. Storage costs grow unbounded and `borg list` becomes slow.

**Recommendation:** Add prune settings to each Borg job:

```nix
prune.keep = {
  hourly = 48;
  daily = 30;
  weekly = 12;
  monthly = 12;
};
```

### G5: Media Files (21.6T) Not Backed Up

**Risk:** Low — media is re-downloadable. But re-downloading 21.6T takes significant time and the Sonarr/Radarr configurations to re-fetch would need to be set up.

**Recommendation:** Accept the risk. Media can be re-acquired. The *arr databases (which track what you have) are backed up hourly.

### G6: No Backup Monitoring/Alerting

**Risk:** If a Borg job silently fails, you won't know until you need to restore.

**Recommendation:** Add a Prometheus alert or simple check. Borg jobs are systemd services, so you could alert on `borgbackup-job-*.service` failures via the existing alertmanager setup.

### G7: No Documented Disk Serial Mapping

**Risk:** When a disk fails, you need to know which physical bay corresponds to which `wwn-*` identifier. The disk with write errors (`wwn-0x5000cca05c76cbd8`) may need proactive replacement.

**Recommendation:** Document the physical-to-WWN mapping. Run `lsblk -o NAME,WWN,SIZE,MODEL,SERIAL` and record it.

### G8: Root NVMe at 82% — Approaching Full

**Risk:** At 180G/234G, the root NVMe could fill up, which would crash services that write to `/var/lib/`.

**Recommendation:** Move PostgreSQL data to ZFS (fixes G2 and G8 simultaneously), or add monitoring alerts for root disk usage. The existing Prometheus node exporter + alertmanager can handle this.

### G9: `borg.sh` Uses `~/.ssh/id_rsa` Instead of agenix Key

**Risk:** The `scripts/borg.sh` wrapper hardcodes `BORG_RSH="ssh -i ${HOME}/.ssh/id_rsa"` which may not be authorized on rsync.net. It also uses `agenix -d` (old-style) rather than the rekey workflow.

**Recommendation:** Update `borg.sh` to use the agenix-rekey decrypt path, or document that your personal SSH key must be independently authorized on rsync.net for manual operations.

### G10: YubiKey Physical Location Not Documented

**Risk:** In a disaster, you need to locate a YubiKey quickly.

**Recommendation:** Record where each YubiKey is stored (e.g., "key 22916238: desk drawer", "key 15498888: fireproof safe", "key 18103415: offsite with family member"). Store this information somewhere you can access without needing the keys themselves.
