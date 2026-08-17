{
  config,
  lib,
  ...
}: let
  # ---------------------------------------------------------------------
  # Fill these in and flip `enable` to turn on Matrix alert delivery.
  #
  # The bot account lives in MAS on the omar cluster, not in Synapse itself,
  # so it is created and re-tokened with mas-cli:
  #   kubectl exec -n matrix deploy/mas -- mas-cli manage \
  #     issue-compatibility-token -c /config.yaml gandalfbot alertmanager
  # The compat token is what the client-server API accepts; store it with
  #   nix run '.#agenix-rekey.x86_64-linux.edit-view' -- \
  #     nixos/sauron/monitoring/matrix-alertmanager-token.age
  # The webhook shared secret is generated automatically by agenix-rekey.
  #
  # The bot cannot join an invite-only room on its own — it has to be invited
  # by a member first, or delivery fails with M_FORBIDDEN.
  #
  # With `enable = false`, alerts are still evaluated and grouped but are
  # only visible in the Alertmanager and Grafana UIs.
  # ---------------------------------------------------------------------
  matrix = {
    enable = true;
    homeserverUrl = "https://chat.samlockart.com";
    # Shared with maubot. The `alertmanager` device below is a separate
    # session, so revoking it does not log maubot out.
    user = "@gandalfbot:chat.samlockart.com";
    roomId = "!VnfJuvbBRnyruscIFx:chat.samlockart.com";
    # Grafana already owns 3000, which is this module's default.
    port = 9535;
  };

  # Alertmanager receiver names double as the routing key for the bridge:
  # matrix-alertmanager picks the room from the `receiver` field of the
  # webhook payload.
  receivers = ["critical" "warning" "watchdog"];

  webhookFor = name: {
    inherit name;
    webhook_configs = [
      {
        url = "http://127.0.0.1:${toString matrix.port}/alerts";
        max_alerts = 0;
        send_resolved = true;
        http_config.basic_auth = {
          username = "alertmanager";
          # Passing the secret this way keeps it out of the Nix store; the
          # bridge accepts it as the basic-auth password or a ?secret= query.
          password_file = config.age.secrets.matrix-alertmanager-secret.path;
        };
      }
    ];
  };
in {
  age.secrets = lib.mkIf matrix.enable {
    matrix-alertmanager-token = {
      rekeyFile = ./matrix-alertmanager-token.age;
      mode = "0400";
      owner = "root";
    };
    matrix-alertmanager-secret = {
      rekeyFile = ./matrix-alertmanager-secret.age;
      generator.script = "alnum";
      mode = "0400";
      owner = "root";
    };
  };

  services.matrix-alertmanager = lib.mkIf matrix.enable {
    enable = true;
    inherit (matrix) port;
    homeserverUrl = matrix.homeserverUrl;
    matrixUser = matrix.user;
    tokenFile = config.age.secrets.matrix-alertmanager-token.path;
    secretFile = config.age.secrets.matrix-alertmanager-secret.path;
    # Every receiver posts to the same room; split this list if you later want
    # criticals somewhere noisier than warnings.
    matrixRooms = [
      {
        inherit (matrix) roomId;
        inherit receivers;
      }
    ];
  };

  services.prometheus.alertmanager.configuration = {
    route = {
      receiver = "warning";
      group_by = ["alertname" "severity"];
      group_wait = "30s";
      group_interval = "5m";
      repeat_interval = "4h";
      routes = [
        {
          # The heartbeat must never be grouped with real alerts or
          # throttled — its whole job is to arrive on a predictable cadence.
          receiver = "watchdog";
          matchers = ["severity = watchdog"];
          group_wait = "0s";
          group_interval = "5m";
          repeat_interval = "1h";
        }
        {
          receiver = "critical";
          matchers = ["severity = critical"];
          repeat_interval = "1h";
        }
      ];
    };

    inhibit_rules = [
      {
        # A pool that is FAULTED will also trip every vdev and capacity rule;
        # only page for the root cause.
        source_matchers = ["severity = critical"];
        target_matchers = ["severity = warning"];
        equal = ["alertname" "instance"];
      }
      {
        # HostDown means the exporter is gone, so everything it feeds will
        # go stale. Do not also complain about the stale metrics.
        source_matchers = ["alertname = HostDown"];
        target_matchers = ["severity =~ warning|critical"];
        equal = ["instance"];
      }
    ];

    receivers =
      if matrix.enable
      then map webhookFor receivers
      # Delivery not configured yet: keep the receivers so routing still
      # validates and alerts remain visible in the UI.
      else map (name: {inherit name;}) receivers;
  };
}
