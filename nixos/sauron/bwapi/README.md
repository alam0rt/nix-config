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

## One-time setup

The images need a StarCraft 1.16.1 install, which is not redistributable and
which sc-docker's own mirror (`files.theabyss.ru`) no longer serves. Supply it
yourself:

```console
# zip of a 1.16.1 install — StarCraft.exe, *.mpq, characters/, etc. at the root
$ sudo cp starcraft.zip /srv/data/bwapi/starcraft.zip
$ sudo systemctl start bwapi-images.service
```

That pulls `ggaic/starcraft:java` (Wine + BWAPI 4.4.0 + bwheadless, published by
the SSCAIT group) and builds `starcraft:game` on top of it. `bwapi-install.service`
then downloads the SSCAI map pack and the precomputed BWTA terrain caches.

The base layers are pulled rather than rebuilt on purpose: sc-docker's
dockerfiles are `FROM ubuntu:xenial` and `apt-get update` against an EOL release
fails.

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
