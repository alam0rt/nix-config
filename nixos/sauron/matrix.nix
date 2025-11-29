{
  pkgs,
  lib,
  config,
  ...
}: let
  fqdn = "${config.networking.hostName}.${config.networking.domain}";
  baseUrl = "https://${fqdn}";
  clientConfig."m.homeserver".base_url = baseUrl;
  serverConfig."m.server" = "${fqdn}:443";
  mkWellKnown = data: ''
    default_type application/json;
    return 200 '${builtins.toJSON data}';
  '';
in {
  networking.domain = "iced.cool";
  networking.firewall.allowedTCPPorts = [
    80
    443
  ];

  services.postgresql.enable = true;

  services.nginx = {
    virtualHosts = {
      # If the A and AAAA DNS records on example.org do not point on the same host as the
      # records for myhostname.example.org, you can easily move the /.well-known
      # virtualHost section of the code to the host that is serving example.org, while
      # the rest stays on myhostname.example.org with no other changes required.
      # This pattern also allows to seamlessly move the homeserver from
      # myhostname.example.org to myotherhost.example.org by only changing the
      # /.well-known redirection target.
      "iced.cool" = {
        enableACME = true;
        forceSSL = true;
        # This section is not needed if the server_name of matrix-synapse is equal to
        # the domain (i.e. example.org from @foo:example.org) and the federation port
        # is 8448.
        # Further reference can be found in the docs about delegation under
        # https://element-hq.github.io/synapse/latest/delegate.html
        locations."= /.well-known/matrix/server".extraConfig = mkWellKnown serverConfig;
        # This is usually needed for homeserver discovery (from e.g. other Matrix clients).
        # Further reference can be found in the upstream docs at
        # https://spec.matrix.org/latest/client-server-api/#getwell-knownmatrixclient
        locations."= /.well-known/matrix/client".extraConfig = mkWellKnown clientConfig;
      };
      "${fqdn}" = {
        enableACME = true;
        forceSSL = true;
        # It's also possible to do a redirect here or something else, this vhost is not
        # needed for Matrix. It's recommended though to *not put* element
        # here, see also the section about Element.
        locations."/".extraConfig = ''
          return 404;
        '';
        # Forward all Matrix API calls to the synapse Matrix homeserver. A trailing slash
        # *must not* be used here.
        locations."/_matrix".proxyPass = "http://[::1]:8008";
        # Forward requests for e.g. SSO and password-resets.
        locations."/_synapse/client".proxyPass = "http://[::1]:8008";
      };
    };
  };

  systemd.services."matrix-authentication-service" = {
    description = "MAS";
    after = ["network.target" "postgresql.service"];
    wantedBy = ["multi-user.target"];
    serviceConfig = {
      Environment = "MAS_CONFIG_FILE=${config.environment.etc."mas/config.yaml".source}:/srv/data/matrix-authentication-service/secrets.yaml";
      ExecStart = "${pkgs.matrix-authentication-service}/bin/mas-cli config check";
      Type = "oneshot";
      RemainAfterExit = true;
      User = "matrix-synapse";
      Group = "matrix-synapse";
      Restart = "on-failure";
    };
    enable = true;
  };

  # for matrix-authentication-service
  # the secrets are generated and stored in /srv/data/matrix-authentication-service/secrets.yaml manually
  environment.etc."mas/config.yaml" = {
    user = config.users.groups.matrix-synapse.name;
    gid = config.users.groups.matrix-synapse.gid;
    source = (pkgs.formats.yaml {}).generate "config" {
      database = {
        uri = "postgresql://postgres@localhost/mas";
      };
    };
  };

  services.matrix-synapse = {
    enable = true;
    settings.server_name = config.networking.domain;
    # The public base URL value must match the `base_url` value set in `clientConfig` above.
    # The default value here is based on `server_name`, so if your `server_name` is different
    # from the value of `fqdn` above, you will likely run into some mismatched domain names
    # in client applications.
    settings.public_baseurl = baseUrl;
    settings.listeners = [
      {
        port = 8008;
        bind_addresses = ["::1"];
        type = "http";
        tls = false;
        x_forwarded = true;
        resources = [
          {
            names = [
              "client"
              "federation"
            ];
            compress = true;
          }
        ];
      }
    ];
  };

  #\\\\\\\
  # element
  #\\\\\\\\\
  services.nginx.virtualHosts."x.${fqdn}" = {
    enableACME = true;
    forceSSL = true;
    serverAliases = ["x.${config.networking.domain}"];

    root = pkgs.element-web.override {
      conf = {
        default_server_config = clientConfig; # see `clientConfig` from the snippet above.
      };
    };
  };
}
