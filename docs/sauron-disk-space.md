# Sauron root volume — space reclamation

Sauron's root ext4 volume is 250 GB and filling up. ZFS pool `mordor` (mounted at
`/srv/...`) has plenty of room. Every recommendation below is a pure-config
change to move growth off `/` or shrink it in place.

Priority order is "biggest win for least work" first.

## 1. Tighten Nix GC + cap boot generations

File: `nixos/config/common/default.nix`

Current config keeps 7 days of generations and only GCs weekly. On a host that
rebuilds often this is the single largest source of churn on `/nix/store`.

```nix
nix = {
  gc = {
    automatic = true;
    dates = "daily";
    options = "--delete-older-than 3d";
  };
  settings = {
    # Auto-GC when free space drops below min-free, stop at max-free.
    min-free = 10 * 1024 * 1024 * 1024;  # 10 GB
    max-free = 50 * 1024 * 1024 * 1024;  # 50 GB
  };
  optimise.automatic = true;
  optimise.dates = [ "weekly" ];
  channel.enable = false;
};

boot.loader.systemd-boot.configurationLimit = 10;
```

`min-free` / `max-free` is the important line — it triggers GC automatically
when the store is filling up, rather than waiting for the weekly timer.

Expected reclaim: **10–30 GB**, plus prevents future blowups.

## 2. Cap journald + disable coredumps

Add to `nixos/config/common/server.nix` (or wherever shared server config
lives):

```nix
services.journald.extraConfig = ''
  SystemMaxUse=500M
  SystemKeepFree=2G
'';

systemd.coredump.extraConfig = ''
  Storage=none
'';
```

`/var/log/journal` on a noisy server easily grows to multiple GB. Coredumps
from crashed services (Jellyfin transcodes, podman containers) can each be
hundreds of MB.

Expected reclaim: **2–10 GB**.

## 3. Shrink / relocate swap

File: `nixos/sauron/hardware-configuration.nix:76-81`

Currently 32 GB swapfile on `/`. Sauron has ample RAM; this is mostly dead
space.

Option A — shrink in place:
```nix
swapDevices = [
  {
    device = "/var/lib/swapfile";
    size = 8 * 1024;  # 8 GB
  }
];
```

Option B — move to a ZFS zvol (off root entirely). Create the zvol out of band:
```
zfs create -V 16G -b 4096 \
  -o compression=zle -o logbias=throughput -o sync=always \
  -o primarycache=metadata -o secondarycache=none \
  mordor/swap
```
Then reference it:
```nix
swapDevices = [ { device = "/dev/zvol/mordor/swap"; } ];
```
Note: NixOS won't create the zvol for you, and `hardware-configuration.nix`
is auto-generated — put the swap change in `configuration.nix` and remove it
from the hardware file.

Expected reclaim: **24 GB** (shrink) or **32 GB** (move).

## 4. Prometheus retention + scrape interval

File: `nixos/sauron/monitoring/default.nix:167-168`

```nix
services.prometheus = {
  enable = true;
  retentionTime = "15d";               # was 30d
  globalConfig.scrape_interval = "30s"; # was 10s
  # ...
};
```

At 10s scrape across node/zfs/nginx/smartctl/blackbox/jellyfin/exportarr
jobs, 30d of TSDB sits around 10–30 GB. Cutting scrape to 30s reduces sample
volume ~3×; cutting retention halves it again.

Optionally cap by size instead of time:
```nix
retentionSize = "10GB";
```

Also move the data dir to ZFS so growth doesn't matter:
```nix
services.prometheus.dataDir = "/srv/data/prometheus";
```

Expected reclaim: **10–20 GB** immediately (after one compaction cycle).

## 5. Move stateful service dataDirs onto ZFS

Services that currently live under `/var/lib` on root:

| Service      | Default path           | Recommended                  | Notes |
| ------------ | ---------------------- | ---------------------------- | ----- |
| Grafana      | `/var/lib/grafana`     | `/srv/data/grafana`          | sqlite + dashboards |
| Prometheus   | `/var/lib/prometheus2` | `/srv/data/prometheus`       | see §4 |
| Alertmanager | `/var/lib/alertmanager`| `/srv/data/alertmanager`     | |
| Bazarr       | `/var/lib/bazarr`      | `/srv/data/bazarr`           | `services.bazarr.dataDir` not currently set |
| Unifi        | `/var/lib/unifi`       | `/srv/data/unifi`            | MongoDB grows several GB |
| Vaultwarden  | `/var/lib/bitwarden_rs`| `/srv/data/vaultwarden`      | set `DATA_FOLDER` env + `StateDirectory` |
| Maubot       | `/var/lib/maubot`      | `/srv/data/maubot`           | |
| Syncthing    | `/var/lib/syncthing`   | `/srv/data/syncthing`        | also `configDir` |
| Mailserver   | `/var/vmail` etc.      | `/srv/data/mail`             | biggest unknown — audit size first |
| Jellyseerr   | `/var/lib/private/jellyseerr` | see below           | no dataDir option |

Most of these support `services.<name>.dataDir`. For services that don't
(Jellyseerr, Recyclarr), either:

- override `systemd.services.<name>.serviceConfig.StateDirectory` and
  bind-mount `/srv/data/<name>` onto `/var/lib/<name>`, or
- stop the service, `rsync -aHAX /var/lib/<name>/ /srv/data/<name>/`, then
  replace the original with a symlink.

For each service, the migration pattern is:
1. Stop the service.
2. `rsync -aHAX --delete /var/lib/<name>/ /srv/data/<name>/`
3. `chown -R <user>:<group> /srv/data/<name>`
4. Change config, rebuild.
5. Verify, then `rm -rf /var/lib/<name>`.

Expected reclaim: **5–20 GB** depending on which services have accumulated state.

## 6. Move Jellyfin cache off SSD

File: `nixos/sauron/media/default.nix:170`

```nix
services.jellyfin = {
  # ...
  dataDir  = "/srv/data/jellyfin";
  cacheDir = "/var/cache/jellyfin"; # leave on ssd  <-- this
};
```

The "leave on SSD" intent is fine for performance, but transcode cache and
image cache grow without bound. Two options:

Option A — cap the cache via tmpfs (RAM-backed, auto-evicted):
```nix
fileSystems."/var/cache/jellyfin" = {
  device = "tmpfs";
  fsType = "tmpfs";
  options = [ "size=4G" "mode=0755" "uid=jellyfin" "gid=jellyfin" ];
};
```

Option B — move to ZFS (slower but unlimited):
```nix
services.jellyfin.cacheDir = "/srv/data/jellyfin-cache";
```

Expected reclaim: **2–20 GB** (varies wildly by library size and transcode activity).

## 7. Ensure podman volumes aren't leaking

File: `nixos/sauron/configuration.nix:171-177`

Container storage is already correctly on `/srv/share/public/containers/storage`. ✓

But double-check these aren't growing on root:
- `/var/lib/containers/storage` (leftover from before the override)
- `/var/log/containers/`
- `/var/lib/containers/storage/volumes/` (if any containers predate the override)

If the old path has data, one-shot cleanup (manual, not config):
```
podman system prune -a --volumes
rm -rf /var/lib/containers/storage
```

## 8. Enable ZFS compression on `/srv/data` datasets

Not a root-volume fix, but worth doing as you migrate state onto ZFS so the
migrations pay off more:

```
zfs set compression=zstd mordor/data
zfs set atime=off mordor/data
```

(Out-of-band; not representable in the flake.)

---

## Rollout plan

Do these in order, rebuilding after each:

1. §1 (Nix GC) + §2 (journald/coredump) + §3 (swap shrink) + §4 (Prometheus)
   — all pure config, low risk. Should reclaim 40–80 GB.
2. §6 (Jellyfin cache → tmpfs) — reclaim + cap.
3. §5 (dataDir migrations) — one service at a time, verify each before moving on.
   Start with the biggest offenders: Unifi, Prometheus, Mailserver.
4. §7 (podman cleanup) — one-shot manual if needed.
5. §8 (ZFS compression) — out-of-band.

## How to identify the next target

When root fills up again, on sauron:
```
sudo du -xhd 1 / | sort -h | tail -20
sudo du -xhd 1 /var/lib | sort -h | tail -20
sudo du -xhd 1 /var/log | sort -h | tail -20
nix path-info -Sh /run/current-system
```
