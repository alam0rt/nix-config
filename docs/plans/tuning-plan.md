# Sauron Kernel & System Tuning Plan

Evaluation of Linux kernel tunables for sauron — a multi-service AMD server running
Nginx, Matrix, Jellyfin, media stack, LLM inference (llama-cpp), Home Assistant,
Prometheus/Grafana, mail, Transmission, and NAS duties over ZFS.

**Current setup:** ext4 root, ZFS data pool (mordor), 9000 MTU on eno2, Nvidia GPU
(CUDA), 32GB swap file, podman containers, NixOS default kernel (no custom
`linuxPackages`).

**Already tuned:**
- BBR + fq qdisc
- 16MB socket buffer ceilings (`rmem_max`/`wmem_max`)
- Per-socket auto-tuning range (`tcp_rmem`/`tcp_wmem`)
- `tcp_slow_start_after_idle = 0`
- `tcp_mtu_probing = 1`
- ZFS I/O scheduler disabled (udev rule)
- Nginx: `directio 4m`, `aio threads`, large `output_buffers`

---

## Network Stack

### TCP Fast Open — RECOMMENDED

```
net.ipv4.tcp_fastopen = 3
```

Saves a round-trip on repeat TCP connections by embedding data in the SYN/SYN-ACK.
Mode 3 enables both client and server sides. Directly benefits Nginx (every browser
reconnection), Matrix federation, and any outbound HTTP (media fetchers, webhook
calls).

**Risk:** Minimal. Some middleboxes strip TFO options, but the kernel falls back
gracefully. ZFS/storage unaffected.

**Measuring:**
- `node_netstat_TcpExt_TCPFastOpenActive` / `TCPFastOpenPassive` — count of
  successful TFO connections (already exposed by node_exporter tcpstat collector)
- Compare `probe_http_duration_seconds` (blackbox exporter) before/after for repeat
  connections to local services

### Listen backlog — RECOMMENDED

```
net.core.somaxconn = 4096
net.ipv4.tcp_max_syn_backlog = 4096
net.core.netdev_max_backlog = 4096
```

Defaults (128/1024/1000) can cause SYN drops under bursty load — Jellyfin streaming
sessions, Matrix federation bursts, media grabber activity all hitting Nginx
simultaneously. With 9000 MTU jumbo frames, larger `netdev_max_backlog` helps absorb
packet bursts at the driver level.

**Risk:** None. Just increases queue capacity; unused memory is negligible.

**Measuring:**
- `node_netstat_TcpExt_ListenOverflows` — increments when the accept queue is full
  (should be 0; if non-zero before tuning, this is the fix)
- `node_netstat_TcpExt_ListenDrops` — SYNs dropped due to full backlog
- `node_netstat_Tcp_PassiveOpens` — total accepted connections (baseline)

### Busy polling — NOT RECOMMENDED

```
net.core.busy_read (skip)
net.core.busy_poll (skip)
```

Trades CPU for ~5-50us latency reduction by spin-waiting on sockets. Sauron is
throughput-oriented and already CPU-loaded (LLM inference, bioinformatics workloads).
Burning cores on spin-waits is counterproductive. Also requires NIC driver support
(`ndo_busy_poll`) — onboard NICs (likely `tg3`/`bnxt` given Broadcom on this board)
typically don't implement it.

### MPTCP — NOT APPLICABLE

Sauron has a single network path (eno2). MPTCP requires multiple interfaces or paths
to provide any benefit.

### GRO/GSO verification — LOW EFFORT CHECK

Already on by default, but worth a one-time verification:

```bash
ethtool -k eno2 | grep -E 'generic-(receive|segmentation)-offload'
```

**Measuring:** Not needed beyond the check — these are fundamental and affect all
throughput numbers.

### RPS/RFS (Receive Packet/Flow Steering) — WORTH INVESTIGATING

Distributes network interrupt processing across CPU cores. Relevant because sauron is
a multi-core AMD system serving many concurrent connections, but all NIC interrupts
may land on a single core by default.

```bash
# Check current IRQ distribution:
cat /proc/interrupts | grep eno2
# Check if RPS is configured:
cat /sys/class/net/eno2/queues/rx-*/rps_cpus
```

If the NIC only has 1-2 RX queues, RPS can spread the load. If the NIC already has
many hardware queues with RSS, this is less important.

**Measuring:**
- `node_softnet_dropped_total` — packets dropped due to per-CPU backlog overflow
- `node_softnet_processed_total` — per-CPU softirq processing (already collected via
  softirqs collector). Uneven distribution indicates need for RPS
- Per-CPU `si` (softirq) time in CPU metrics — one core maxed on softirq = bottleneck

---

## Memory & Scheduling

### MGLRU (Multi-Gen LRU) — RECOMMENDED

```
boot.kernel.sysctl."vm.mglru.enabled" = 1;
```

Or via sysfs: `echo 1 > /sys/kernel/mm/lru_gen/enabled` (NixOS sysctl path may
differ; a tmpfiles rule may be needed).

MGLRU (kernel 6.1+) improves page reclaim decisions by tracking access recency across
multiple generations rather than a simple active/inactive split. Sauron is a textbook
beneficiary: mixed workloads competing for memory (ZFS ARC, LLM model weights, Nginx
workers, Matrix, Jellyfin transcoding, containers, bioinformatics jobs).

**Risk:** Low. MGLRU has been mainline since 6.1 and is default-on in ChromeOS and
some distros. Can be toggled at runtime.

**NixOS implementation:**
```nix
# MGLRU needs to be enabled via sysfs, not sysctl
systemd.tmpfiles.rules = [
  "w /sys/kernel/mm/lru_gen/enabled - - - - 5"
  # 5 = enable MGLRU for both anon and file pages
];
```

**Measuring:**
- `node_memory_MemAvailable_bytes` — should be more stable under mixed load
- `node_vmstat_pgscan_direct` / `node_vmstat_pgsteal_direct` — direct reclaim
  activity (should decrease with MGLRU; less stalling)
- `node_vmstat_pswpin` / `node_vmstat_pswpout` — swap I/O (should decrease)
- ZFS ARC hit ratio (`node_zfs_arc_hits / (hits + misses)`) — less page cache
  pressure means ZFS ARC gets evicted less

### Transparent Huge Pages — LEAVE AS DEFAULT (madvise)

THP `always` can cause latency spikes from compaction and hurts allocator-heavy
workloads. With ZFS (which manages its own memory via ARC/slab), Matrix (Synapse uses
Python with many small allocations), and podman containers, `madvise` is the safe
choice. Applications that benefit (like LLM inference) can opt in via `madvise()`.

### zswap — RECOMMENDED

```nix
boot.kernelParams = [ "zswap.enabled=1" "zswap.compressor=zstd" "zswap.zpool=z3fold" ];
```

Compresses swap pages in RAM before writing to the 32GB swap file. With LLM inference
and bioinformatics jobs, memory pressure is real. zswap can absorb pressure spikes
without hitting slow disk swap. zstd gives good compression ratios for mixed data.

**Risk:** Low. Uses some CPU for compression (negligible vs LLM inference load).
Worst case: pages that don't compress well get written through to disk swap as normal.

**Measuring:**
- `/sys/kernel/debug/zswap/pool_total_size` — current compressed pool size
- `/sys/kernel/debug/zswap/stored_pages` vs `written_back_pages` — ratio shows how
  effectively zswap is absorbing pressure
- `node_vmstat_pswpout` — disk swap writes should decrease significantly
- Custom textfile collector or a simple cron exporting zswap stats to
  node_exporter's textfile directory:
  ```bash
  # /etc/cron.d/zswap-metrics or systemd timer
  #!/bin/bash
  dir=/sys/kernel/debug/zswap
  out=/var/lib/prometheus-node-exporter/zswap.prom
  for f in stored_pages pool_total_size written_back_pages reject_compress_poor; do
    echo "zswap_${f} $(cat $dir/$f)" >> "$out.tmp"
  done
  mv "$out.tmp" "$out"
  ```

### PSI (Pressure Stall Information) + systemd-oomd — RECOMMENDED

PSI is compiled into NixOS kernels but `systemd-oomd` isn't always enabled. It
provides proactive OOM killing based on actual resource pressure rather than the
kernel's last-resort OOM killer.

```nix
systemd.oomd = {
  enable = true;
  enableRootSlice = true;
  enableUserSlices = true;
};
```

**Measuring:**
- `/proc/pressure/memory` — `some avg10`, `full avg10` values
- PSI metrics are available via node_exporter `--collector.pressure` flag (add to
  `extraFlags`)
- `node_pressure_memory_waiting_seconds_total` — time tasks spent stalled on memory
- Alert on sustained memory pressure:
  ```
  rate(node_pressure_memory_stalled_seconds_total[5m]) > 0.1
  ```

### DAMON — SKIP FOR NOW

Proactive memory reclaim via access pattern monitoring. Powerful but complex to
configure and tune. MGLRU + zswap + oomd covers the same ground with less operational
complexity. Revisit if memory pressure remains an issue after the above changes.

---

## I/O & Filesystems

### I/O Scheduler — ALREADY HANDLED

ZFS disks already have scheduler set to `none` via udev rule (ZFS has its own I/O
scheduling). The ext4 root is on NVMe which defaults to `none` (appropriate). No
changes needed.

### ZFS compression — WORTH CHECKING

Not a kernel tunable, but verify compression is enabled on the mordor datasets:

```bash
zfs get compression mordor
zfs get compressratio mordor
```

If not already `lz4` or `zstd`, enabling `compression=lz4` on data-heavy datasets
(media, shares) is free performance — reduces I/O at negligible CPU cost.

**Measuring:**
- `zfs get compressratio` per dataset
- ZFS exporter already scrapes pool-level metrics

### io_uring — NO ACTION

Applications must opt in. Nginx doesn't use it yet (still epoll). No kernel-side
tuning available.

### DAX — NOT APPLICABLE

Sauron doesn't use persistent memory / Optane.

---

## CPU & Power

### Performance cpufreq governor — RECOMMENDED

```nix
powerManagement.cpuFreqGovernor = "performance";
```

Default is `schedutil` or `ondemand` which introduces frequency scaling latency.
Sauron is a server that's always doing work — there's no reason to save power. Fixed
max frequency eliminates ~1-5ms response time jitter from frequency ramp-up.

**Risk:** Higher power draw / heat. Sauron already has thermal monitoring via SMART
exporter.

**Measuring:**
- `node_cpu_scaling_frequency_hertz` — should show all cores at max after change
- Reduced variance in `probe_http_duration_seconds` (blackbox) — less jitter
- `node_cpu_seconds_total{mode="idle"}` — unchanged in total, but latency
  distribution tightens

### NUMA balancing — CHECK FIRST

```bash
numactl --hardware  # Check if sauron is actually NUMA
cat /proc/sys/kernel/numa_balancing
```

If sauron is a single-socket AMD system, NUMA balancing is irrelevant. If multi-socket
or if the AMD CPU has multiple NUMA nodes (some Zen architectures expose CCDs as NUMA
nodes), then `kernel.numa_balancing=1` helps. Check before enabling.

**Measuring:**
- `node_vmstat_numa_pages_migrated` — NUMA page migration activity
- `node_vmstat_numa_hit` vs `node_vmstat_numa_miss` — local vs remote memory access

---

## Security (Performance Tradeoffs)

### init_on_alloc — CONSIDER

```nix
boot.kernelParams = [ "init_on_alloc=1" ];
```

Zeros memory on allocation, preventing info leaks. ~1-2% performance overhead.
Reasonable for a server exposed to the internet (Nginx, Matrix, mail). NixOS hardened
kernel profile enables this by default; worth adding if not already present.

**Measuring:**
- Benchmark a representative workload before/after (e.g. `wrk` against Nginx)
- Should see ~1-2% throughput decrease if enabled; weigh against security benefit

### Lockdown mode — SKIP

Too restrictive for a system that needs NVIDIA kernel modules and runtime debugging.

---

## Observability Gaps

Current node_exporter flags: `--collector.systemd`, `--collector.ethtool`,
`--collector.softirqs`, `--collector.tcpstat`.

### Add these collectors for tuning visibility:

```nix
services.prometheus.exporters.node = {
  enable = true;
  port = 9000;
  enabledCollectors = ["systemd"];
  extraFlags = [
    "--collector.ethtool"
    "--collector.softirqs"
    "--collector.tcpstat"
    # New: needed for tuning measurements
    "--collector.pressure"       # PSI metrics (memory/cpu/io pressure)
    "--collector.buddyinfo"      # Memory fragmentation (THP/compaction insight)
    "--collector.meminfo_numa"   # NUMA memory distribution (if applicable)
    "--collector.netstat"        # TCP ext stats (ListenOverflows, TFO counters)
    "--collector.vmstat"         # Page scan/steal/swap rates, NUMA migration
    "--collector.interrupts"     # Per-CPU IRQ distribution (RPS evaluation)
  ];
};
```

Note: `netstat` and `vmstat` are enabled by default in most node_exporter builds, but
explicitly listing them ensures they're present. `pressure` and `buddyinfo` are not
default.

### Prometheus alert rules to add:

```promql
# SYN queue overflow (backlog tuning)
rate(node_netstat_TcpExt_ListenOverflows[5m]) > 0

# Memory pressure (PSI)
rate(node_pressure_memory_stalled_seconds_total[5m]) > 0.1

# Swap I/O rate (zswap effectiveness)
rate(node_vmstat_pswpout[5m]) > 100

# Softirq imbalance (RPS need)
# If one CPU handles >50% of network softirqs, RPS would help
```

### zswap textfile collector:

Export zswap stats to node_exporter textfile directory for Grafana visibility. See the
zswap section above for the script.

---

## Implementation Priority

| # | Change | Effort | Impact | Risk |
|---|--------|--------|--------|------|
| 1 | TCP Fast Open | 1 line sysctl | Medium | None |
| 2 | Listen backlog (somaxconn + friends) | 3 lines sysctl | Medium | None |
| 3 | cpufreq governor = performance | 1 line NixOS | Medium | Trivial (heat) |
| 4 | MGLRU enable | tmpfiles rule | High | Low |
| 5 | zswap enable | boot params | High | Low |
| 6 | PSI + systemd-oomd | 4 lines NixOS | Medium | Low |
| 7 | Node exporter collectors | extraFlags | Visibility | None |
| 8 | ZFS compression check | One-time check | Varies | None |
| 9 | RPS/RFS evaluation | SSH investigation | Varies | None |
| 10 | NUMA check | SSH investigation | Varies | None |
| 11 | init_on_alloc | boot param | Security | ~1-2% perf |

Items 1-7 can be implemented in a single NixOS rebuild. Items 8-10 require SSH access
to sauron first to evaluate current state. Collect baseline metrics for at least 24h
before applying changes, then compare.

---

## Baseline Metrics Checklist

Before applying changes, record 24h averages for:

- [ ] `rate(node_netstat_TcpExt_ListenOverflows[1h])` — should be 0
- [ ] `rate(node_vmstat_pswpout[1h])` — swap write rate
- [ ] `rate(node_vmstat_pgscan_direct[1h])` — direct reclaim pressure
- [ ] `avg(probe_http_duration_seconds{job="blackbox"})` — service response times
- [ ] `node_zfs_arc_hits / (node_zfs_arc_hits + node_zfs_arc_misses)` — ARC hit rate
- [ ] `avg(rate(node_cpu_seconds_total{mode="idle"}[5m]))` — CPU headroom
- [ ] `node_cpu_scaling_frequency_hertz` — current governor behavior
- [ ] `/proc/pressure/memory` — PSI baselines (via SSH until collector added)
