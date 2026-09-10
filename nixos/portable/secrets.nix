# Secrets for the portable stick, decrypted on access.
#
# The stick has no persistent state, so anything it needs to know about the
# world - wifi PSKs, a tailscale auth key, an ssh key - has to ride along in
# the image. Everything in ./secrets is encrypted to the same three YubiKey
# FIDO2-HMAC master identities as the rest of the repo, so a lost stick is a
# lost pile of ciphertext.
#
# Nothing decrypts it at boot. /run/portable-secrets is an *automount*: the
# first process to look inside blocks while portable-secrets.service runs
# `age -d -j fido2-hmac`, which needs a key plugged in and touched. So
# `services.tailscale.authKeyFile` pointing into that directory is the whole
# trigger - tailscale's auto-login is what asks for the YubiKey - and the same
# holds for anything else, including a bare `cat`.
#
# Deliberately not agenix: agenix-rekey re-encrypts to a host key, and this
# host's key would have to live unencrypted on the same stick.
#
# Add one with scripts/portable-secret.sh. Encrypting is public-key only, so
# building an image never needs a YubiKey; only using one does.
{
  config,
  lib,
  pkgs,
  ...
}: let
  secretsDir = ./secrets;

  # The wifi PSKs are not kept here: the same file feeds laptop and desktop
  # through agenix, and it is already encrypted to the three master
  # identities, so it ships verbatim rather than as a second copy.
  sharedWifiSecret = ../config/network/nm-env.age;

  # name -> path.
  ageFiles =
    lib.mapAttrs (name: _: secretsDir + "/${name}")
    (lib.filterAttrs
      (name: type: type == "regular" && lib.hasSuffix ".age" name)
      (builtins.readDir secretsDir))
    // lib.optionalAttrs (builtins.pathExists sharedWifiSecret) {
      "nm-env.age" = sharedWifiSecret;
    };

  hasSecrets = ageFiles != {};

  # Where the automount points, and the directory it binds.
  mountPoint = "/run/portable-secrets";
  plainDir = "${mountPoint}.d";

  decrypt = pkgs.writeShellApplication {
    name = "portable-secrets-decrypt";
    runtimeInputs = with pkgs; [
      age
      age-plugin-fido2-hmac
      coreutils
      util-linux # wall
    ];
    text = builtins.readFile ./portable-decrypt.sh;
  };

  restore = pkgs.writeShellApplication {
    name = "portable-secrets-restore";
    runtimeInputs = [pkgs.coreutils];
    text = builtins.readFile ./portable-restore.sh;
  };

  # The two commands worth knowing about by hand. Unlocking from a terminal
  # rather than letting the service do it matters if the key asks for a PIN:
  # the plugin can only prompt where there is a tty.
  portable-unlock = pkgs.writeShellApplication {
    name = "portable-unlock";
    runtimeInputs = [decrypt restore];
    text = ''
      portable-secrets-decrypt
      portable-secrets-restore
    '';
  };

  portable-lock = pkgs.writeShellApplication {
    name = "portable-lock";
    runtimeInputs = [pkgs.systemd];
    text = ''
      # Stopping the mount re-arms the automount, and stopping the service
      # wipes the plaintext, so the next access asks for the key again.
      systemctl stop 'run-portable\x2dsecrets.mount' portable-secrets.service
      echo "portable-lock: plaintext dropped; next access will ask for the YubiKey"
    '';
  };
in {
  environment.etc =
    lib.mapAttrs'
    (name: path:
      lib.nameValuePair "portable/secrets/${name}" {
        source = path;
      })
    ageFiles;

  environment.systemPackages = [
    portable-unlock
    portable-lock
    # For reading anything the bundle layout doesn't cover:
    #   age -d -j fido2-hmac /etc/portable/secrets/<name>.age
    pkgs.age
    pkgs.age-plugin-fido2-hmac
  ];

  # So the bind source exists even when the decrypt is skipped or fails, and
  # the mount resolves to an empty directory instead of an error.
  systemd.tmpfiles.rules = ["d ${plainDir} 0700 root root -"];

  systemd.services.portable-secrets = lib.mkIf hasSecrets {
    description = "Decrypt the portable image's secrets with a YubiKey";
    # Skipped, successfully, on an image built without any - the mount still
    # comes up, just empty.
    unitConfig.ConditionPathExistsGlob = "/etc/portable/secrets/*.age";
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      # Long enough to find the key and touch it, short enough that a boot
      # without one is not a hang.
      TimeoutStartSec = "60s";
      ExecStart = "${decrypt}/bin/portable-secrets-decrypt";
      ExecStop = "${pkgs.coreutils}/bin/rm -rf ${plainDir}";
    };
  };

  # The mount only completes once the decrypt has, which is what makes a
  # blocking access safe: nobody sees an empty directory and gives up.
  systemd.mounts = lib.mkIf hasSecrets [
    {
      what = plainDir;
      where = mountPoint;
      type = "none";
      options = "bind";
      requires = ["portable-secrets.service"];
      after = ["portable-secrets.service"];
    }
  ];

  systemd.automounts = lib.mkIf hasSecrets [
    {
      where = mountPoint;
      wantedBy = ["multi-user.target"];
      # Never unmount on idle; one touch should last the session. Use
      # `portable-lock` to give the plaintext back.
      automountConfig.TimeoutIdleSec = "0";
    }
  ];

  # Puts ssh keys in place at boot. Reading the directory is what triggers the
  # decrypt, so between this and the wifi profiles a normal boot asks for one
  # touch - drop this from multi-user.target if you would rather nothing asked
  # until you run `portable-unlock` yourself.
  systemd.services.portable-restore = lib.mkIf hasSecrets {
    description = "Install ssh keys from the portable image's secrets";
    wantedBy = ["multi-user.target"];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${restore}/bin/portable-secrets-restore";
    };
  };

  # The read that trips the automount. Gated on that one secret rather than on
  # having any: with it set but absent, tailscaled-autoconnect asks for a
  # touch at every boot and then fails for want of a key.
  services.tailscale.authKeyFile =
    lib.mkIf (ageFiles ? "tailscale-authkey.age") "${mountPoint}/tailscale-authkey";

  # Shown at the console before greetd takes tty1.
  services.getty.helpLine = lib.mkAfter ''

    Encrypted state is baked into this image. Plug in a YubiKey: touch it when
    something asks, or run `sudo portable-unlock` to do it up front.
  '';
}
