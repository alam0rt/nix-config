# Use ZFS snapshots instead of live files for Borg backups


ZFS uses this format for timestamps:
```bash
date +%Y-%m-%d-%Hh00
```

Find the latest snapshot for a given dataset:

```bash
# sorting numerically (-n) and in reverse order (-r) to get the latest snapshot first
find .zfs/snapshot -name \*hourly\* -maxdepth 1 -print0 | xargs -0 -n 1 basename | sort -n -r | head -n 1
``

borg configuration to use directory instead of live files:

```bash
SNAPSHOT_DIR="/path/to/zfs/dataset/.zfs/snapshot/$(find /path/to/zfs/dataset/.zfs/snapshot -name \*hourly\* -maxdepth 1 -print0 | xargs -0 -n 1 basename | sort -n -r | head -n 1)"
```

## Borg Backup Jobs

Current backup jobs configured:
- **mordor-vault**: `/srv/vault` → `mordor/vault` (daily)
- **mordor-srv-data**: `/srv/data` → `mordor/srv/data` (hourly)
  - Excludes: `*.db-wal`, `*.db-shm` (SQLite temp files)
- **mordor-share-sam**: `/srv/share/sam` → `mordor/share/sam` (daily)
- **mordor-share-emma**: `/srv/share/emma` → `mordor/share/emma` (daily)

All jobs use:
- Remote: `hk1068@hk1068.rsync.net`
- Encryption: `repokey-blake2`
- Compression: `auto,zstd`
- SSH key: `/srv/vault/ssh_keys/id_rsa`

## List borg backups

Example for the srv/data backup:

```bash
sudo BORG_PASSCOMMAND='cat /run/agenix/borg' BORG_REPO='hk1068@hk1068.rsync.net:mordor/srv/data' BORG_RSH='ssh -i /srv/vault/ssh_keys/id_rsa' borg --remote-path borg14 list
```

For other repositories, replace `mordor/srv/data` with:
- `mordor/vault`
- `mordor/share/sam`
- `mordor/share/emma`
