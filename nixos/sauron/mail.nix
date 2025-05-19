{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.server;
in {
  users.groups.mail = {};
  age.secrets = {
    smtp-addr = {
      file = ../../secrets/smtp-addr.age;
      mode = "640";
      group = "mail";
    };
    smtp-user = {
      file = ../../secrets/smtp-user.age;
      mode = "640";
      group = "mail";
    };
    smtp-pass = {
      file = ../../secrets/smtp-pass.age;
      mode = "640";
      group = "mail";
    };
  };
}
