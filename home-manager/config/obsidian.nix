{
  config,
  pkgs,
  ...
}: {
  # Obsidian, managed declaratively via home-manager.
  #
  # NOTE: nixpkgs does not package any Obsidian *community* plugins or themes,
  # so only core plugins + settings are configured declaratively here. Community
  # plugins (Dataview, Templater, Marp, Obsidian Git, ...) can still be installed
  # from inside Obsidian's own "Community plugins" browser as normal — they just
  # live in the vault rather than being pinned in Nix.
  programs.obsidian = {
    enable = true;
    # `obsidian-cli`, handy for scripting the vault from the shell.
    cli.enable = true;

    defaultSettings = {
      # Sensible appearance defaults.
      appearance = {
        theme = "obsidian"; # dark
        nativeMenus = false;
      };

      app = {
        # Good defaults for a knowledge base / LLM-maintained wiki.
        attachmentFolderPath = "raw/assets";
        newLinkFormat = "relative";
        useMarkdownLinks = true; # plain [text](path) links, friendlier to LLMs/git
        alwaysUpdateLinks = true;
        showUnsupportedFiles = true;
      };

      # Core (first-party) plugins — these ship with Obsidian itself and need no
      # packaging. Enabling the ones that suit a cross-referenced wiki workflow.
      corePlugins = [
        "file-explorer"
        "global-search"
        "switcher"
        "graph" # graph view — connections, hubs, orphans
        "backlink"
        "outgoing-link"
        "tag-pane"
        "properties"
        "page-preview"
        "templates"
        "note-composer"
        "command-palette"
        "slash-command"
        "editor-status"
        "bookmarks"
        "outline"
        "word-count"
        "file-recovery"
        "canvas"
      ];
    };

    # A single vault at ~/notes. `target` is relative to $HOME.
    vaults.notes.target = "notes";
  };
}
