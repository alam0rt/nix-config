# Sauron Issues

Observed from `journalctl -p err -b` on 2026-04-02.

## Disk I/O errors on sdg and sdb

- `I/O error, dev sdg, sector 544 op 0x0:(READ)`
- `I/O error, dev sdb, sector 544 op 0x0:(READ)`

Both at boot, same sector. Both are Hitachi HUS724040ALS640 4TB SAS drives.

SMART checked 2026-04-02: both healthy, zero grown defects, temps normal (32-33°C).
- sdg: 19,844 power-on hours, mfg 2013
- sdb: 10,449 power-on hours, mfg 2014

Likely transient SAS spinup errors. Monitor for recurrence.

## botamusique failed to start

`Failed to start botamusique.service` at boot. No further details in error log.
Determine if this service is still needed — if not, disable it.

## nmbd spamming link-local broadcast errors

Samba's `nmbd` repeatedly fails to send packets to `169.254.255.255` on
interface `eno2` (link-local subnet `169.254.167.242`). The DHCP lease on `eno2`
expired, leaving only a link-local address with no reachable broadcast target.

Options:
- Bind nmbd to specific interfaces (exclude eno2)
- Disable nmbd entirely if NetBIOS name resolution isn't needed (likely — modern
  clients use mDNS/DNS-SD)

## /boot world-accessible (random seed security warning)

`bootctl` warns:
- `Mount point '/boot' which backs the random seed file is world accessible`
- `Random seed file '/boot/loader/random-seed' is world accessible`

Fix by tightening `/boot` mount permissions (e.g. `fmask=0077` in fstab/mount
options).

## wl kernel module not found

`systemd-modules-load: Failed to find module 'wl'` — Broadcom wireless driver
reference, irrelevant on a server. Remove from `boot.kernelModules` or
`modules-load` config to silence the error.
