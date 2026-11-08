# Halo 3 servers (Project Reclaimer)

[Project Reclaimer](https://projectreclaimer.dev) is community multiplayer
for Halo 3 (and ODST, and early Reach, CE and Halo 2) on the PC files of
Halo: The Master Chief Collection. Since 0.10 its dedicated server is a
native Linux program, so `modules/nixos/reclaimer.nix` runs upstream's own
Linux setup: one `reclaimer.service` whose supervisor starts each server as
a process of its own, restarts any that stops, and runs the machine's
discovery master.

| Server                            | Port      | Plays                                                    |
| --------------------------------- | --------- | -------------------------------------------------------- |
| Jim's Hosting Services Rotation   | 49176/udp | `rotation` playlist (16 games), 16 players               |
| Jim's Hosting Services Big Team   | 49177/udp | `big-team` playlist (17 games), 127 players, waits for 2 |
| Jim's Hosting Services GravAttack | 49178/udp | GravAttack 09 only, free-for-all Slayer, 32 players      |
| discovery master                  | 49175/tcp+udp | the machine's Server Browser listing, NAT introductions |

Players find the servers in the in-game Server Browser (every server reports
to the project's public masters) or with Direct Connect to
`<sauron's public IP>:49176`.

## Game files (needed before anything starts)

The program has no game files. Until they are in place the servers log what
is missing and re-check every 15 seconds, so nothing needs restarting once
they land.

### Straight from Steam, on sauron

`reclaimer-fetch-game` downloads them with
[DepotDownloader](https://github.com/SteamRE/DepotDownloader), signed in
as a Steam account that owns MCC with Halo 3. It takes every MCC depot the
account owns and keeps only what servers need: `halo3/halo3.dll`,
`halo3/maps/` (every map, multiplayer and campaign, with their `.mapinfo`
files) and the game and map variant folders, about 10 GB. The other games
(ODST, Reach, CE, Halo 2) come too once named in
`services.reclaimer.fetchGames`. Run it as sam, who owns the folder, in a
real terminal: the first sign-in asks for the password and a Steam Guard
code or approval in the Steam app.

```sh
ssh sauron
reclaimer-fetch-game <steam account name>
```

Later runs reuse the saved login token and fetch only what changed;
`reclaimer-fetch-game <account> -validate` re-checks every file. It keeps
its own state in `.DepotDownloader/` inside the folder; leave it there.

Since 0.10 a Steam update to MCC no longer stops the servers: each keeps a
copy of the engine files it was built for in its own data folder. Only a
fresh server folder needs a Reclaimer release that knows MCC's current
build.

### Copied from a PC with the game

On a machine with MCC and Halo 3 installed through Steam (Proton is fine,
the layout is the same):

```sh
MCC="$HOME/.local/share/Steam/steamapps/common/Halo The Master Chief Collection"
rsync -a --info=progress2 --relative \
  "$MCC/./halo3/halo3.dll" \
  "$MCC/./halo3/maps" \
  sauron:/srv/share/public/games/halo3-reclaimer/
```

The servers play no sound, so `halo3/fmod` is not needed. The same folder is
on the `public` SMB/NFS share if that is easier than rsync.

Then watch the first real check, which is where a misspelt map or mode
name in a playlist would show up:

```sh
journalctl -fu reclaimer
```

## Router

Open on the UniFi gateway, forwarded to sauron: UDP 49176-49178, and
49175 on both TCP and UDP (0.10's master takes UDP too: server
registration and NAT introductions). sauron's own firewall already allows
them (`openFirewall`).

The public masters can hole-punch players through a router that does not
forward the game port, but not through every router and there is no relay,
so forwarding is still what makes the servers reliably reachable. `upnp` is
left off. Check from outside the LAN (a phone hotspot) with
`project-reclaimer --list-servers http://148.251.153.44:44340` from a
client: it lists what the public master knows, asked the way the Server
Browser asks, with ping.

## Versions

A server admits only players on exactly its own Reclaimer version, and 0.9
and 0.10 can't play together at all. Releases come out several times a
week, so the servers run from a writable copy of the program in
`/var/lib/reclaimer-home/program`, and `auto_update = true` replaces it with
each new stable release (checked at start and hourly); an update restarts
every server and ends games under way. That copy is seeded from
`pkgs/project-reclaimer-dedicated`: bumping that package replaces the copy
on the next start (`auto_update` brings back anything newer within the
hour). The program runs unpatched through nix-ld.

To hold a version, set `settings.auto_update = false` and pin the package.

## Day to day

`reclaimer` runs `project-reclaimer dedicated <command>` as the service user,
with the service's environment and mod folders (root needed; it uses
`systemd-run`):

```sh
sudo reclaimer status                          # every server: players, IDs, addresses, master
sudo reclaimer check                           # files, settings, playlists, ports
sudo reclaimer content guardian                # names maps/game types/variants go by
sudo reclaimer playlist show rotation          # a playlist's games and odds
sudo reclaimer ban <player ID|IP|CIDR> --reason "…" [--for 7d]
sudo reclaimer unban <target>
sudo reclaimer bans
sudo reclaimer vpn allow <player ID>           # VPN blocking is on by default
sudo reclaimer -s gravattack status            # one server's own view
sudo reclaimer -s rotation rcon players        # its remote console, from this machine
sudo reclaimer reload                          # apply dedicated.toml/playlist edits now
sudo systemctl restart reclaimer               # every server, ending games
```

Bans live in `/srv/data/reclaimer/bans.json` and apply to every server
within a second.

- Logs: `journalctl -u reclaimer` (every server, tagged with its name), and
  per server in `/srv/data/reclaimer/data/<server>/` (`server.log`,
  `server.previous.log`, `chat/<date>.log`); the master's in
  `data/master/master.log`.
- Config: `nixos/sauron/reclaimer/default.nix`. On switch,
  `reclaimer-config.service` copies `dedicated.toml`, the playlists and
  content into `/srv/data/reclaimer`, and the running servers apply the
  change by themselves (`auto_reload`): players stay in, playlist changes
  start from the next vote, and settings such as `port` restart only that
  server once it is empty. The journal shows `[reload]` lines with what
  changed, or why nothing did. If no reload appears, `sudo reclaimer
  reload` forces one. Only `public_address`, `bind_address`, `upnp`,
  `auto_update`, `[master]`, `[workshop]`, VPN lists, the folder paths,
  `coop_network` and the Forge palette settings restart reclaimer.service
  on switch.
- Admins: add player IDs (client: Settings → Online services → Your player
  ID) to `settings.admins`. Admins can `/kick` and `/ban` from chat. Since
  0.10, `status` and RCON events show players' network keys; either ID works
  in `admins` and bans.
- RCON is off. To turn it on, put `RECLAIMER_DEDICATED_RCON_PASSWORD=…` in an
  agenix secret and pass its path in `services.reclaimer.environmentFiles`;
  it then listens on 127.0.0.1 at each game port (TCP). `sudo reclaimer -s
  rotation rcon …` works without it; `pkgs.reclaimer-rcon` is the desktop
  console (through an SSH tunnel).
- Forge maps: drop the `.mvar` (or `.json`) in `maps/` here, list it in
  `services.reclaimer.content` as `"Maps/<file>"`, and name it the same way
  in a playlist entry. On switch it lands in `content/Maps` and the servers
  take it up from their next vote. A client's saved maps are in its player
  folder's `Maps` (`%LOCALAPPDATA%\ProjectReclaimer` on Windows,
  `~/.local/share/ProjectReclaimer` on Linux).

## Workshop mods

Two ways, and sauron is between them.

**Now: hand-fetched.** `workshop.items` lists the items;
`reclaimer-fetch-workshop <steam account>`, as sam, downloads them into
`/srv/share/public/games/halo3-reclaimer-mods/<item ID>`, mounted read-only
at `content/Mods/Fetched`. Restart the servers after adding or updating one
(`sudo systemctl restart reclaimer`). In playlists, name a mod map by its
name, never `workshop:<id>/…`: that form makes the server try to download
it, which fails without SteamCMD, and a failed download stops the start.
Players get mods through their own Steam and can't join while their copy
differs from the server's, so re-fetch when an author updates one.

**Next: the servers download them.** With SteamCMD the servers download
`workshop.items` themselves into
`/srv/share/public/games/halo3-reclaimer-workshop` (mounted at
`content/Mods/Workshop`), check Steam hourly for newer versions and swap one
in once the servers using it are empty. To switch:

1. Sign SteamCMD in once as the service user, with its home (an account
   that owns MCC; it asks for the password and Steam Guard once and keeps
   only a login token):

   ```sh
   sudo -u reclaimer -H steamcmd +login <steam account> +quit
   ```

   `steamcmd` is on the system path only once step 2 is switched in; until
   then use `nix run nixpkgs#steamcmd` the same way (with
   `NIXPKGS_ALLOW_UNFREE=1 … --impure`).
2. Check the share has room: the servers download every item again (about
   7 GB for the five listed) before step 3 frees the hand copies.
   In `default.nix` set `workshop.username = "<steam account>"` and
   `workshop.steamcmd.enable = true`, and switch. `journalctl -fu
   reclaimer` shows each item downloading; `sudo reclaimer check` lists
   their versions.
3. Remove the hand copies, so each mod is there once:
   `rm -rf /srv/share/public/games/halo3-reclaimer-mods/*` (as sam, or root
   for the ones fetched as root), then `sudo systemctl restart reclaimer`.
   Playlists may then name mod maps as `workshop:<id>/<map file>`
   (`sudo reclaimer mods` prints them).

## Moving from 0.9 (containers) to 0.10 (native)

0.10 loads the 0.9 server folder as it is: dedicated.toml, bans, admins,
playlists, content and `data/stats-key.json`. Each server makes a new
network key on its first start. The switch removes the old
`podman-reclaimer-*` units; afterwards, once `reclaimer.service` is up, the
0.9 Windows executables the containers kept can go:

```sh
sudo rm -rf /srv/data/reclaimer/.reclaimer
```
