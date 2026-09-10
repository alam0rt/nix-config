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

  # Where the automount points, and the directory it binds. These are the
  # only definitions: the shell bodies take them from here, because a
  # decrypt target that drifts from the bind source brings the mount up
  # *empty* rather than failing, which is the worst way this can break.
  mountPoint = "/run/portable-secrets";
  plainDir = "${mountPoint}.d";
  etcPrefix = "portable/secrets";
  user = config.users.users.sam.name;
  home = config.users.users.sam.home;

  decrypt = pkgs.writeShellApplication {
    name = "portable-secrets-decrypt";
    runtimeInputs = with pkgs; [
      age
      age-plugin-fido2-hmac
      coreutils
      util-linux # wall
    ];
    text =
      ''
        secrets_dir=/etc/${etcPrefix}
        plain_dir=${plainDir}
      ''
      + builtins.readFile ./portable-decrypt.sh;
  };

  restore = pkgs.writeShellApplication {
    name = "portable-secrets-restore";
    runtimeInputs = [pkgs.coreutils];
    text =
      ''
        secrets=${mountPoint}
        user=${user}
        home=${home}
      ''
      + builtins.readFile ./portable-restore.sh;
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
      # The mount is BindsTo= this service, so it comes down with it, and the
      # service's ExecStop wipes the plaintext. The automount stays armed, so
      # the next access asks for the key again.
      systemctl stop portable-secrets.service
      echo "portable-lock: plaintext dropped; next access will ask for the YubiKey"
    '';
  };
in {
  environment.etc =
    lib.mapAttrs'
    (name: path:
      lib.nameValuePair "${etcPrefix}/${name}" {
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
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      # Upstream orders NetworkManager-ensure-profiles before
      # network-online.target, and that unit waits on this mount, so this
      # timeout is what a keyless boot costs everything ordered after the
      # network. Long enough to notice a blinking key, short enough to sit
      # through.
      TimeoutStartSec = "30s";
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
      # BindsTo, not Requires: the service's ExecStop deletes this mount's
      # source, so anything that stops the service - a restart included - has
      # to take the mount with it. Otherwise the bind survives over a deleted
      # directory, the automount is never re-armed, and every later reader
      # sees an empty directory with no way back short of umount.
      bindsTo = ["portable-secrets.service"];
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
    # Without this the glob just comes back empty when the decrypt failed,
    # and the unit reports "no ssh keys in this image" about an image that
    # has them.
    unitConfig.RequiresMountsFor = mountPoint;
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
