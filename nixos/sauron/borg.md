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
