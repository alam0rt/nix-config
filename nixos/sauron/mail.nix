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
      path = "/etc/smtp.addr";
      group = "mail";
    };
    smtp-user = {
      file = ../../secrets/smtp-user.age;
      path = "/etc/smtp.user";
      group = "mail";
    };
    smtp-pass = {
      file = ../../secrets/smtp-pass.age;
      path = "/etc/smtp.pass";
      group = "mail";
    };
  };
}