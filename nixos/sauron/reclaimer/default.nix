# Halo 3 multiplayer via Project Reclaimer. The module is
# modules/nixos/reclaimer.nix; README.md here covers getting the game files
# onto sauron, the router and day-to-day commands.
#
# The playlists began as a "best of" from the project's public match log
# (http://148.251.153.44:8790/v1/matches: 17,863 games on 790 servers,
# 2026-09-27 to 10-31), ranked by player-hours, with weights following each
# game's share there. 0.10's own modes and the four newer Workshop maps sit
# on top at weight 1-2. Both playlists were checked with `dedicated check`
# and `dedicated playlist show` on 0.10.1 against these game files and mods
# before going in.
{lib, ...}: let
  # Every server name and playlist starts with it; names stay within
  # Reclaimer's 48 characters.
  community = "Jim's Hosting Services";

  # Ready-to-flip servers for the other games; see README.md, "Other games".
  # Each needs that game's files first (`fetchGames`, then
  # `reclaimer-fetch-game`), and its playlist is only written once it is on,
  # so no unchecked file lands in playlists/.
  everyHalo = false;
  odstFirefight = false;

  # Only the ten base game types are installed (until the fetch of
  # halo3/*_variants lands), so the popular named variants are rebuilt from
  # options: team play, BR starts and score limits.
  teams = {"rounds.teams" = 1;};
  br = {
    "player.primary_weapon" = "Battle rifle";
    "player.secondary_weapon" = "Magnum";
  };

  game = map: game: extra: {inherit map game;} // extra;
  teamSlayer = map: extra:
    game map "Slayer" ({
        name = "Team Slayer";
        options = teams;
      }
      // extra);
in {
  services.reclaimer = {
    enable = true;

    # /srv/data is an hourly borg target with ~10G free; the game files are
    # ~7 GB of regenerable data, so they live on the public share.
    dataDir = "/srv/data/reclaimer";
    gameDir = "/srv/share/public/games/halo3-reclaimer";
    # Workshop mods, for the same reason: gigabytes each. Hand-fetched ones
    # (`reclaimer-fetch-workshop <steam account>`, as sam) until SteamCMD is
    # signed in; see README.md.
    modsDir = "/srv/share/public/games/halo3-reclaimer-mods";
    workshop = {
      # All five are fetched and in the playlists, named by their titles.
      items = [
        "2984061723" # Hugegrass: the most-played map of all, 18% of big games
        "3663541185" # Permafrost: the #2 mod map → big-team
        "3824657545" # Snowfort, titled "Avalanche 2Fort v1": 2Fort for 64-127 → big-team
        "3826615823" # Derelict: Halo CE remake → rotation
        "3824246444" # Ascension: Halo 2 remake → rotation
      ];
      # Where the servers' own Workshop downloads go once SteamCMD is on.
      dir = "/srv/share/public/games/halo3-reclaimer-workshop";
      # Off until SteamCMD has been signed in once as reclaimer (README.md,
      # "Workshop mods"): with it on and no sign-in, the downloads fail and
      # no server starts. Then set username and flip this.
      steamcmd.enable = false;
      # username = "<steam account>";
    };

    # Game ports are meant for the internet; the router forwards them too
    # (see README.md). RCON is not opened: it listens on 127.0.0.1 only.
    openFirewall = true;

    # Every server runs in reclaimer.service. Under 0.9 each had its own
    # container capped at 6g (rotation, big-team) and 3g (gravattack): rotation
    # hit 3g 9,456 times in its first week, and Hugegrass is a 2 GB map loaded
    # while up to 127 play. 0.10.1 measured ~1.2 GB a server idle on sauron,
    # so the ceiling is the old caps' sum plus headroom. sauron has ~36 GB
    # free.
    serviceConfig.MemoryMax = "18G";

    settings = {
      host_name = community;

      # Player IDs (64 hex characters, in the client under Settings → Online
      # services → Your player ID) who may kick and ban on every server.
      admins = [];
      # The Mod role: kick, mute, and bans of up to an hour
      # (moderator_ban_minutes), on every server. Player IDs, as for admins.
      moderators = [];
      # The VIP role: players here wait in the join queue's VIP line, which
      # gets 75% of the places that open on a full server (vip_priority).
      # Big Team has no queue: its 127 players take every place there is.
      roles.vip.players = [];

      defaults = {
        max_players = 16;
        # Players get Workshop mods through their own Steam.
        share_mods = false;

        # 60 ticks (the default) everywhere: sauron has 32 cores and sat at a
        # load of ~2 with the 0.9 servers running. tick_rate = 30 halves a
        # server's simulation if that ever changes.

        # Every game recorded as a film any player's Theater plays, in
        # /srv/data/reclaimer/data/<server>/films (excluded from borg below).
        # Each server keeps its newest 10 within 1 GB, so the three cost at
        # most 3 GB of /srv/data's ~10 GB free; each server switched on
        # below adds up to 1 GB more.
        film_recording = true;
        film_keep = 10;
        film_max_mb = 1024;
      };
    };

    # sam's Forge maps. Each plays on whichever base map it was made on,
    # which the game folder already has (every multiplayer map).
    content = {
      "Maps/GravAttack_09.mvar" = ./maps/GravAttack_09.mvar;
    };

    playlists =
      {
        # Games of up to 16. Guardian free-for-all and The Pit lead there;
        # BR-start CTF and team BR stand in for the HARDCORE CTF/TS variants
        # that top small games.
        rotation = {
          version = 2;
          name = "${community} Rotation";
          vote_seconds = 20;
          games = [
            (game "Guardian" "Slayer" {weight = 3;})
            (teamSlayer "The Pit" {weight = 3;})
            (teamSlayer "Narrows" {weight = 2;})
            (game "Heretic" "Slayer" {
              weight = 2;
              name = "Team BR";
              options = teams // br;
              rules.score_to_win = 50;
            })
            (teamSlayer "Guardian" {})
            (teamSlayer "Valhalla" {})
            (teamSlayer "Last Resort" {})
            (teamSlayer "Standoff" {})
            (game "The Pit" "Capture the Flag" {
              weight = 2;
              name = "BR CTF";
              options = br;
            })
            (game "Narrows" "Capture the Flag" {
              weight = 2;
              name = "BR CTF";
              options = br;
            })
            (game "Heretic" "Capture the Flag" {
              name = "BR CTF";
              options = br;
            })
            (game "Foundry" "Infection" {weight = 2;})
            (game "Construct" "King of the Hill" {
              name = "Team King";
              options = teams;
            })
            (game "Guardian" "Oddball" {
              name = "Team Oddball";
              options = teams;
            })
            (game "Heretic" "Slayer" {})
            (game "Maps/GravAttack_09.mvar" "Slayer" {name = "GravAttack";})

            # Modes that come with 0.10 (content/Game Modes/Project
            # Reclaimer, written by the servers' first check), on small maps.
            # Flood Infection plays the campaign's Flood from 050_floodvoi.map,
            # which the game folder has.
            (game "The Pit" "Gun Game" {})
            (game "Guardian" "One in the Chamber" {})
            (game "Construct" "Growth" {})
            (game "Heretic" "Zone Control" {})
            (game "Last Resort" "Flood Infection" {})

            # Workshop mods (workshop.items), named by their titles.
            (teamSlayer "Derelict" {})
            (teamSlayer "Ascension" {})
            (game "Ascension" "Capture the Flag" {
              name = "BR CTF";
              options = br;
            })
          ];
        };

        # Games of 24 and up. Hugegrass CTF alone is 15% of big-game
        # player-hours; then team slayer on the classic big maps, the faction
        # battle, Sandtrap Infection and objective games on Valhalla,
        # Avalanche and High Ground.
        big-team = {
          version = 2;
          name = "${community} Big Team";
          vote_seconds = 20;
          games = [
            # Workshop mods (workshop.items), named by their titles: a
            # workshop: reference would make the server try to download it,
            # which fails until workshop.steamcmd is on.
            (game "Hugegrass" "Capture the Flag" {weight = 6;})
            (teamSlayer "Hugegrass" {weight = 2;})
            (teamSlayer "Valhalla" {weight = 3;})
            # 0.10 replaced 0.9's "UNSC vs Covenant" (whose "first to 50"
            # topped big-team play) with this class-based battle of three
            # factions: a faction with no players sits out, any two start it,
            # and the one with the most reinforcements left after ten minutes
            # wins. No score limit: one would end the battle on kills. Its own
            # settings (reinforcements, length) can't be set from a playlist.
            (game "Valhalla" "UNSC vs Covenant vs Flood" {weight = 2;})
            (game "Valhalla" "Capture the Flag" {weight = 2;})
            (game "Valhalla" "Assault" {})
            (teamSlayer "Sandtrap" {weight = 3;})
            (game "Sandtrap" "UNSC vs Covenant vs Flood" {weight = 2;})
            (game "Sandtrap" "Infection" {weight = 2;})
            (game "Sandtrap" "Assault" {})
            (teamSlayer "Avalanche" {weight = 2;})
            (game "Avalanche" "Capture the Flag" {})
            (game "Avalanche" "Assault" {})
            (game "High Ground" "Capture the Flag" {weight = 2;})
            (teamSlayer "High Ground" {})
            (teamSlayer "Rat's Nest" {})
            (teamSlayer "Standoff" {})

            # 0.10's Conquest (tickets, squads, five classes, deploy on the
            # map's territories) and Flood Infection, on big maps.
            (game "Valhalla" "Conquest" {weight = 2;})
            (game "Sandtrap" "Conquest" {})
            (game "High Ground" "Flood Infection" {})

            # The newer Workshop maps. Snowfort's map is titled "Avalanche
            # 2Fort v1".
            (game "Permafrost" "Capture the Flag" {weight = 2;})
            (teamSlayer "Permafrost" {})
            (game "Avalanche 2Fort v1" "Capture the Flag" {weight = 2;})
            (teamSlayer "Avalanche 2Fort v1" {})
          ];
        };
      }
      # Map and game names as upstream's guide gives them; check with `sudo
      # reclaimer playlist show every-halo` once the files are in.
      // lib.optionalAttrs everyHalo {
        every-halo = {
          version = 2;
          name = "${community} Every Halo";
          vote_seconds = 20;
          games = [
            (teamSlayer "Guardian" {})
            (game "Valhalla" "Capture the Flag" {})
            (game "Sword Base" "headhunter_054" {})
            (game "Blood Gulch" "ctf" {})
            (game "halo2_lockout" "slayer" {})
          ];
        };
      };

    servers = {
      rotation = {
        name = "${community} Rotation";
        port = 49176;
        playlist = "playlists/rotation.playlist.json";
        # Halo 3's own networking for small games (0.10.1's default too).
        network_model = "classic";
        metrics_http = "127.0.0.1:9310";
        welcome = "Welcome to ${community}, {name}! Vote for the next game in the lobby.";
      };

      big-team = {
        name = "${community} Big Team";
        port = 49177;
        playlist = "playlists/big-team.playlist.json";
        # Reclaimer's ceiling (since 0.9.6). Upstream hasn't measured a full
        # 127; a 63-player game takes about a core and 30 Mbit/s up. At 127
        # there are no join queue places left over (the queue shares them).
        max_players = 127;
        # At 4 it never started a game in its first week: everyone who
        # joined arrived alone.
        min_players = 2;
        # Built for big games: updates sent by the error each player would
        # see, which upstream measured halving a player's download at 64.
        network_model = "enhanced";
        metrics_http = "127.0.0.1:9311";
        welcome = [
          "Welcome to ${community} Big Team, {name}!"
          "CTF, Slayer, Conquest and the faction battle rotate; a game starts once two are in."
        ];
      };

      # Just GravAttack, over and over. A playlist needs three different
      # games, so this is one map and game type instead. The map is made
      # for 2-6; 32 is on purpose.
      gravattack = {
        name = "${community} GravAttack";
        port = 49178;
        map = "Maps/GravAttack_09.mvar";
        game = "Slayer";
        max_players = 32;
        network_model = "classic";
        metrics_http = "127.0.0.1:9312";
        welcome = "Welcome to ${community} GravAttack, {name}! One map, forever.";
      };

      # Halo 3, Reach, CE and Halo 2 maps in one rotation, each game's maps
      # by their own rules. Needs fetchGames = ["halo3" "reach" "halo1"
      # "halo2"] and a reclaimer-fetch-game run; players without a game the
      # playlist needs are told as they join. Port 49179 is past the
      # router's forward; see README.md.
      every-halo = {
        enable = everyHalo;
        name = "${community} Every Halo";
        port = 49179;
        playlist = "playlists/every-halo.playlist.json";
        network_model = "classic";
        metrics_http = "127.0.0.1:9313";
      };

      # Halo 3: ODST Firefight on Crater (Night), the classic game type, for
      # up to 16 (ODST's limit). Needs "odst" in fetchGames.
      odst-firefight = {
        enable = odstFirefight;
        name = "${community} ODST Firefight";
        port = 49180;
        odst = {
          mode = "firefight";
          mission = 5000;
          insertion = 7;
          variant = "odst_ff_classic";
          difficulty = "heroic";
        };
        metrics_http = "127.0.0.1:9314";
      };
    };
  };

  # Somewhere for the game files to land, writable by sam over the share.
  # Made before the servers start, which can't mount a missing mod folder.
  # Not tmpfiles: it refuses to create anything under /srv/share/public
  # (nobody) → games (sam), an "unsafe path transition".
  systemd.services.reclaimer-config.preStart = ''
    install -d -m 2755 -o sam -g nogroup /srv/share/public/games/halo3-reclaimer
    install -d -m 2755 -o sam -g nogroup /srv/share/public/games/halo3-reclaimer-mods
  '';

  # Server and chat logs (server.log, server.previous.log, chat/*.log) are
  # excluded by the *.log pattern; the full log kept past 20 MB isn't. Films
  # are the servers' own rolling record (capped above), not worth backing up.
  services.borgbackup.jobs.mordor-srv-data.exclude = [
    "/srv/data/reclaimer/data/*/server.log.old"
    "/srv/data/reclaimer/data/*/films"
  ];
}
