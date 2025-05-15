{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.server;
in
{
  # NFS
  services.nfs.server = {
    enable = true;
    # fixed rpc.statd port; for firewall
    lockdPort = 4001;
    mountdPort = 4002;
    statdPort = 4000;
    exports = ''
      /srv/share/sam          192.168.0.0/255.255.255.0(rw,fsid=0,no_subtree_check) 100.64.0.0/255.255.255.0(rw,fsid=0,no_subtree_check)
      /srv/share/emma         192.168.0.0/255.255.255.0(rw,fsid=0,no_subtree_check) 100.64.0.0/255.255.255.0(rw,fsid=0,no_subtree_check)
      /srv/share/public       192.168.0.0/255.255.255.0(rw,nohide,insecure,no_subtree_check) 100.64.0.0/255.255.255.0(rw,nohide,insecure,no_subtree_check)
      /srv/media              192.168.0.0/255.255.255.0(ro,nohide,insecure,no_subtree_check) 100.64.0.0/255.255.255.0(rw,nohide,insecure,no_subtree_check)
    '';
  };

  networking.firewall =
    let
      inherit (config.services.nfs) server;
    in
    {
      allowedTCPPorts = [
        server.lockdPort
        server.mountdPort
        server.statdPort
        111
        2049
        20048
      ];
      allowedUDPPorts = [
        server.lockdPort
        server.mountdPort
        server.statdPort
        111
        2049
        20048
      ];
    };

  # Samba
  services.samba-wsdd.enable = true; # make shares visible for windows 10 clients
  services.samba-wsdd.openFirewall = true;

  services.samba = {
    enable = true;
    openFirewall = true;
    settings = {
      global = {
        workgroup = "WORKGROUP";
        "server string" = "sauron";
        "netbios name" = "sauron";
        security = "user";
        "hosts allow" = "100.64. 192.168.0. 127.0.0.1 localhost ::1";
        "hosts deny" = "0.0.0.0/0";
        "guest account" = "nobody";
        "map to guest" = "bad user";
      };
      public = {
        path = "/srv/share/public";
        browseable = "yes";
        writable = "yes";
        "read only" = "no";
        "guest ok" = "yes";
        "create mask" = "0664";
        "directory mask" = "2777";
        "force user" = "nobody";
        "force group" = "nogroup";
      };
      sam = {
        path = "/srv/share/sam";
        browseable = "no";
        "read only" = "no";
        "guest ok" = "no";
        "create mask" = "0600";
        "directory mask" = "0700";
        "force user" = "sam";
        "force group" = "root";
      };
      emma = {
        path = "/srv/share/emma";
        browseable = "no";
        "read only" = "no";
        "guest ok" = "no";
        "create mask" = "0600";
        "directory mask" = "0700";
        "force user" = "emma";
        "force group" = "root";
      };
      tv = {
        path = "/srv/media/tv";
        browseable = "yes";
        "read only" = "yes";
        "guest ok" = "yes";
        "create mask" = "0600";
        "directory mask" = "0700";
        "force user" = "nobody";
        "force group" = "nogroup";
      };
      movies = {
        path = "/srv/media/movies";
        browseable = "yes";
        "read only" = "yes";
        "guest ok" = "yes";
        "create mask" = "0600";
        "directory mask" = "0700";
        "force user" = "nobody";
        "force group" = "nogroup";
      };
      downloads = {
        path = "/srv/media/downloads";
        browseable = "yes";
        "read only" = "no";
        "guest ok" = "yes";
        "create mask" = "0644";
        "directory mask" = "0755";
        "force user" = "nobody";
        "force group" = "nogroup";
      };
    };
  };
}
