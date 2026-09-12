# BWAPI bots on sauron

Runs StarCraft: Brood War 1.16.1 bots headless, in Wine, in podman containers,
driven by [`scbw`](https://github.com/basil-ladder/sc-docker).

## This is not connected to PvPGN

Worth being blunt about, because the two are easy to conflate:

**BWAPI bots cannot join a PvPGN server.** BWAPI's own `auto_menu` documents
`BATTLE_NET` as *"Automates the navigation to Battle.net. Beyond that this
feature is non-functional"*, and `bwheadless` — the thing that actually launches
a headless StarCraft — only implements the **LAN (UDP)** and **Local PC**
network providers. There is no Battle.net path.

So:

- `../pvpgn` is the chat/lobby/ladder server for **human** StarCraft clients.
- this module is a **bot ladder** that plays games on a private container
  network, and lets you play against a bot over VNC.

They share a version (1.16.1) and nothing else. If you want a bot in a PvPGN
lobby, someone has to drive the menus by hand.

## Setup

Nothing. `pkgs/starcraft-1161` fetches the game, so a switch is all it takes.

BWAPI requires StarCraft **1.16.1** exactly — patch 1.18 added anti-cheat that
breaks it, and Blizzard's free download is 1.18+ with no supported downgrade, so
"StarCraft is free now" does not get you there. What the package fetches is the
ICCup-derived install SSCAIT's tutorial has always pointed at, "hosted with
permission from Activision Blizzard", now at `davechurchill.ca` rather than the
`cs.mun.ca` URL SSCAIT still links (that one 404s).

It is pinned by hash and was cross-checked against PvPGN's own version table
before pinning: `conf/versioncheck.json.in` expects
`StarCraft.exe 01/09/09 22:57:43 1220608` for SEXP revision 0xd3 (Brood War
1.16.1), and the exe in the zip is exactly that.

`bwapi-images.service` builds the whole image chain — wine, bwapi, play, java,
then game — from [basil-ladder/sc-docker](https://github.com/basil-ladder/sc-docker),
the fork BASIL itself runs. Its dockerfiles are `FROM ubuntu:22.04` with
`winehq-stable`.

Do not be tempted by the prebuilt `ggaic/starcraft:*` images on Docker Hub. They
are from 2018, frozen at wine 2.20, and carry tournament modules for BWAPI
3.7.4-4.2.0 only. Every current SSCAIT bot is 4.4.0, and `play_bot.sh` runs
under `set -e` with an unguarded `cp $TM_DIR/$BOT_BWAPI.dll`, so a bot would die
with `cp: cannot stat '/app/tm/4.4.0.dll'` before writing a single line to its
log directory — leaving scbw to report only "some containers exited
prematurely". Building from the fork gets 4.4.0 in-tree.

`bwapi-install.service` then fetches the SSCAI map pack and BWTA caches — without
those, every bot re-analyses the map for the first minute of every game.

It is supposed to do that once. `pkgs/scbw` patches `_image_version_up_to_date()`
in `cli.py` to make that true: it compared image tags against the bare
`starcraft:game`, but podman reports a locally built image as
`localhost/starcraft:game`, so the check never matched and *every* `scbw.play`
re-ran the whole installer first — both map packs and both BWTA caches off
GitHub, about 7MB a game. It never failed, because `check_for_game_image()`
inside the installer found the image fine; it only ever showed up as a
`re-installing scbw package` warning in the journal.

## Playing against a bot

From the laptop:

```console
$ starcraft-vs Locutus
$ starcraft-vs 'Iron bot' T
```

Then host an ordinary LAN game with the name it prints — Multiplayer → Local
Area Network (UDP) → Create Game. The bot joins it.

This does **not** go through PvPGN. `bwheadless --lan-sendto` hooks
`ws2_32!sendto` and rewrites every outgoing destination to your address, so the
bot unicasts at you instead of broadcasting; that is what carries it across the
tailnet, which has no broadcast domain. The container runs with `--network
host`, not scbw's `sc_net` bridge, because the bridge SNATs and breaks the
return path from your client.

## Watching two bots fight

```console
$ starcraft-watch Locutus Steamhammer
```

Starts a rendered game here and opens a VNC viewer per player on the laptop —
5900 is the first bot, 5901 the second. There is no true observer mode, so each
viewer shows that player's screen, fog of war and all.

The VNC servers are unauthenticated (`x11vnc -nopw` inside the container), so
the firewall exposes 5900-5901 on the tailnet only. Never widen that.

`--auto_launch` is on, which drives the map-selection screen with xdotool to
work around sc-docker's "Unable to distribute map" bug; without it a headful
game sits in the lobby forever waiting for a human to pick the map.

If live watching misbehaves, the headless path is more reliable: the hourly
ladder saves a replay per game under
`/srv/data/bwapi/.scbw/games/<game>/`, and those open in a normal StarCraft.

## The ladder

`bwapi-ladder.timer` fires hourly and plays one game between two randomly
chosen bots on a random map. Replays and per-game logs land under
`/srv/data/bwapi/.scbw/games/`.

`--read_overwrite` is on, so bots that learn between games (most of the good
ones keep opponent-model data in their `read`/`write` directories) actually
accumulate knowledge instead of starting cold every time.

## Disk and retention

An untouched game directory is about 1.3MB, and almost none of it is the result:

| | Share of 21 games |
|---|---|
| `player_{0,1}.rep` | 56% |
| `write_{0,1}/` | 29% |
| `logs_*/unit_events.csv` | 11% |
| `logs_*/frames.csv` | 3% |
| `result.json` + `scores.json` | **0.09%** (30KB total) |

Bot replays are much larger than human ones — ~430KB average, 1.1MB for a long
game — because a `.rep` is a command stream and these bots sustain ~450 APM
each. At 24 games a day that is ~11GB a year.

`bwapi-prune` runs as the ladder's `ExecStopPost` and sweeps the whole tree:

- **finished game** — drops `player_1.rep` (the same game from the other seat;
  replays hold no per-player fog, so it is worth nothing), `write_{0,1}` and
  `logs_*/unit_events.csv`. Leaves ~400KB: one replay, `frames.csv`, the logs
  and the JSON.
- **finished, past 30 days** — drops the replay and logs too, keeping
  `result.json` and both `scores.json`. ~1.4KB, so every game's outcome is kept
  forever and the ladder table stays computable.
- **no `result.json`, past 7 days** — deleted. These are runs that died before
  scbw wrote a result (the journal has the failure) and `bwapi-join` /
  `bwapi-watch` directories, which never get one.

Deleting `write_{0,1}` is safe because `result.json` is written in `run_game`
only *after* `wait_for_containers` has done the `--read_overwrite` copy into
`bots/<name>/read`. A directory with a result has already had its learning data
folded back. `crashes_{0,1}` is removed with `rmdir`, never `rm -r`, so a real
crash dump survives.

Run it by hand with `bwapi-prune`; it is idempotent.

## Choosing bots

The ones configured in `default.nix` are all `AI_MODULE` bots — a single BWAPI
DLL the game loads itself. The other SSCAIT bot types work but need more care:

| Type | What it is | Notes |
|---|---|---|
| `AI_MODULE` | BWAPI DLL | Simplest. Everything here is one of these. |
| `EXE` | Standalone Windows binary using the BWAPI client API | Works, but it's a second process Wine has to keep alive. `Iron bot`, `krasi0`, `Monster`. |
| `JAVA_MIRROR` / `JAVA_JNI` | JVM bot + bridge DLL | Needs the 32-bit JVM in the image and a proxy started in the right order. |
| `jython` | Jython | Effectively unmaintained. |

Current strong bots on the SSCAIT ladder, by average score:

- **Iron bot** (T, `EXE`) — famously defensive, extremely hard to crack
- **BetaStar** (P), **Stardust** (P), **DaQin** (P) — modern Protoss
- **Locutus** (P) — the UAlbertaBot/Steamhammer lineage, well documented
- **Steamhammer** (Z) — the other big open-source codebase, good to read
- **BananaBrain** (P), **Crona** (Z), **WillyT** (T), **Brainiac** (R)

Add one by putting its name in the `bots` list; `scbw` resolves it against
`https://sscaitournament.com/api/bots.php` and downloads it on first use.
Names are fuzzy-matched, so `"Iron bot"` and `"iron"` both work.

**Bots are arbitrary binaries downloaded from the internet and run under Wine.**
The containers are the only isolation. Do not treat this as a hardened service.
