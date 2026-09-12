{
  lib,
  writeShellApplication,
  openssh,
  tigervnc,
  coreutils,
  # Host running nixos/sauron/bwapi, reachable over SSH.
  botHost ? "sauron",
}:
# Launch a bot-vs-bot game on the bot host and watch it live over VNC.
#
# Nothing here involves PvPGN or your own StarCraft install: both players are
# containers on the far end, each rendering to its own VNC server. You are a
# spectator looking at one player's screen — StarCraft has no true observer
# mode in this setup, so you see the game through a player's fog of war.
writeShellApplication {
  name = "starcraft-watch";
  runtimeInputs = [openssh tigervnc coreutils];
  text = ''
    if [ $# -lt 2 ]; then
      echo "usage: starcraft-watch <bot> <bot> [map]" >&2
      echo "  e.g. starcraft-watch Locutus Steamhammer" >&2
      exit 2
    fi

    echo "starting $1 vs $2 on ${botHost}"
    ssh -f ${botHost} sudo bwapi-watch "$1" "$2" ''${3:+"$3"}

    # The containers need to boot Wine and StarCraft before anything is
    # listening; connecting too early just fails.
    echo "waiting for the VNC servers to come up"
    for _ in $(seq 1 60); do
      if timeout 2 bash -c "</dev/tcp/${botHost}/5900" 2>/dev/null; then
        break
      fi
      sleep 2
    done

    echo "opening viewers (5900 = $1, 5901 = $2)"
    vncviewer ${botHost}:5900 &
    vncviewer ${botHost}:5901 &
    wait
  '';

  meta = {
    description = "Watch a BWAPI bot-vs-bot game running on another host over VNC";
    mainProgram = "starcraft-watch";
    platforms = lib.platforms.linux;
    maintainers = [];
  };
}
