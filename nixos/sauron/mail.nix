{ config
, lib
, pkgs
, ... }:
let cfg = config.server;
in {
  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  # programs.mtr.enable = true;
  # programs.gnupg.agent = {
  #   enable = true;
  #   enableSSHSupport = true;
  # };
  age.secrets = {
    smtp-addr.file = ../../secrets/smtp-addr.age;
    smtp-user.file = ../../secrets/smtp-user.age;
    smtp-pass.file = ../../secrets/smtp-pass.age;
  };
  programs.msmtp = {
    enable = true;
    setSendmail = true;
    defaults = {
      aliases = "/etc/aliases";
      port = 465;
      tls_trust_file = "/etc/ssl/certs/ca-certificates.crt";
      tls = true;
      auth = "login";
      tls_starttls = "off";
    };
    accounts = {
      default = {
        host = builtins.readFile config.age.secrets.smtp-addr.path; # stored in store but that's okay
        tls_fingerprint = "5C:72:F6:4D:A9:CE:79:1A:B5:2C:60:E7:CB:7C:DF:C4:D2:63:AA:CB:97:EA:1E:18:8A:D6:C4:C5:C0:5F:4F:A1";
        passwordeval = config.age.secrets.smtp-pass.path;
        user = builtins.readFile config.age.secrets.smtp-user.path; # stored in store but that's okay
        from = "sauron@iced.cool";
      };
    };
  };
  environment.etc = {
    "aliases" = {
      text = ''
	root: sam@samlockart.com
      '';
	mode = "0644";
    };
  };

  environment.systemPackages = with pkgs; [
    mailutils
  ];

  ## alert on failure
  systemd.services = {
    "notify-problems@" = {
      enable = false; # need to fix sendgrid shit
      serviceConfig.User = "root";
      environment.SERVICE = "%i";
      script = ''
        printf "Content-Type: text/plain\r\nSubject: $SERVICE FAILED\r\n\r\n$(systemctl status $SERVICE)" | /run/wrappers/bin/sendmail root
      '';
    };
  };
  systemd.packages = [
    (pkgs.runCommandNoCC "notify.conf" {
      preferLocalBuild = true;
      allowSubstitutes = false;
    } ''
      mkdir -p $out/etc/systemd/system/service.d/
      echo -e "[Unit]\nOnFailure=notify-problems@%i.service\nStartLimitIntervalSec=1d\nStartLimitBurst=5\n" > $out/etc/systemd/system/service.d/notify.conf
      '')
  ];
}