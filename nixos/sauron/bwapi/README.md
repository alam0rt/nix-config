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

`bwapi-images.service` pulls `ggaic/starcraft:java` (Wine + BWAPI 4.4.0 +
bwheadless, published by the SSCAIT group) and builds `starcraft:game` on top.
The base layers are pulled rather than rebuilt because sc-docker's dockerfiles
are `FROM ubuntu:xenial` and `apt-get update` fails on an EOL release.
`bwapi-install.service` then fetches the SSCAI map pack and BWTA caches — without
those, every bot re-analyses the map for the first minute of every game.

## Playing against a bot

```console
$ sudo scbw --bots "Locutus" --human --map "sscai/(4)Circuit Breaker.scx"
```

This starts a headful container with a VNC server on `:5900`. Connect over the
tailnet, pick your race, and the bot joins. Expect it to feel sluggish — you are
playing over VNC into Wine.

## The ladder

`bwapi-ladder.timer` fires hourly and plays one game between two randomly
chosen bots on a random map. Replays and per-game logs land under
`/srv/data/bwapi/.scbw/games/`.

`--read_overwrite` is on, so bots that learn between games (most of the good
ones keep opponent-model data in their `read`/`write` directories) actually
accumulate knowledge instead of starting cold every time.

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
