# pi coding agent: package + personal extensions.
#
# Machine/provider-specific settings (model gateways, enabled models) are
# layered on top by the host config (e.g. private-flake's darwin.nix) via
# the same programs.pi-coding-agent options.
{outputs, ...}: {
  imports = [outputs.homeManagerModules.pi];

  programs.pi-coding-agent = {
    enable = true;
    extensions = [
      ./pi/extensions/auto-model.ts
      ./pi/extensions/ed-edit.ts
      ./pi/extensions/firefox-cookies.ts
      ./pi/extensions/kitty.ts
      ./pi/extensions/mcp.ts
    ];
  };
}
