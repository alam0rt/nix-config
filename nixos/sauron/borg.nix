{
  config,
  pkgs,
  ...
}: let
  user = "hk1068";
  host = "${user}.rsync.net";
  repo = "${user}@${host}";
  environment = {
    #BORG_RSH = "ssh -i /srv/vault/ssh_keys/id_rsa";
    BORG_RELOCATED_REPO_ACCESS_IS_OK = "1";
  };
in {
  environment.systemPackages = with pkgs; [borgbackup];

  age.secrets.borg.rekeyFile = ../../secrets/borg.age;

  services.borgbackup.jobs = {
    mordor-vault = {
      paths = "/srv/vault";
      repo = "${repo}:mordor/vault";
      doInit = true;
      encryption = {
        mode = "repokey-blake2";
        passCommand = "cat ${config.age.secrets.borg.path}";
      };
      extraArgs = ["--remote-path=borg14"];
      environment = environment;
      compression = "auto,zstd";
      startAt = "daily";
    };
    mordor-srv-data = {
      paths = "/srv/data";
      repo = "${repo}:mordor/srv/data";
      doInit = true;
      encryption = {
        mode = "repokey-blake2";
        passCommand = "cat ${config.age.secrets.borg.path}";
      };
      exclude = [
        "*.db-wal" # Exclude SQLite write-ahead log files
        "*.db-shm" # Exclude SQLite shared memory files
      ];
      extraArgs = ["--remote-path=borg14"];
      environment = environment;
      compression = "auto,zstd";
      failOnWarnings = true;
      startAt = "hourly";
    };
    mordor-share-sam = {
      paths = "/srv/share/sam";
      repo = "${repo}:mordor/share/sam";
      doInit = true;
      encryption = {
        mode = "repokey-blake2";
        passCommand = "cat ${config.age.secrets.borg.path}";
      };
      extraArgs = ["--remote-path=borg14"];
      environment = environment;
      compression = "auto,zstd";
      startAt = "daily";
    };
    mordor-share-emma = {
      paths = "/srv/share/emma";
      repo = "${repo}:mordor/share/emma";
      doInit = true;
      encryption = {
        mode = "repokey-blake2";
        passCommand = "cat ${config.age.secrets.borg.path}";
      };
      extraArgs = ["--remote-path=borg14"];
      environment = environment;
      compression = "auto,zstd";
      startAt = "daily";
    };
  };
}
