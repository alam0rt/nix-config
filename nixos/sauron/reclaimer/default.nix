# Halo 3 multiplayer via Project Reclaimer. The module is
# modules/nixos/reclaimer.nix; README.md here covers getting the game files
# onto sauron, the router and day-to-day commands.
{...}: let
  # Team Slayer is Slayer with teams on: the server knows only the base modes
  # (Slayer, Capture the Flag, King of the Hill, Oddball, Territories,
  # Assault, Juggernaut, Infection, VIP) plus its scripted ones (Gun Game,
  # Growth, One in the Chamber, Zone Control, Flood Infection), and the named
  # matchmaking variants need halo3/hopper_game_variants from the game.
  teamSlayer = map: {
    inherit map;
    game = "Slayer";
    name = "Team Slayer";
    options."rounds.teams" = 1;
  };
in {
  services.reclaimer = {
    enable = true;

    # /srv/data is an hourly borg target with ~12G free; the game files are
    # 5-10 GB of regenerable data, so they live on the public share, where
    # they can be copied in over SMB/NFS from a machine with MCC installed.
    dataDir = "/srv/data/reclaimer";
    gameDir = "/srv/share/public/games/halo3-reclaimer";

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
        # Mods would need share_mods or a Workshop source; none are hosted yet.
        share_mods = false;
      };
    };

    # sam's Forge maps. Each plays on whichever base map it was made on,
    # which the game folder already has (every multiplayer map).
    content = {
      "Maps/GravAttack_09.mvar" = ./maps/GravAttack_09.mvar;
    };

    playlists = {
      rotation = {
        version = 2;
        name = "WankNet Rotation";
        vote_seconds = 20;
        games = [
          {
            map = "Guardian";
            game = "Slayer";
            weight = 2;
          }
          (teamSlayer "The Pit")
          (teamSlayer "Snowbound")
          {
            map = "Valhalla";
            game = "Capture the Flag";
          }
          {
            map = "Narrows";
            game = "Capture the Flag";
          }
          {
            map = "Last Resort";
            game = "King of the Hill";
          }
          {
            map = "Construct";
            game = "Oddball";
          }
          {
            # Forge map for 2-6 players: free-for-all.
            map = "Maps/GravAttack_09.mvar";
            game = "Slayer";
            name = "GravAttack";
          }
          {
            map = "Guardian";
            game = "Slayer";
            name = "BR Slayer";
            options = {
              "player.primary_weapon" = "Battle rifle";
              "player.secondary_weapon" = "Magnum";
            };
          }
        ];
      };

      big-team = {
        version = 2;
        name = "WankNet Big Team";
        vote_seconds = 20;
        games = [
          {
            map = "Valhalla";
            game = "Capture the Flag";
            weight = 2;
          }
          (teamSlayer "Valhalla")
          (teamSlayer "Sandtrap")
          {
            map = "Sandtrap";
            game = "Assault";
          }
          {
            map = "Standoff";
            game = "Territories";
          }
          {
            map = "Avalanche";
            game = "Capture the Flag";
          }
        ];
      };
    };

    servers = {
      rotation = {
        name = "WankNet Rotation";
        port = 49176;
        playlist = "playlists/rotation.playlist.json";
        extraOptions = ["--memory=3g"];
      };

      big-team = {
        name = "WankNet Big Team";
        port = 49177;
        playlist = "playlists/big-team.playlist.json";
        max_players = 24;
        # Valhalla with two people in it is not big team.
        min_players = 4;
        extraOptions = ["--memory=3g"];
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
  '';

  # The executable copies auto-update keeps (one per container) are
  # re-downloaded on demand. Server and chat logs are already excluded by
  # the *.log pattern.
  services.borgbackup.jobs.mordor-srv-data.exclude = ["/srv/data/reclaimer/.reclaimer"];
}
