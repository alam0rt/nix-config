{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.programs.pi;
  jsonFormat = pkgs.formats.json {};
in {
  options.programs.pi = {
    enable = mkEnableOption "pi AI coding agent";

    package = mkOption {
      type = types.package;
      default = pkgs.pi;
      description = "The pi package to use.";
    };

    settings = mkOption {
      type = jsonFormat.type;
      default = {};
      example = literalExpression ''
        {
          defaultProvider = "anthropic";
          defaultModel = "claude-sonnet-4-20250514";
          defaultThinkingLevel = "medium";
          theme = "dark";
          compaction = {
            enabled = true;
            reserveTokens = 16384;
          };
        }
      '';
      description = ''
        Global settings written to {file}`~/.pi/agent/settings.json`.
        See <https://github.com/earendil-works/pi/blob/main/packages/coding-agent/docs/settings.md>.
      '';
    };

    models = mkOption {
      type = jsonFormat.type;
      default = {};
      example = literalExpression ''
        {
          providers = {
            ollama = {
              baseUrl = "http://localhost:11434/v1";
              api = "openai-completions";
              apiKey = "ollama";
              models = [
                { id = "llama3.1:8b"; }
              ];
            };
          };
        }
      '';
      description = ''
        Custom model/provider configuration written to {file}`~/.pi/agent/models.json`.
        See <https://github.com/earendil-works/pi/blob/main/packages/coding-agent/docs/models.md>.
      '';
    };

    extensions = mkOption {
      type = types.listOf types.path;
      default = [];
      description = ''
        List of extension files or directories to symlink into
        {file}`~/.pi/agent/extensions/`.
      '';
    };

    skills = mkOption {
      type = types.listOf types.path;
      default = [];
      description = ''
        List of skill files or directories to symlink into
        {file}`~/.pi/agent/skills/`.
      '';
    };

    themes = mkOption {
      type = types.listOf types.path;
      default = [];
      description = ''
        List of theme files or directories to symlink into
        {file}`~/.pi/agent/themes/`.
      '';
    };

    prompts = mkOption {
      type = types.listOf types.path;
      default = [];
      description = ''
        List of prompt template files or directories to symlink into
        {file}`~/.pi/agent/prompts/`.
      '';
    };
  };

  config = mkIf cfg.enable {
    home.packages = [cfg.package];

    home.file = let
      mkLinks = prefix: paths:
        listToAttrs (imap0 (i: path: {
            name = ".pi/agent/${prefix}/${baseNameOf (toString path)}";
            value = {source = path;};
          })
          paths);
    in
      {}
      // (optionalAttrs (cfg.settings != {}) {
        ".pi/agent/settings.json".source = jsonFormat.generate "pi-settings.json" cfg.settings;
      })
      // (optionalAttrs (cfg.models != {}) {
        ".pi/agent/models.json".source = jsonFormat.generate "pi-models.json" cfg.models;
      })
      // (mkLinks "extensions" cfg.extensions)
      // (mkLinks "skills" cfg.skills)
      // (mkLinks "themes" cfg.themes)
      // (mkLinks "prompts" cfg.prompts);
  };
}
