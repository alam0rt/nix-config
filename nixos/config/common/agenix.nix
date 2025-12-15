{...}: {
  age = {
    rekey = {
      masterIdentities = [
        ../../secrets/yubikey-22916238.pub
        ../../secrets/yubikey-15498888.pub
        ../../secrets/yubikey-18103415.pub
      ];
      storageMode = "local";
      localStorageDir = ./. + "/secrets/rekeyed/${config.networking.hostName}";
      agePlugins = [pkgs.age-plugin-fido2-hmac];
    };
  };
}
