# pi coding agent: package + personal extensions.
{
  config,
  inputs,
  lib,
  pkgs,
  ...
}: let
  yaml = pkgs.formats.yaml {};

  # `switchyard-spend`: OpenRouter's own accounting for the key, plus a
  # per-model split of Switchyard's traffic derived from the routing log.
  spend = pkgs.writeShellApplication {
    name = "switchyard-spend";
    runtimeInputs = [pkgs.python3 pkgs.sqlite.bin];
    text = ''exec python3 ${./switchyard-spend.py} "$@"'';
  };

  # Switchyard advisor-gate deployment.
  #
  # Every client-visible turn is served by the executor (a free Nemotron
  # Lightning); when it produces a terminal turn — a plan, or a claim that the
  # work is done — the gate buffers that turn and has the advisor (DeepSeek
  # V4.1 Flash) read the transcript and answer APPROVE or REDO. On REDO the
  # turn is discarded before the client ever sees it and the advisor's plan is
  # injected as feedback, so the paid model is only spent on verdicts, never on
  # serving tokens.
  #
  # Both ids are current OpenRouter slugs and both advertise `tools` in
  # supported_parameters, which the gate needs: its default trigger is the
  # executor's first turn *without* tool calls.
  routes = pkgs.writeText "switchyard-routes.toml" ''
    schema_version = 1

    [llm_clients.openrouter]
    format = "openai_chat"
    base_url = "https://openrouter.ai/api/v1"
    # No credential of its own: the proxy forwards the caller's `authorization`
    # header upstream, so OMP's existing OpenRouter login stays the only copy of
    # the key on this machine. (An openai_chat client forwards `authorization`;
    # a route configured this way is rejected if called through the Anthropic
    # API, which OMP does not do here.)
    forward_auth = true

    # Free tier, 1M context, 65k max completion. Rate limits are per-account
    # and per-day, so this route degrades to 429s rather than to a bill.
    [targets.executor]
    id = "nvidia/nemotron-3.5-lightning:free"
    llm_client = "openrouter"
    # Ask OpenRouter to report what it actually charged. Switchyard has no cost
    # concept of its own, but it passes `usage.cost` through untouched, so a
    # client sees the real figure for the turns it is served.
    extra_body = { usage = { include = true } }

    # $0.15/$0.60 per Mtok, and only consulted on gated turns.
    [targets.advisor]
    id = "deepseek/deepseek-v4.1-flash"
    llm_client = "openrouter"
    extra_body = { usage = { include = true } }

    [routes.advisor_gate]
    id = "advisor-gate"
    type = "advisor"
    executor_target = "executor"
    advisor_target = "advisor"
    # Upstream's benchmarked-best trio for agentic coding harnesses: skip the
    # early chatty turns, keep a mid-task checkpoint for an executor that
    # grinds without declaring completion, and allow a re-review after a REDO.
    max_reviews = 3
    gate_stall_turns = 30
    gate_min_tool_results = 3
    # No capability fields (context_window/tool_calling/reasoning/vision) here:
    # the docs on main list them as common route fields, but the pinned 0.2.0
    # advisor route rejects them outright. `--dry-run` catches it if that
    # changes on a version bump.
  '';
in {
  imports = [inputs.omp.homeManagerModules.default];

  programs.omp = {
    enable = true;
  };

  home.packages = [pkgs.switchyard spend];

  systemd.user.services.switchyard = lib.mkIf pkgs.stdenv.isLinux {
    Unit = {
      Description = "Switchyard LLM routing proxy (advisor gate)";
      After = ["network-online.target"];
      Wants = ["network-online.target"];
    };
    Service = {
      # Validates clients, targets and route construction without binding.
      ExecStartPre = "${pkgs.switchyard}/bin/switchyard-server --config ${routes} --dry-run";
      # The gate's consults are invisible downstream and /v1/stats is in-memory,
      # so the routing log is the only durable record of what the advisor cost.
      # StateDirectory creates and owns ~/.local/state/switchyard.
      StateDirectory = "switchyard";
      ExecStart = "${pkgs.switchyard}/bin/switchyard-server --config ${routes} --host 127.0.0.1 --port 4000 --routing-log-file %S/switchyard/routing.jsonl";
      Restart = "on-failure";
      RestartSec = 5;
    };
    Install.WantedBy = ["default.target"];
  };

  # OMP reaches the gate as an ordinary OpenAI-compatible provider. The route's
  # `id` is the model name, so the selector is `switchyard/advisor-gate` — pick
  # it with /model, or set it as a modelRoles entry in ~/.omp/agent/config.yml.
  #
  # config.yml is left runtime-managed (programs.omp.settings is unset), so
  # declaring it here would clobber the model roles OMP writes itself.
  home.file.".omp/agent/models.yml".source = yaml.generate "omp-models.yml" {
    providers.switchyard = {
      baseUrl = "http://127.0.0.1:4000/v1";
      api = "openai-completions";
      # `!cmd` runs the command and uses its trimmed stdout as the key (10s
      # timeout, cached for the process lifetime, failures negative-cached for
      # 30s). This reads the OpenRouter key back out of OMP's own credential
      # store, so `omp login` remains the single place it is set and a rotation
      # needs no change here. Read-only, so it is safe against a running OMP.
      #
      # The coupling is to OMP's private auth schema: if the `auth_credentials`
      # table or the `data` JSON shape changes on an update, this returns empty,
      # OMP omits the header, and OpenRouter 401s.
      apiKey = "!${pkgs.sqlite.bin}/bin/sqlite3 -readonly 'file:${config.home.homeDirectory}/.omp/agent/agent.db?mode=ro' \"select data ->> 'key' from auth_credentials where provider='openrouter' and credential_type='api_key' limit 1\"";
      # Injects `Authorization: Bearer <key>`, which forward_auth relays upstream.
      authHeader = true;
      models = [
        {
          id = "advisor-gate";
          name = "Nemotron Lightning + DeepSeek advisor";
          api = "openai-completions";
          reasoning = true;
          input = ["text"];
          contextWindow = 1000000;
          maxTokens = 65536;
          # Zero is the truth for the executor: the :free tier bills nothing.
          # It is not the truth for a session, because the advisor's DeepSeek
          # consults never reach OMP and so cannot appear in its token counts.
          # `switchyard-spend` is where the real number lives.
          cost = {
            input = 0;
            output = 0;
            cacheRead = 0;
            cacheWrite = 0;
          };
          compat = {
            # Nemotron Lightning does not list reasoning_effort among its
            # OpenRouter supported_parameters, and the localhost base URL means
            # OMP cannot detect the real upstream to decide this itself.
            supportsReasoningEffort = false;
          };
        }
      ];
    };
  };
}
