# Borg Backup

## SSH Key Management

SSH keys for borg are managed via agenix-rekey generators:

- `borg-ssh`: Private key (generated via `ssh-ed25519` generator)
- `borg-ssh-public`: Public key (derived from private key)

After generating new keys with `agenix generate`, authorize them on rsync.net:

```bash
nix develop
agenix decrypt nixos/sauron/borg/borg-ssh-public.age | ssh hk1068@hk1068.rsync.net 'dd of=.ssh/authorized_keys oflag=append conv=notrunc'
```

## ZFS Snapshots for Backups

ZFS uses this format for timestamps:

```bash
date +%Y-%m-%d-%Hh00
```

Find the latest snapshot for a given dataset:

```bash
# sorting numerically (-n) and in reverse order (-r) to get the latest snapshot first
find .zfs/snapshot -name \*hourly\* -maxdepth 1 -print0 | xargs -0 -n 1 basename | sort -n -r | head -n 1
```

Borg configuration to use directory instead of live files:

```bash
SNAPSHOT_DIR="/path/to/zfs/dataset/.zfs/snapshot/$(find /path/to/zfs/dataset/.zfs/snapshot -name \*hourly\* -maxdepth 1 -print0 | xargs -0 -n 1 basename | sort -n -r | head -n 1)"
```

## List Borg Backups

```bash
sudo BORG_PASSCOMMAND='cat /run/agenix/borg' \
     BORG_REPO='hk1068@hk1068.rsync.net:mordor/srv/data' \
     BORG_RSH='ssh -i /run/agenix/borg-ssh' \
     borg --remote-path borg14 list
```
