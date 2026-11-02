# Kernel attack-surface reduction. Each knob here is from the KSPP recommended
# settings (https://kspp.github.io/Recommended_Settings) and was checked against
# what sauron actually runs before turning it on.
#
# CPU speculative-execution mitigations are left at the kernel default
# (mitigations=auto). They were off until 2026-11, but sauron runs third-party
# code (BWAPI ladder bots, Halo 3 under Wine) and Zen 1 is exposed to Spectre v2,
# Retbleed and SRSO, so "single-tenant, trusted" no longer held.
{...}: {
  boot.kernel.sysctl = {
    # No io_uring for anyone. It is behind a large share of recent kernel LPEs.
    # Nothing on sauron needs it: samba is the only package in the closure that
    # links liburing and its io_uring VFS module is not configured; libuv (node)
    # is opt-in since 1.49; podman's built-in seccomp profile already denies
    # io_uring_setup inside containers. Reversible live with
    # `sysctl -w kernel.io_uring_disabled=0`.
    "kernel.io_uring_disabled" = 2;

    # Unprivileged users can no longer pull in tty line disciplines (n_gsm,
    # n_hdlc...) by setting them on a pty.
    "dev.tty.ldisc_autoload" = 0;

    # One-way until reboot. Nothing here uses kexec.
    "kernel.kexec_load_disabled" = 1;
  };

  # Stop unprivileged socket() calls from autoloading protocol families nobody
  # here uses. `blacklist` only blocks alias-based autoloading, so an explicit
  # `modprobe` still works if one of these is ever needed.
  boot.blacklistedKernelModules = [
    "atm"
    "appletalk"
    "ax25"
    "caif"
    "can"
    "ieee802154"
    "kcm"
    "n_gsm"
    "n_hdlc"
    "netrom"
    "phonet"
    "rds"
    "rose"
    "rxrpc"
    "sctp"
    "tipc"
    "x25"
  ];
}
