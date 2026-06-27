{...}: {
  programs.firefox = {
    enable = true;
    configPath = ".mozilla/firefox";

    # Enterprise policies — force-installs the Obsidian Web Clipper from AMO.
    # This avoids having to package the extension; Firefox fetches and keeps it
    # updated itself. `installation_mode = "normal_installed"` lets the user
    # disable/remove it if they ever want to.
    policies = {
      ExtensionSettings = {
        "clipper@obsidian.md" = {
          installation_mode = "normal_installed";
          install_url = "https://addons.mozilla.org/firefox/downloads/latest/web-clipper-obsidian/latest.xpi";
        };
      };
    };
  };
}
