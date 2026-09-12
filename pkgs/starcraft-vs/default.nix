{
  lib,
  writeShellApplication,
  openssh,
  tailscale,
  coreutils,
  # Host running nixos/sauron/bwapi, reachable over SSH.
  botHost ? "sauron",
}:
# Start a game against a BWAPI bot from the command line.
#
# The bot does NOT come in over PvPGN — BWAPI has no working Battle.net path
# (see nixos/sauron/bwapi/README.md). You host an ordinary LAN game; the bot
# runs on the bot host and joins it directly, because bwheadless --lan-sendto
# rewrites its outgoing packets to unicast at you instead of broadcasting.
# That is what lets it cross the tailnet, which has no broadcast domain.
writeShellApplication {
  name = "starcraft-vs";
  runtimeInputs = [openssh tailscale coreutils];
  text = ''
        bot="''${1:-}"
        if [ -z "$bot" ]; then
          echo "usage: starcraft-vs <bot> [race]" >&2
          echo "  e.g. starcraft-vs Locutus" >&2
          echo "       starcraft-vs 'Iron bot' T" >&2
          exit 2
        fi
        race="''${2:-}"

        # The address the bot will unicast to. Must be the tailnet IP: the
        # container on the bot host has no route to anything else of ours.
        me=$(tailscale ip -4)
        game="vs-$(id -un)-$RANDOM"

        echo "asking ${botHost} to send '$bot' to $me"
        ssh -f ${botHost} sudo bwapi-join \
          --bot "$bot" --sendto "$me" --game "$game" \
          ''${race:+--race "$race"}

        cat <<EOF

      The bot is starting up. In StarCraft:

        Multiplayer  ->  Local Area Network (UDP)  ->  Create Game

        Game name:  $game
        Map:        anything in maps/sscai or maps/BroodWar

      It takes a few seconds to appear. Logs on ${botHost}:
        /srv/data/bwapi/.scbw/games/$game/logs/

    EOF
  '';

  meta = {
    description = "Start a StarCraft game against a BWAPI bot running on another host";
    mainProgram = "starcraft-vs";
    platforms = lib.platforms.linux;
    maintainers = [];
  };
}
