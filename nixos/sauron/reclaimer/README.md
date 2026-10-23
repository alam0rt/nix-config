# Halo 3 servers (Project Reclaimer)

[Project Reclaimer](https://projectreclaimer.dev) is community multiplayer
for Halo 3 on the PC files of Halo: The Master Chief Collection. Its
dedicated server is a Windows program; this runs upstream's container image
(Wine + Xvfb inside) through `modules/nixos/reclaimer.nix`, with one podman
container per server, as upstream's own `compose.yaml` does.

| Server             | Container                     | Port      | Plays                                               |
| ------------------ | ----------------------------- | --------- | --------------------------------------------------- |
| WankNet Rotation   | `podman-reclaimer-rotation`   | 49176/udp | `rotation` playlist, 16 players                     |
| WankNet Big Team   | `podman-reclaimer-big-team`   | 49177/udp | `big-team` playlist, 24 players, waits for 4        |
| WankNet GravAttack | `podman-reclaimer-gravattack` | 49178/udp | GravAttack 09 only, free-for-all Slayer, 32 players |
| discovery master   | (first container up)          | 49175/tcp | the machine's Server Browser listing                |

Players find the servers in the in-game Server Browser (every server reports
to the project's public masters) or with Direct Connect to
`<sauron's public IP>:49176`.

## Game files (needed before anything starts)

The image has no game files. Until they are in place each container logs
what is missing and re-checks every 15 seconds, so nothing needs restarting
once they land.

### Straight from Steam, on sauron

`reclaimer-fetch-game` downloads them with
[DepotDownloader](https://github.com/SteamRE/DepotDownloader), signed in
as a Steam account that owns MCC with Halo 3. It takes every MCC depot the
account owns and keeps only `halo3/halo3.dll` and `halo3/maps/` (every map,
multiplayer and campaign, with their `.mapinfo` files), about 10 GB. Run it
as sam, who owns the folder, in a real terminal: the first sign-in asks for
the password and a Steam Guard code or approval in the Steam app.

```sh
ssh sauron
reclaimer-fetch-game <steam account name>
```

Later runs reuse the saved login token and fetch only what changed;
`reclaimer-fetch-game <account> -validate` re-checks every file. It keeps
its own state in `.DepotDownloader/` inside the folder; leave it there.

Running it again always takes MCC's newest build, so after a Steam update
to MCC, wait until a Reclaimer release supports it (servers on the new DLL
refuse to start before then) and only then re-run it.

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

That copies every map, multiplayer and campaign, with their `.mapinfo`
files: what the servers need, plus `campaign.map`
and `040_voi.map` for Forge maps with campaign vehicles and AI. The servers
play no sound, so `halo3/fmod` is not needed. The same folder is on the
`public` SMB/NFS share if that is easier than rsync.

After a Steam update to MCC, copy `halo3/halo3.dll` again once a Reclaimer
release supports the new build; `dedicated check` names the file when it does
not match.

Then watch the first real check, which is where a misspelt map or mode
name in a playlist would show up:

```sh
journalctl -fu podman-reclaimer-rotation
```

## Router

Open on the UniFi gateway, forwarded to sauron: UDP 49176-49178 and TCP
49175. sauron's own firewall already allows them (`openFirewall`).

Since 0.9.8 the public masters can hole-punch players through a router that
does not forward the game port, but not through every router and there is no
relay, so forwarding is still what makes the servers reliably reachable.
`upnp` is left off. Check from outside the LAN (a phone hotspot) with
`project-reclaimer.exe server-status <public IP>:49176` from the client.

## Versions

A server admits only players on exactly its own Reclaimer version, and
releases come out several times a week. So the image tag is `latest`,
checked against the registry whenever a container starts (`pull = "newer"`),
and `auto_update = true` installs new stable releases hourly in between.
An update restarts the servers and ends games under way. To hold a version,
set `services.reclaimer.image` to a tag such as `…:0.9.23` and
`settings.auto_update = false`.

## Day to day

`reclaimer` runs `dedicated <command>` inside a server's container (root
needed, the containers are rootful):

```sh
sudo reclaimer status                          # every server: players, IDs, addresses, master
sudo reclaimer ban <player ID|IP|CIDR> --reason "…" [--for 7d]
sudo reclaimer unban <target>
sudo reclaimer bans
sudo reclaimer vpn allow <player ID>           # VPN blocking is on by default
sudo reclaimer -s gravattack status            # one server's own view
sudo reclaimer reload                          # apply dedicated.toml/playlist edits now
```

Bans live in `/srv/data/reclaimer/bans.json` and apply to every server
within a second.

- Server and chat logs: `/srv/data/reclaimer/data/<server name>/`
  (`server.log`, `chat/<date>.log`), also in the journal per unit.
- Config: `nixos/sauron/reclaimer/default.nix`. On switch,
  `reclaimer-config.service` copies `dedicated.toml` and the playlists into
  `/srv/data/reclaimer`, and the running servers apply the change by
  themselves (Reclaimer 0.9.18+ `auto_reload`): players stay in, playlist
  changes start from the next vote, and settings such as `port` restart
  only that server once it is empty. The journal shows `Configuration
  reloaded.` and what changed, or why nothing did. If no reload appears,
  `sudo reclaimer reload` forces one. Only `public_address`,
  `auto_update`, `[master]`, `[workshop]`, VPN lists and the folder paths
  restart the containers on switch.
- Admins: add player IDs (client: Settings → Online services → Your player
  ID) to `settings.admins`. Admins can `/kick` and `/ban` from chat.
- RCON is off. To turn it on, put `RECLAIMER_DEDICATED_RCON_PASSWORD=…` in an
  agenix secret and pass its path in `services.reclaimer.environmentFiles`;
  it then listens on 127.0.0.1 at each game port (TCP), so use
  `sudo reclaimer -s rotation rcon players` or an SSH tunnel.
- Forge maps: drop the `.mvar` (or `.json`) in `maps/` here, list it in
  `services.reclaimer.content` as `"Maps/<file>"`, and name it the same way
  in a playlist entry. On switch it lands in `content/Maps` and the servers
  take it up from their next vote. A client's saved maps are under
  `Documents\My Games\Project Reclaimer\Maps`.
- Mods: copy mod folders into `/srv/data/reclaimer/content/Mods` and set
  `defaults.share_mods = true`. The image has no Steam, so `workshop:`
  references cannot download; name mod maps by name.
