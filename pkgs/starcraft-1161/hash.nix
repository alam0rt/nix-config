# sha256 of your own Starcraft_1161.zip, or null.
#
# This is the single place to set it. Both consumers import this file:
#   nixos/sauron/bwapi   — builds the container image the bot ladder plays in
#   nixos/laptop/starcraft.nix — the Wine launcher for playing it yourself
# Each is mkIf'd out while this is null, so nothing is defined and nothing fails.
#
# To fill it in:
#   nix-store --add-fixed sha256 Starcraft_1161.zip
#   sha256sum Starcraft_1161.zip
#
# See ./default.nix for what the zip must contain and why the free 1.18
# download will not do.
null
