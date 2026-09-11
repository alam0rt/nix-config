# PvPGN on sauron

A Battle.net server emulator. Serves **StarCraft / Brood War 1.16.1 only** —
Warcraft II/III and Diablo clients are refused by `allowed_clients`, and the
Diablo II realm daemons (`d2cs`, `d2dbs`) are not even built.

Listens on 6112/tcp+udp, on the LAN (`eno1`) and the tailnet (`tailscale0`).
Not reachable from the internet.

## Connecting

Point a 1.16.1 client at `sauron.middleearth.samlockart.com` (or the tailnet
IP). Accounts are created on first login — `new_accounts = true`.

Clients do this by editing `bnserver.ini` in the StarCraft directory, or by
picking a gateway that resolves there.

## State

Everything lives in `/srv/data/pvpgn`:

- `users.db` — SQLite, all accounts. Back this up; it is the whole server.
- `bnban.conf` — rewritten in place by `/ipban`, seeded from the package on
  first boot and never overwritten afterwards.
- `reports/`, `chanlogs/`, `userlogs/`, `bnmail/`, `ladders/`, `status/`

`bnetd.conf` is generated in full by `default.nix`; the rest of the config tree
comes from the package unmodified. There is nothing to edit on the box.

## Admin

The first account created is not automatically an admin. From a logged-in
client, or via `bnbot`:

```
/set <account> BNET\auth\admin true
/set <account> BNET\auth\operator true
```

## Bot accounts

PvPGN has a plain-text bot protocol — this is how channel bots, moderation bots
and announce scripts connect, and it is much easier to script against than the
binary BNCS protocol.

```
/set <account> BNET\auth\botlogin true
```

Then connect to 6112 and send a `Ctrl-C` byte before anything else (that is the
handshake). `bnbot(1)`, shipped in the package and on `PATH`, is a stdin/stdout
reference client, mostly useful for confirming that botlogin is on:

```console
$ bnbot localhost
```

For anything real, script it — the protocol is line-oriented text. If you need
to appear as an actual game client rather than a chat bot, that is the binary
protocol instead: [`bncs.py`](https://github.com/Davnit/bncs.py) or
[`bncsutil`](https://github.com/BNETDocs/bncsutil), documented at
[bnetdocs.org](https://bnetdocs.org/).

## Version checking

`allow_bad_version` and `allow_unknown_version` are both on. The version-check
archives shipped with PvPGN are old, and a rejected client reports only "unable
to validate game version" with nothing useful in the journal. There is no ladder
here worth protecting from a patched client.

This also means a BWAPI-injected client is accepted — though see
`../bwapi/README.md` for why bots still cannot join a PvPGN game on their own.
