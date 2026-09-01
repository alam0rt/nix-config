{config, ...}: {
  age.secrets.ups-monitor-password = {
    rekeyFile = ./ups-monitor-password.age;
    generator.script = "alnum";
    mode = "0400";
    owner = "root";
  };

  # Keep retrying the driver until the UPS actually shows up.
  #
  # The stock module runs upsdrvctl as a Type=oneshot with the systemd default
  # Restart=no, so a UPS that is not enumerated at the moment the unit runs
  # leaves the driver dead until a human notices. That is precisely what
  # happened between 2026-08-29 and 2026-09-01: a faulty USB port meant the UPS
  # never enumerated, upsdrv failed at boot, and nothing retried — 17 silent
  # failures over 30 days while the machine had no working power monitoring.
  #
  # NUT's own nut-driver-enumerator is the upstream answer, but it works by
  # generating and enabling nut-driver@.service instances at runtime, which
  # fights the read-only /etc/systemd/system that NixOS builds. Retrying the
  # existing unit is much the smaller change and covers the same failures: a UPS
  # absent at boot, or unplugged and moved to another port later, is picked up
  # within RestartSec without intervention.
  #
  # StartLimitIntervalSec=0 disables the default start-rate limiter, which would
  # otherwise give up permanently after five attempts and reintroduce the exact
  # silent-death behaviour this is meant to remove.
  systemd.services.upsdrv = {
    startLimitIntervalSec = 0;
    serviceConfig = {
      Restart = "on-failure";
      RestartSec = 60;
    };
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
