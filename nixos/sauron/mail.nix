{ config
, lib
, pkgs
, ... }:
let cfg = config.server;
in {
  users.groups.mail = {};
  age.secrets = {
    smtp-addr = {
      file = ../../secrets/smtp-addr.age;
      group = "mail";
    };
    smtp-user = {
      file = ../../secrets/smtp-user.age;
      group = "mail";
    };
    smtp-pass = {
      file = ../../secrets/smtp-pass.age;
      group = "mail";
    };
  };
}