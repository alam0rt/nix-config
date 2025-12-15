{
  pkgs,
  config,
  ...
}: {
  age = {
    rekey = {
      masterIdentities = [
        ./pubkeys/yubikey-22916238.pub
        ./pubkeys/yubikey-15498888.pub
        ./pubkeys/yubikey-18103415.pub
      ];
      storageMode = "local";
      localStorageDir = ./. + "/rekeyed/${config.networking.hostName}";
      agePlugins = [pkgs.age-plugin-fido2-hmac];
    };
  };
}
