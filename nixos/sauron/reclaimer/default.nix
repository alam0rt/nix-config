# Halo 3 multiplayer via Project Reclaimer. The module is
# modules/nixos/reclaimer.nix; README.md here covers getting the game files
# onto sauron, the router and day-to-day commands.
#
# The playlists are a "best of" from the project's public match log
# (http://148.251.153.44:8790/v1/matches: 17,863 games on 790 servers,
# 2026-09-27 to 10-31), ranked by player-hours. Weights follow each game's
# share there. Both were checked with `dedicated playlist show` against
# these game files and mods before going in.
{...}: let
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

    # /srv/data is an hourly borg target with ~11G free; the game files are
    # ~7 GB of regenerable data, so they live on the public share.
    dataDir = "/srv/data/reclaimer";
    gameDir = "/srv/share/public/games/halo3-reclaimer";
    # Workshop mods, for the same reason: gigabytes each.
    # `reclaimer-fetch-workshop <steam account>` (as sam) fills it.
    modsDir = "/srv/share/public/games/halo3-reclaimer-mods";
    workshopItems = [
      "2984061723" # Hugegrass: the most-played map of all, 18% of big games
      "3663541185" # Permafrost: the #2 mod map; joins big-team once fetched
    ];

    # Game ports are meant for the internet; the router forwards them too
    # (see README.md). RCON is not opened: it listens on 127.0.0.1 only.
    openFirewall = true;

    settings = {
      # Same name as the PvPGN server (nixos/sauron/pvpgn).
      host_name = "WankNet";

      # Player IDs (64 hex characters, in the client under Settings → Online
      # services → Your player ID) who may kick and ban on every server.
      admins = [];

      defaults = {
        max_players = 16;
        # Players get Workshop mods through their own Steam.
        share_mods = false;
      };
    };

    # sam's Forge maps. Each plays on whichever base map it was made on,
    # which the game folder already has (every multiplayer map).
    content = {
      "Maps/GravAttack_09.mvar" = ./maps/GravAttack_09.mvar;
    };

    playlists = {
      # Games of up to 16. Guardian free-for-all and The Pit lead there;
      # BR-start CTF and team BR stand in for the HARDCORE CTF/TS variants
      # that top small games.
      rotation = {
        version = 2;
        name = "WankNet Rotation";
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
        ];
      };

      # Games of 24 and up. Hugegrass CTF alone is 15% of big-game
      # player-hours; then team slayer on the classic big maps, "UNSC vs
      # Covenant 50" (the top big-team variant), Sandtrap Infection and
      # objective games on Valhalla, Avalanche and High Ground.
      big-team = {
        version = 2;
        name = "WankNet Big Team";
        vote_seconds = 20;
        games = [
          # Workshop mod (workshopItems), named by its title: a workshop:
          # reference would make the server try to download it.
          (game "Hugegrass" "Capture the Flag" {weight = 6;})
          (teamSlayer "Hugegrass" {weight = 2;})
          (teamSlayer "Valhalla" {weight = 3;})
          (game "Valhalla" "UNSC vs Covenant" {
            weight = 2;
            name = "UNSC vs Covenant 50";
            rules.score_to_win = 50;
          })
          (game "Valhalla" "Capture the Flag" {weight = 2;})
          (game "Valhalla" "Assault" {})
          (teamSlayer "Sandtrap" {weight = 3;})
          (game "Sandtrap" "UNSC vs Covenant" {
            weight = 2;
            name = "UNSC vs Covenant 50";
            rules.score_to_win = 50;
          })
          (game "Sandtrap" "Infection" {weight = 2;})
          (game "Sandtrap" "Assault" {})
          (teamSlayer "Avalanche" {weight = 2;})
          (game "Avalanche" "Capture the Flag" {})
          (game "Avalanche" "Assault" {})
          (game "High Ground" "Capture the Flag" {weight = 2;})
          (teamSlayer "High Ground" {})
          (teamSlayer "Rat's Nest" {})
          (teamSlayer "Standoff" {})
        ];
      };
    };

    servers = {
      rotation = {
        name = "WankNet Rotation";
        port = 49176;
        playlist = "playlists/rotation.playlist.json";
        # It hit a 3g cap 9,456 times in its first week (no OOM kill, but
        # 1.2 GB pushed to swap); sauron has ~36 GB free.
        extraOptions = ["--memory=6g"];
      };

      big-team = {
        name = "WankNet Big Team";
        port = 49177;
        playlist = "playlists/big-team.playlist.json";
        # Reclaimer's ceiling (since 0.9.6). Upstream hasn't measured a full
        # 127; a 63-player game takes about a core and 30 Mbit/s up.
        max_players = 127;
        # At 4 it never started a game in its first week: everyone who
        # joined arrived alone.
        min_players = 2;
        # Hugegrass is a 2 GB map, loaded while up to 127 play.
        extraOptions = ["--memory=6g"];
      };

      # Just GravAttack, over and over. A playlist needs three different
      # games, so this is one map and game type instead. The map is made
      # for 2-6; 32 is on purpose.
      gravattack = {
        name = "WankNet GravAttack";
        port = 49178;
        map = "Maps/GravAttack_09.mvar";
        game = "Slayer";
        max_players = 32;
        extraOptions = ["--memory=3g"];
      };
    };
  };

  # Somewhere for the game files to land, writable by sam over the share.
  # Made before the containers start, which can't mount a missing folder.
  # Not tmpfiles: it refuses to create anything under /srv/share/public
  # (nobody) → games (sam), an "unsafe path transition".
  systemd.services.reclaimer-config.preStart = ''
    install -d -m 2755 -o sam -g nogroup /srv/share/public/games/halo3-reclaimer
    install -d -m 2755 -o sam -g nogroup /srv/share/public/games/halo3-reclaimer-mods
  '';

  # The executable copies auto-update keeps (one per container) are
  # re-downloaded on demand. Server and chat logs are excluded by the *.log
  # pattern; their rotated copies aren't.
  services.borgbackup.jobs.mordor-srv-data.exclude = [
    "/srv/data/reclaimer/.reclaimer"
    "/srv/data/reclaimer/data/*/server.log.old"
  ];
}
