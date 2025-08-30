{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.server;
in {
  environment.systemPackages = with pkgs; [borgbackup];

  age.secrets.borg.file = ../../secrets/borg.age;

  services.borgbackup.jobs = {
    mordor-vault = {
      paths = "/srv/vault";
      repo = "20972@hk-s020.rsync.net:mordor/vault";
      doInit = true;
      encryption = {
        mode = "repokey-blake2";
        passCommand = "cat ${config.age.secrets.borg.path}";
      };
      extraArgs = [ "--remote-path=borg14" ];
      environment.BORG_RSH = "ssh -i /srv/vault/ssh_keys/id_rsa";
      compression = "auto,zstd";
      startAt = "daily";
    };
    mordor-srv-data = {
      paths = "/srv/data";
      repo = "20972@hk-s020.rsync.net:mordor/srv/data";
      doInit = true;
      encryption = {
        mode = "repokey-blake2";
        passCommand = "cat ${config.age.secrets.borg.path}";
      };
      exclude = [
        "*.db-wal" # Exclude SQLite write-ahead log files
        "*.db-shm" # Exclude SQLite shared memory files
      ];
      extraArgs = [ "--remote-path=borg14" ];
      environment.BORG_RSH = "ssh -i /srv/vault/ssh_keys/id_rsa";
      compression = "auto,zstd";
      failOnWarnings = true;
      startAt = "hourly";
    };
    mordor-share-sam = {
      paths = "/srv/share/sam";
      repo = "20972@hk-s020.rsync.net:mordor/share/sam";
      doInit = true;
      encryption = {
        mode = "repokey-blake2";
        passCommand = "cat ${config.age.secrets.borg.path}";
      };
      extraArgs = [ "--remote-path=borg14" ];
      environment.BORG_RSH = "ssh -i /srv/vault/ssh_keys/id_rsa";
      compression = "auto,zstd";
      startAt = "daily";
    };
    mordor-share-emma = {
      paths = "/srv/share/emma";
      repo = "20972@hk-s020.rsync.net:mordor/share/emma";
      doInit = true;
      encryption = {
        mode = "repokey-blake2";
        passCommand = "cat ${config.age.secrets.borg.path}";
      };
      extraArgs = [ "--remote-path=borg14" ];
      environment.BORG_RSH = "ssh -i /srv/vault/ssh_keys/id_rsa";
      compression = "auto,zstd";
      startAt = "daily";
    };
  };
}
