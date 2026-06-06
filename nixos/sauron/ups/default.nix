{config, ...}: {
  age.secrets.ups-monitor-password = {
    rekeyFile = ./ups-monitor-password.age;
    generator.script = "alnum";
    mode = "0400";
    owner = "root";
  };

  power.ups = {
    enable = true;
    # Single host monitoring its own locally-attached UPS over USB.
    mode = "standalone";

    ups.sauron = {
      driver = "usbhid-ups";
      port = "auto";
      description = "CyberPower VP700ELCD";
    };

    users.monitor = {
      passwordFile = config.age.secrets.ups-monitor-password.path;
      upsmon = "primary";
    };

    upsmon = {
      monitor."sauron@localhost" = {
        user = "monitor";
        passwordFile = config.age.secrets.ups-monitor-password.path;
        type = "primary";
      };
      settings = {
        # Seconds between low-battery signal and the shutdown command running.
        FINALDELAY = 5;
        # Refuse to keep running if no UPS reports power-good.
        MINSUPPLIES = 1;
      };
    };
  };
}
