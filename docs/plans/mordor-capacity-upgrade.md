# mordor zpool capacity upgrade — 29 TiB → 80 TiB+

**Status:** proposed
**Date:** 2026-08-22
**Goal:** get `mordor` to 50 TB+ usable, retire the failing drive, and leave a
credible path to retiring the rest of the 4 TB fleet.

---

## 1. Where we are today

### Pool

```
mordor  43.7T raw  34.6T alloc  9.08T free  25% frag  79% cap  DEGRADED
  raidz2-0   8 × 4TB   29.1T raw   82.8% full   (1 FAULTED)
  raidz2-1   4 × 4TB   14.5T raw   72.1% full
```

Usable (post-parity, per `zfs list`): **~28.9 TiB**, of which **23.7 TiB used /
5.16 TiB free**. `mordor/media` alone is 22.1 TiB.

Dataset settings are already correct for this workload — `recordsize=1M`,
`compression=lz4` (zstd on `share`/`data`), `atime=off`. Nothing to change there.

### Hardware

| Item | Detail |
|---|---|
| HBA | Broadcom/LSI **SAS2008** (Falcon), PCIe 2.0 x8, 6 Gb/s per lane |
| Expander | one `expander-0:0` behind the HBA |
| Enclosure | **24 bays**, `ArrayDevice00`–`ArrayDevice17` |
| Populated | **12** (`ArrayDevice00`–`0B`) |
| **Free bays** | **12** (`ArrayDevice0C`–`ArrayDevice17`) |
| Drives | 12 × HGST **HUS724040ALS640** — Ultrastar 7K4000, 4 TB, 7.2k, **SAS** |
| ZFS | 2.4.3, `feature@raidz_expansion` **enabled** |
| Boot/OS | Intel SSDPEKKF256G8L NVMe (separate, not in pool) |

**The 12 free bays are the whole story.** This is an expansion job, not a
replacement job.

### Drive health

Pulled from the smartctl exporter in Prometheus. Only one drive is actually sick:

| Dev | Slot | wwn | Power-on hrs | Grown defects | Uncorrected reads | Verdict |
|---|---|---|---|---|---|---|
| sda | 00 | `…5c6e8780` | 13,857 | 0 | 0 | healthy |
| sdb | 02 | `…5c7412e0` | 13,856 | 0 | 0 | healthy |
| sdc | 01 | `…5c73c920` | 13,857 | 0 | 0 | healthy |
| sdd | 03 | `…5c73d0e0` | 13,857 | 0 | 0 | healthy |
| sde | 04 | `…5c70e1fc` | 6,840 | 0 | 0 | healthy |
| sdf | 05 | `…5c73f1d0` | 13,857 | 0 | 0 | healthy |
| sdg | 06 | `…024c59cec` | **23,253** | 0 | 0 | old but clean — watch |
| **sdh** | **07** | `…024c485fc` | **23,253** | **402** | **11** | **FAULTED — replace now** |
| sdi | 08 | `…5c6842ac` | 1,754 | 0 | 0 | healthy |
| sdj | 09 | `…5c75d654` | 1,755 | 0 | 0 | healthy |
| sdk | 0A | `…5c76cbd8` | 1,754 | 0 | 0 | healthy |
| sdl | 0B | `…5c7aa498` | 1,757 | 0 | 0 | healthy |

`sdg`/`sdh` are the odd batch (`5000cca024…` prefix, 2.65 years powered) — the
rest are `5000cca05c…`. `sdh` is the only failure; `sdg` is its twin and the next
most likely to go. Last scrub (2026-08-02) repaired 4.34M with **0 errors**.

### Constraints worth stating up front

- **raidz vdevs cannot be removed from a pool.** Whatever `raidz2-0` and
  `raidz2-1` are today, they stay, unless the pool is destroyed and rebuilt.
- `raidz2-1` is **4-wide raidz2 = 50% storage efficiency**. It is the worst part
  of the layout. 10.5 TiB of data is sitting there at half density.
- The pool is **79% full**. ZFS allocation gets noticeably worse past ~80%, and
  `raidz2-0` is already at 82.8%. This is not an emergency but it is the reason
  to act this quarter rather than next year.
- **SAS only.** The backplane and HBA are SAS; SATA drives would work over STP
  through the expander but that mixes error-recovery behaviour and is not worth
  it. Every option below is SAS.

---

## 2. Disk choice and prices

Source: [diskprices.com (AU locale)](https://diskprices.com/?locale=au), read
2026-08-22. Note the site's "price per TB" column renders as $/GB on the
all-drives view — the SAS-filtered view gives correct $/TB. Figures below are
normalised to **A$ per TB**.

### SAS drives on the board

| Capacity | Price | A$/TB | Condition | Product |
|---|---|---|---|---|
| **16 TB** | **A$601** | **A$37.6** | Used | HPE 16TB 7.2K SAS `MB016000JYDKL` / `P44753-0` |
| **14 TB** | **A$546** | **A$39.0** | Used | HPE 14TB SAS 12G `P14060-001` / `P42348-003` (Renewed) |
| 6 TB | A$699 | A$116.5 | New | Seagate Exos 7E10 `ST6000NM020B` SAS |
| 16 TB | A$1,499 | A$93.7 | New | Seagate Exos X24 16TB SAS |
| 4 TB | A$273 | A$68.3 | New | HGST Ultrastar 7K4000 (same model as current fleet) |

For contrast, the cheapest **new SATA** on the whole board is the Seagate Exos
X16 14 TB at A$653 (**A$46.6/TB**) and Exos 26 TB at A$1,276 (**A$49/TB**). New
SAS is roughly double that. Used enterprise SAS at **A$37–39/TB is the cheapest
storage available in this market, full stop** — including cheaper than new SATA.

**Recommendation: used HPE 16 TB SAS at A$601 (A$37.6/TB).** The 14 TB is only
A$1.40/TB cheaper and gives you 12.5% less capacity per bay, which matters when
bays are the finite resource.

### ServerPartDeals — manufacturer-recertified SAS (added 2026-08-22)

Worth taking seriously as an alternative to no-warranty Amazon pulls. SPD's
[manufacturer-recertified collection](https://serverpartdeals.com/collections/manufacturer-recertified-drives)
carries a **3 Year Limited Period Warranty** (SPD's own — MR drives explicitly
carry *no manufacturer* warranty). They ship internationally with DDP/DDU options
and also run an [eBay AU store](https://www.ebay.com.au/str/serverpartdeals).

Full SAS 12Gb/s line, prices USD, converted at **1 USD = 1.405 AUD** (mid-Aug 2026)
plus 10% GST. **Shipping is not included and I could not price it without a
checkout — treat the landed column as a floor.**

| Capacity | Model | Sector | USD | A$ conv | +GST | **A$/TB** |
|---|---|---|---|---|---|---|
| **18 TB** | WD Ultrastar HC550 `WUH721818AL4201` | **4Kn** | $519 | 729 | **802** | **A$44.6** |
| 18 TB | WD Ultrastar HC550 `WUH721818AL5201` | 512e, **SED** | $519 | 729 | 802 | A$44.6 |
| 22 TB | WD Ultrastar HC580 `WUH722422AL5201` | 512e | $739 | 1,038 | 1,142 | A$51.9 |
| **24 TB** | WD Ultrastar HC580 `WUH722424AL4201` | **4Kn** | $733 | 1,030 | **1,133** | **A$47.2** |
| 24 TB | WD Ultrastar HC580 `WUH722424AL5201/5204` | 512e | $799 | 1,123 | 1,235 | A$51.5 |

Three things make this more attractive than the raw $/TB suggests:

1. **3-year warranty vs none.** The A$601 HPE pulls have no warranty and unknown
   power-on hours. SPD drives are manufacturer-recertified with a 3-year backstop.
   At a 6-drive scale that is real money if two drives die in year two.
2. **The 4Kn variants kill two risks from this plan at once.** A native-4Kn drive
   cannot be mis-detected as 512-byte, so **ZFS is guaranteed to pick ashift=12** —
   the one irreversible mistake in §5 simply cannot happen. And WD recert drives
   arrive correctly formatted, so the **520/528-byte `sg_format` step disappears**,
   cutting 12–30 h/drive off Phase 1.
3. **Avoid the SED variant** (`…AL5201`, 18 TB). Self-encrypting drives can arrive
   in a locked or unknown-PSID state and need `sedutil`/PSID revert before use.
   The 4Kn `…AL4201` is the same price. Take that one.

**Price comparison at the recommended 6-wide raidz2:**

| Source | Drive | Unit | 6-drive cost | New TiB | A$/new TiB | Warranty |
|---|---|---|---|---|---|---|
| Amazon AU | HPE 16 TB used | A$601 | **A$3,606** | 58.2 | **A$62** | none |
| SPD | WD HC550 18 TB 4Kn | ~A$802 | A$4,812 | 65.5 | A$73 | 3 yr |
| SPD | WD HC580 24 TB 4Kn | ~A$1,133 | A$6,798 | 87.3 | A$78 | 3 yr |

**Verdict: the SPD 18 TB 4Kn at ~A$802 landed is the better buy despite being
18% more per TB.** A$1,206 extra over the HPE option buys 7.3 TiB more capacity,
a 3-year warranty on six drives with no warranty otherwise, no `sg_format`
marathon, and immunity to the ashift trap. On used enterprise drives the warranty
is the part you are actually paying for.

If budget is the binding constraint, the HPE 16 TB pulls still work and the plan
below is unchanged — just do the burn-in in Phase 1 properly, because nothing
else is protecting you.

**Before ordering:** run a cart to Australia to get real shipping + duties, and
prefer a **DDP** shipping method so there are no surprise fees at the border.

### Sourcing caveats for used enterprise SAS

These are real and will bite if ignored:

1. **520/528-byte sectors.** HPE/NetApp/EMC pulls are frequently formatted with
   T10-PI at 520 or 528 bytes/sector. Linux will show them as unusable or the
   wrong size. Fix is `sg_format --format --size=512 /dev/sdX` — takes 12–30 h
   per 16 TB drive and must run to completion. Budget for it; do it in parallel.
2. **Power-on hours.** Ask the seller, or check on arrival. Anything over ~40k
   hours is a poor buy at these prices. Reject and return.
3. **No warranty.** The A$601 listings show no warranty. This is why the array
   geometry below is raidz2 and not raidz1.
4. **Amazon AU is thin on SAS.** Only two large-capacity SAS lines are on
   diskprices at all. Also worth pricing: eBay AU enterprise-pull sellers, and
   AU resellers like [Disk'N'Go](https://www.diskngo.com/collections/enterprise-hard-drives).
   ServerPartDeals is priced out in full above.

---

## 3. Layout options

All capacities in **TiB usable** (drive TB × 0.909 × data-disk count), before
ZFS metadata overhead. Existing pool contributes **28.9 TiB**.

| # | New vdev | Drives | Cost | New TiB | Pool total | A$/new TiB | Bays used |
|---|---|---|---|---|---|---|---|
| A | 4 × 16 TB raidz2 | 4 | **A$2,404** | 29.1 | **58.0** | A$83 | 4 |
| B | 5 × 16 TB raidz2 | 5 | A$3,005 | 43.6 | 72.5 | A$69 | 5 |
| **C** | **6 × 16 TB raidz2** | **6** | **A$3,606** | **58.2** | **87.1** | **A$62** | **6** |
| D | 8 × 16 TB raidz2 | 8 | A$4,808 | 87.3 | 116.2 | **A$55** | 8 |
| E | 6 × 14 TB raidz2 | 6 | A$3,276 | 50.9 | 79.8 | A$64 | 6 |
| F | replace 8 × 4 TB in `raidz2-0` in place | 8 | A$4,808 | +65.5 | 94.4 | A$73 | 0 |

### Recommendation: **Option C — 6-wide raidz2 in the free bays**

Preferred fill: **6 × 18 TB WD HC550 4Kn from SPD (~A$4,812 landed)** → 65.5 TiB new,
**~94 TiB pool total**. Budget fill: 6 × 16 TB HPE from Amazon AU (A$3,606) → 58.2 TiB
new, ~87 TiB total. Geometry and every phase below are identical either way.

Why:

- **Clears the goal by a wide margin.** 87 TiB total against a 50 TB target, and
  drops pool utilisation from 79% to ~27%. That is years of headroom.
- **67% storage efficiency** (4 data + 2 parity) — a real improvement on the
  4-wide `raidz2-1`, and the standard sweet spot for raidz2 width. Wide enough
  that parity isn't dominating, narrow enough that resilver windows stay sane.
- **raidz2, not raidz1.** Non-negotiable on used drives with no warranty and
  16 TB rebuild times. A 16 TB resilver on a busy pool is a multi-day window;
  single parity through that window is how pools die.
- **Leaves 6 free bays** for the retirement path in §6.
- Option D is better $/TB (A$55) and if the budget is there it is the
  buy-once-cry-once answer. But C + a later raidz expansion gets you to the same
  place — see below.

### Why not the others

- **A (4-wide)** repeats the `raidz2-1` mistake: 50% efficiency, and you'd be
  paying A$83/TiB to build a vdev you'll resent.
- **B (5-wide)** is fine but odd; 6-wide costs A$601 more for 14.6 TiB extra.
- **E (14 TB)** saves A$330 and costs you 7.3 TiB. Bad trade when bays are finite.
- **F (in-place replacement)** needs **eight sequential resilvers** on a pool
  that's 82.8% full, each one a 1–2 day window at reduced redundancy, on drives
  averaging 13.8k hours. The last scrub took **30 hours**; resilvers on a full
  raidz2 are comparable or worse. It also throws away eight working drives and
  gains nothing that adding a vdev doesn't. It is the right move *later*, when
  the 4 TB drives are genuinely old — not now.

### The raidz-expansion escape hatch

ZFS 2.4.3 is running and `feature@raidz_expansion` is **enabled** on the pool.
That means `zpool attach mordor raidz2-2 <newdisk>` can grow the new vdev from
6-wide to 7- or 8-wide later, one drive at a time, online.

Caveat that matters: **expansion does not re-stripe existing data.** Blocks
written at 6-wide keep their 6-wide parity ratio forever; only new writes get the
better ratio. So expansion is a way to add capacity incrementally, not a way to
retroactively improve efficiency. Given that, starting at 6-wide and expanding as
budget allows is a legitimate strategy — but if you know you want 8-wide, buying
8 up front (Option D) is strictly better.

---

## 3b. Budget tiers (under A$3,000)

All figures **TiB usable**, on top of the existing **28.9 TiB**. Amazon AU used
HPE SAS unless marked SPD. Every tier assumes **Phase 0 is done first** — one of
your four spare 4 TB drives replaces `sdh` and the pool is ONLINE before anything
else happens, leaving three spares.

### Tier 0 — Destitute: **A$0**

You own **4 spare 4 TB drives**; one replaces `sdh` in Phase 0, leaving **3**.
`feature@raidz_expansion` is enabled, so put them in free bays and grow
`raidz2-1` — the 50%-efficient 4-wide vdev — one drive at a time:

```bash
sudo zpool attach mordor raidz2-1 /dev/disk/by-id/wwn-<spare1>
# each reflow must finish completely before the next attach
sudo zpool attach mordor raidz2-1 /dev/disk/by-id/wwn-<spare2>
sudo zpool attach mordor raidz2-1 /dev/disk/by-id/wwn-<spare3>
```

| `raidz2-1` width | raw | efficiency | pool usable | pool free | gain |
|---|---|---|---|---|---|
| 4 (today) | 14.5 T | 50% | 28.9 TiB | 5.16 TiB | — |
| 5 | 18.2 T | 60% | 31.4 TiB | 7.7 TiB | +2.6 |
| **6** *(keep 1 spare)* | 21.8 T | 67% | **34.4 TiB** | 10.7 TiB | **+5.5** |
| **7** *(all 3)* | 25.5 T | **71%** | **37.5 TiB** | **13.9 TiB** | **+8.7** |

**Up to +8.7 TiB usable, for nothing** — pool free space nearly triples. Existing
blocks keep their 4-wide parity ratio (the reflow relocates data, it does not
re-parity it), so the gain is free space, not a recovery of the 10.5 T already
written.

**Recommended: go to 6-wide and keep one spare on the shelf.** You just lost a
drive, five members of `raidz2-0` are at 13.8k hours and `sdg` is at 23.2k. Being
able to replace the next failure the same day is worth more than the third
drive's 3.2 TiB. Take the 7-wide option only if you also buy a replacement spare
(A$273 for a new HGST 7K4000, same model as the fleet).

Costs either way: 2–3 free bays, and **1–2 days of reflow per drive** — budget
most of a week for all three. The pool stays online throughout.

**Why `raidz2-1` and not `raidz2-0`:** expanding `raidz2-0` from 8- to 11-wide
would actually yield slightly more (+9.3 TiB) and land at 82% efficiency. Don't.
That vdev holds the oldest drives in the box — `sdg` at 23,253 hours, and the one
that just died — and widening a raidz2 with aging members raises the odds of a
double failure inside one reflow window. `raidz2-1` holds `sdi`–`sdl` at ~1,750
hours, the newest drives you own, and it is the vdev with the geometry problem.
Expand the young, healthy, badly-shaped vdev.

**Do this regardless of which tier you buy.** It is free capacity and it fixes
the worst geometry in the pool.

### Tier 1 — Skint: **A$1,202** — 2 × 16 TB mirror

| | |
|---|---|
| New | +14.6 TiB (A$83/TiB) |
| Pool total | 43.4 TiB — **48.9 / 52.1 TiB with Tier 0 (6- / 7-wide)** |
| Bays used | 2 |

Worst $/TiB here, but it has one property nothing else does: **mirror and stripe
vdevs can be removed from a pool; raidz vdevs cannot.** So this is the only
purchase that isn't permanent. If you later build the real vdev, `zpool remove`
evacuates the mirror and you get the drives and bays back.

Doesn't reach 50 TB alone. With Tier 0 it just about does.

### Tier 2 — Budget: **A$2,404** — 4 × 16 TB raidz2

| | |
|---|---|
| New | +29.1 TiB (A$83/TiB) |
| Pool total | **58.0 TiB** — 63.5 / 66.7 TiB with Tier 0 |
| Bays used | 4 |

Clears 50 TB on its own. But 4-wide raidz2 is **50% efficient** — you would be
building a second `raidz2-1`, the exact vdev this document complains about, and
paying the same A$83/TiB as the removable mirror for something permanent.

Note `3 × 16 TB raidz1` costs A$1,803 for the *same* 29.1 TiB (A$62/TiB) — and
I am not recommending it. Single parity across a multi-day 16 TB resilver on
unwarranted used pulls is how you lose a vdev.

Take this tier only if A$2,404 is a hard ceiling.

### Tier 3 — Mid: **A$3,005** — 5 × 16 TB raidz2 ⭐

| | |
|---|---|
| New | +43.7 TiB (**A$69/TiB** — best under budget) |
| Pool total | **72.5 TiB** — **78.0 / 81.2 TiB with Tier 0** |
| Bays used | 5 (7 still free) |

**This is the pick.** Five bucks over A$3,000. 60% efficiency, double parity, and
it drops pool utilisation from 79% to roughly 30%.

The reason it beats Tier 2 by more than the capacity suggests: **you can raidz-
expand it later.** Add a sixth 16 TB for A$601 whenever you feel like it and you
land exactly on the Option C layout from §3 — 6-wide raidz2, 58.2 TiB — without
rebuying anything. Tier 3 is Option C on layaway.

```bash
sudo zpool add -o ashift=12 mordor raidz2 wwn-<d1> ... wwn-<d5>
# later, no downtime:
sudo zpool attach mordor raidz2-2 wwn-<d6>
```

### Comparison

"+Tier 0" columns show pool total with `raidz2-1` at 6-wide (2 spares, 1 kept)
and 7-wide (all 3 spares).

| Tier | Config | Cost | New TiB | Total | +T0 6w | +T0 7w | A$/TiB | Eff. |
|---|---|---|---|---|---|---|---|---|
| 0 | expand `raidz2-1` w/ spares | **A$0** | +5.5 / +8.7 | 34.4 / 37.5 | — | — | — | 67 / 71% |
| 1 | 2 × 16 TB mirror | A$1,202 | 14.6 | 43.4 | 48.9 | **52.1** | A$83 | 50% |
| 2 | 4 × 16 TB raidz2 | A$2,404 | 29.1 | 58.0 | 63.5 | 66.7 | A$83 | 50% |
| **3** | **5 × 16 TB raidz2** | **A$3,005** | **43.7** | **72.5** | **78.0** | **81.2** | **A$69** | **60%** |
| — | 5 × 14 TB raidz2 | A$2,730 | 38.2 | 67.1 | 72.6 | 75.8 | A$71 | 60% |
| — | 6 × 16 TB raidz2 (§3 Option C) | A$3,606 | 58.2 | 87.1 | 92.6 | 95.8 | A$62 | 67% |

Note Tier 1 + Tier 0 at 7-wide reaches **52.1 TiB — the 50 TB goal cleared for
A$1,202**, entirely with removable vdevs. That is the cheapest path to target
that exists.

Ruled out under A$3k: **SPD 18 TB** works out to A$98/TiB at 4-wide raidz2 — the
warranty argument in §2 only pays off at 6 drives, which is A$4,812. **2 × 24 TB
SPD mirror** is A$104/TiB. **5 × 14 TB** is fine and saves A$275, but costs you
5.5 TiB and can't grow into Option C as cleanly.

### Recommended under-A$3k path

1. **Phase 0** — replace `sdh` from your 4 spares. A$0. Pool back to ONLINE.
2. **Tier 0** — expand `raidz2-1` 4-wide → 6-wide with two of the three remaining
   spares. A$0, +5.5 TiB. **Keep the third on the shelf.**
3. **Tier 3** — 5 × 16 TB HPE SAS raidz2. A$3,005, +43.7 TiB.
4. Later, when convenient: attach a 6th 16 TB (A$601) → Option C, ~87 TiB.

**Total A$3,005 → ~78 TiB usable**, 79% full becomes ~30% full, 7 bays still
free, one spare in hand, and an upgrade path that never re-buys anything.

If A$3,005 is out of reach: **Tier 0 at 7-wide + Tier 1 = A$1,202 → 52.1 TiB**,
goal met, and the mirror is removable later when you can afford the real vdev.

---

## 4. Pre-purchase checks

Do these before spending money.

1. **HBA firmware.** SAS2008 needs **P20 IT-mode** firmware for reliable
   large-drive support. Confirm:
   ```bash
   sudo sas2flash -listall     # or: dmesg | grep -i mpt2sas | head
   ```
   Older IR-mode firmware has known issues; if it's not P20 IT, flash before
   adding drives, not after.

2. **PSU headroom.** Going from 12 to 18 drives adds ~6 × 11 W idle / ~6 × 25 W
   spin-up. Check the PSU rating and whether the backplane does staggered
   spin-up. 18 × 7.2k SAS is roughly 200 W idle, ~450 W at simultaneous spin-up.

3. **Cooling.** Bays 0C–11 have never had airflow load. Confirm fan curve and
   watch `smartctl_device_temperature` after install — target under 45 °C.

4. **HBA bandwidth (accept, don't fix).** PCIe 2.0 x8 caps around 3.2 GB/s real.
   18 drives at ~200 MB/s sequential each is 3.6 GB/s, so scrubs will be
   HBA-limited. For a media pool this is fine — it just makes scrubs longer. If
   it becomes a problem the fix is a SAS3008/9300-8i, not a layout change.

5. **Backup reality check.** 22.1 TiB of `mordor/media` is almost certainly not
   in borg. Confirm what `mordor/data`, `mordor/share` and `mordor/vault`
   coverage looks like before doing pool surgery, and accept explicitly that
   media is unbacked.

---

## 5. Migration plan

### Phase 0 — get healthy first (do this now, costs nothing)

The pool should not be degraded when the new drives arrive.

```bash
# Identify the physical slot (ArrayDevice07) and pull sdh.
# Insert one of the three spare 4TB drives.
sudo zpool replace mordor wwn-0x5000cca024c485fc /dev/disk/by-id/wwn-<new>
watch zpool status mordor
```

Expect a resilver in the 12–24 h range (`raidz2-0` is 82.8% full). That leaves
**three spare 4 TB drives** — see §3b Tier 0 for what to do with them. Do **not**
start Phase 2 (or any expansion) until this completes and `zpool status` reads
ONLINE; raidz expansion will not run on a degraded pool.

Optional but sensible while waiting: `sudo zpool scrub mordor` after the
resilver, to confirm the rest of `raidz2-0` is sound before you commit money.
That's another ~30 h.

### Phase 1 — receive and burn in the new drives

Do **not** put unburned-in used drives straight into a pool. Bathtub-curve
failures show up in the first week.

For each new drive:

```bash
# 1. Check sector size — if it's 520/528, reformat. This is the long pole.
sudo sg_readcap -l /dev/sdX
sudo sg_format --format --size=512 /dev/sdX      # 12-30h per drive, run in parallel

# 2. Check hours and defect list
sudo smartctl -x -d scsi /dev/sdX | grep -iE "hours powered up|grown defect|uncorrected"

# 3. Long self-test
sudo smartctl -t long -d scsi /dev/sdX           # ~24h for 16TB

# 4. Full-surface write/read
sudo badblocks -b 4096 -wsv -t random /dev/sdX   # several days; optional if 1-3 clean
```

Reject anything with a non-zero grown defect list, any uncorrected error, or
>40k power-on hours. Budget **1–2 weeks** for this phase running all six in
parallel. Rushing it is the single most likely way this project goes wrong.

### Phase 2 — add the vdev

Zero-risk to existing data; adding a vdev doesn't touch the others.

```bash
sudo zpool add mordor raidz2 \
  /dev/disk/by-id/wwn-<d1> /dev/disk/by-id/wwn-<d2> /dev/disk/by-id/wwn-<d3> \
  /dev/disk/by-id/wwn-<d4> /dev/disk/by-id/wwn-<d5> /dev/disk/by-id/wwn-<d6>
```

Notes:

- **Always use `/dev/disk/by-id/wwn-*`**, never `/dev/sdX` — matches the existing
  pool convention and survives renumbering.
- **Verify ashift is 12** before committing. `zpool add -n` for a dry run, and
  check with `zdb -C mordor | grep ashift` after. If the drives report 512e ZFS
  may pick ashift=9, which is unfixable without destroying the vdev:
  ```bash
  sudo zpool add -o ashift=12 mordor raidz2 ...
  ```
  Set it explicitly. This is the one irreversible mistake available in this plan.
- Set `autoexpand=on` while you're here — it's currently `off`, which will
  silently cost you capacity on any future in-place drive swap:
  ```bash
  sudo zpool set autoexpand=on mordor
  ```

### Phase 3 — rebalance (optional, recommended)

After the add, the pool has 28.9 TiB of data on the old vdevs and an empty new
one. ZFS writes preferentially to the emptiest vdev, so it self-corrects over
time — but reads of existing media stay bottlenecked on the old drives.

To force it, rewrite the data. ZFS 2.4 has `zfs rewrite`:

```bash
sudo zfs rewrite -r mordor/media
```

This is I/O-heavy and will take days. It is genuinely optional — for a media
pool the performance difference is not noticeable. Skip it unless you want the
old vdevs drained ahead of Phase 4.

### Phase 4 — retire `raidz2-1` (later, when drives age out)

`raidz2-1` (4 × 4 TB, 50% efficient) is the piece worth killing. It cannot be
removed. Two paths when the time comes:

- **Expand it.** `zpool attach mordor raidz2-1 <disk>` up to 6- or 8-wide. Old
  blocks keep the bad ratio; new ones don't. Cheap, online, incremental.
- **Replace in place.** Swap all four 4 TB for 16 TB with `autoexpand=on`
  → 4-wide raidz2 of 16 TB = 29.1 TiB usable. Still 50% efficient, but 4× the
  capacity for four drives and four resilvers.

Neither is urgent — `sdi`–`sdl` are at 1,750 hours, the newest drives in the box.
Revisit in 2–3 years.

The genuine long-term end state, if you ever want it: build a second large vdev
in the remaining 6 bays, `zfs send` everything across, destroy `mordor`, rebuild
clean. That's the only way to actually be rid of `raidz2-1`.

---

## 6. Final state

### Recommended path — Phase 0 + Tier 0 (6-wide) + Tier 3 — **A$3,005**

```
mordor
  raidz2-0    8 × 4TB    21.8 TiB usable   (sdh replaced from spares)
  raidz2-1    6 × 4TB    14.6 TiB usable   <- expanded 4->6 with 2 spares, free
  raidz2-2    5 × 16TB   43.7 TiB usable   <- new
  ---------------------------------------------
  total                  ~78 TiB usable
  used                    23.7 TiB (~30%)
```

- Bays: **19 of 24** used, 5 free.
- Spares on shelf: **1 × 4 TB**.
- Cost: **A$3,005** + shipping/GST.
- Goal (50 TB+): **cleared, 1.5×.**
- Growth path: attach a 6th 16 TB (A$601) any time → ~92 TiB, no rebuy.

### Buy-once path — Phase 0 + Tier 0 (6-wide) + Option C — **A$3,606**

```
mordor
  raidz2-0    8 × 4TB    21.8 TiB usable
  raidz2-1    6 × 4TB    14.6 TiB usable
  raidz2-2    6 × 16TB   58.2 TiB usable   <- new
  ---------------------------------------------
  total                  ~93 TiB usable
  used                    23.7 TiB (~26%)
```

- Bays: **20 of 24** used, 4 free. Spares: 1 × 4 TB.
- Goal: **cleared, 1.9×.**

### Floor — Phase 0 + Tier 0 (7-wide) + Tier 1 — **A$1,202**

~52 TiB total, goal just cleared, zero spares left, and both new vdevs
(the mirror and the expansion) remain undoable later.

## 7. Follow-ups for this repo

- Add a Prometheus alert on `smartctl_scsi_grown_defect_list > 0` — `sdh` hit 402
  before it faulted and there was no alert on the growth curve. See
  `nixos/sauron/monitoring/`.
- Add an alert on pool capacity > 80%.
- Once the vdev is in, revisit `docs/zfs-tuning.md` and `docs/sauron-disk-space.md`.
- Record the new drives' serials + slot mapping in `docs/sauron-issues.md`.

## Sources

- [diskprices.com — AU](https://diskprices.com/?locale=au) (read 2026-08-22)
- [Disk'N'Go — enterprise HDDs, AU](https://www.diskngo.com/collections/enterprise-hard-drives)
- [ServerPartDeals — manufacturer-recertified drives](https://serverpartdeals.com/collections/manufacturer-recertified-drives) (read 2026-08-22)
- [ServerPartDeals — shipping policy (DDP/DDU)](https://serverpartdeals.com/pages/shipping-policy)
- [ServerPartDeals eBay AU store](https://www.ebay.com.au/str/serverpartdeals)
- USD/AUD 1.405, mid-August 2026
