# ZFS tuning for media serving

## recordsize on media datasets

The default ZFS recordsize is 128K. For datasets that store large media files
(video, music), setting `recordsize=1M` reduces metadata overhead and IO ops
per sequential read — a significant win for streaming workloads.

```bash
# Check current recordsize
zfs get recordsize tank/media

# Set 1M recordsize (applies to newly written data, not retroactively)
sudo zfs set recordsize=1M tank/media
```

Adjust `tank/media` to match your actual dataset path (e.g. the dataset
backing `/srv/media`). Existing files keep their original recordsize — to
benefit fully, files would need to be rewritten (e.g. via `zfs send | zfs recv`
to a new dataset, or by re-downloading).

Datasets with small files (databases, app state) should keep the default 128K
or lower.

## ARC sizing

ZFS uses the ARC (Adaptive Replacement Cache) for read caching in RAM. By
default it can grow up to ~50% of system memory but will shrink under pressure.

If the machine has plenty of RAM and media serving is the primary workload,
pinning a higher ARC minimum prevents the kernel from reclaiming cache that
ZFS is actively using:

```bash
# Check current ARC size and limits
arc_summary | head -30

# Or directly:
cat /proc/spl/kstat/zfs/arcstats
```

In NixOS, ARC limits are set via boot params:

```nix
# Example: pin ARC min to 8GB, max to 32GB
boot.kernelParams = [
  "zfs.zfs_arc_min=8589934592"   # 8GB
  "zfs.zfs_arc_max=34359738368"  # 32GB
];
```

Be cautious if the machine also runs memory-heavy services (LLM inference,
databases) — ARC and those workloads compete for the same RAM.
