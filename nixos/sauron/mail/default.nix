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
      rekeyFile = ./smtp-addr.age;
      mode = "640";
      group = "mail";
    };
    smtp-user = {
      rekeyFile = ./smtp-user.age;
      mode = "640";
      group = "mail";
    };
    smtp-pass = {
      rekeyFile = ./smtp-pass.age;
      mode = "640";
      group = "mail";
    };
  };
}
