{
  config,
  ...
}: {
  age.secrets.tailscale-authkey.rekeyFile = ./authkey.age;
  services.tailscale.authKeyFile = config.age.secrets.tailscale-authkey.path;
}
