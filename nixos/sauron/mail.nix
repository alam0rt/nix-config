{ config
, lib
, pkgs
, ... }:
let cfg = config.server;
in {
  age.secrets = {
    smtp-addr = {
      file = ../../secrets/smtp-addr.age;
      path = "/etc/smtp.addr";
    };
    smtp-user = {
      file = ../../secrets/smtp-user.age;
      path = "/etc/smtp.user";
    };
    smtp-pass = {
      file = ../../secrets/smtp-pass.age;
      path = "/etc/smtp.pass";
    };
  };
}