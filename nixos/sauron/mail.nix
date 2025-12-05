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
      rekeyFile = ../../secrets/smtp-addr.age;
      mode = "640";
      group = "mail";
    };
    smtp-user = {
      rekeyFile = ../../secrets/smtp-user.age;
      mode = "640";
      group = "mail";
    };
    smtp-pass = {
      rekeyFile = ../../secrets/smtp-pass.age;
      mode = "640";
      group = "mail";
    };
  };
}
