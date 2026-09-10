# Secrets for the portable stick.
#
# The stick has no persistent state at all, so anything it needs to know -
# wifi PSKs, a tailscale auth key, an ssh key - has to ride along in the
# image. Everything in ./secrets is encrypted to the same three YubiKey
# FIDO2-HMAC master identities as the rest of the repo, so a lost stick is a
# lost pile of ciphertext: opening it needs one of the keys, plugged in and
# touched. `portable-unlock` does the decryption, into tmpfs, on demand.
#
# Deliberately *not* agenix: agenix-rekey re-encrypts to a host key, and this
# host's key would have to live unencrypted on the same stick, which would
# undo the whole thing. These files stay master-encrypted and are read
# interactively instead.
#
# Pack the bundle with scripts/portable-pack-state.sh - encrypting is public
# -key only, so building an image never needs a YubiKey. Only using it does.
{
  config,
  lib,
  pkgs,
  ...
}: let
  secretsDir = ./secrets;

  ageFiles =
    lib.filterAttrs
    (name: type: type == "regular" && lib.hasSuffix ".age" name)
    (builtins.readDir secretsDir);

  portable-unlock = pkgs.writeShellApplication {
    name = "portable-unlock";
    runtimeInputs = with pkgs; [
      age
      age-plugin-fido2-hmac
      coreutils
      gnutar
      networkmanager
      config.services.tailscale.package
    ];
    text =
      ''
        PORTABLE_TS_FLAGS=${lib.escapeShellArg (toString config.services.tailscale.extraUpFlags)}
      ''
      + builtins.readFile ./portable-unlock.sh;
  };
in {
  environment.etc =
    lib.mapAttrs'
    (name: _:
      lib.nameValuePair "portable/secrets/${name}" {
        source = secretsDir + "/${name}";
      })
    ageFiles;

  environment.systemPackages = [
    portable-unlock
    # For reading anything the wrapper doesn't know how to apply:
    #   age -d -j fido2-hmac /etc/portable/secrets/<name>.age
    pkgs.age
    pkgs.age-plugin-fido2-hmac
  ];

  # Shown at the console before greetd takes tty1, since there is no other
  # hint that the command exists.
  services.getty.helpLine = lib.mkAfter ''

    Encrypted state is baked into this image. Plug in a YubiKey and run
    `sudo portable-unlock` to restore wifi, ssh keys and tailscale.
  '';
}
