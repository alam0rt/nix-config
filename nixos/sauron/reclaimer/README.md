# Halo 3 servers (Project Reclaimer)

[Project Reclaimer](https://projectreclaimer.dev) is community multiplayer
for Halo 3 on the PC files of Halo: The Master Chief Collection. Its
dedicated server is a Windows program; this runs upstream's container image
(Wine + Xvfb inside) through `modules/nixos/reclaimer.nix`, with one podman
container per server, as upstream's own `compose.yaml` does.

| Server            | Container                    | Port      | Plays                                         |
| ----------------- | ---------------------------- | --------- | --------------------------------------------- |
| WankNet Rotation  | `podman-reclaimer-rotation`  | 49176/udp | `rotation` playlist, 16 players               |
| WankNet Big Team  | `podman-reclaimer-big-team`  | 49177/udp | `big-team` playlist, 24 players, waits for 4  |
| WankNet Co-op     | `podman-reclaimer-coop`      | 49178/udp | campaign from Sierra 117 on Heroic, 4 players |
| discovery master  | (first container up)         | 49175/tcp | the machine's Server Browser listing          |

Players find the servers in the in-game Server Browser (every server reports
to the project's public masters) or with Direct Connect to
`<sauron's public IP>:49176`.

## Game files (needed before anything starts)

The image has no game files. Until they are in place each container logs
what is missing and re-checks every 15 seconds, so nothing needs restarting
once they land.

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
files: what the playlists and the co-op server need, plus `campaign.map`
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
set `services.reclaimer.image` to a tag such as `…:0.9.11` and
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
sudo reclaimer -s coop status                  # one server's own view
```

Bans live in `/srv/data/reclaimer/bans.json` and apply to every server
within a second.

- Server and chat logs: `/srv/data/reclaimer/data/<server name>/`
  (`server.log`, `chat/<date>.log`), also in the journal per unit.
- Config: `nixos/sauron/reclaimer/default.nix`. A change rewrites
  `dedicated.toml` or the playlists in the store and restarts the containers
  on switch.
- Admins: add player IDs (client: Settings → Online services → Your player
  ID) to `settings.admins`. Admins can `/kick` and `/ban` from chat.
- RCON is off. To turn it on, put `RECLAIMER_DEDICATED_RCON_PASSWORD=…` in an
  agenix secret and pass its path in `services.reclaimer.environmentFiles`;
  it then listens on 127.0.0.1 at each game port (TCP), so use
  `sudo reclaimer -s rotation rcon players` or an SSH tunnel.
- Mods: copy mod folders into `/srv/data/reclaimer/content/Mods` and set
  `defaults.share_mods = true`. The image has no Steam, so `workshop:`
  references cannot download; name mod maps by name.
