{pkgs, ...}: {
  fileSystems."/mnt/share/sam" = {
    device = "sauron:/srv/share/sam";
    fsType = "nfs";
    options = [
      "x-systemd.automount"
      "noauto"
    ];
  };

  fileSystems."/mnt/share/public" = {
    device = "sauron:/srv/share/public";
    fsType = "nfs";
    options = [
      "x-systemd.automount"
      "noauto"
    ];
  };

  fileSystems."/mnt/media/downloads" = {
    device = "sauron:/srv/media/downloads";
    fsType = "nfs";
    options = [
      "x-systemd.automount"
      "noauto"
    ];
  };

  fileSystems."/mnt/media/tv" = {
    device = "sauron:/srv/media/tv";
    fsType = "nfs";
    options = [
      "x-systemd.automount"
      "noauto"
    ];
  };

  fileSystems."/mnt/media/movies" = {
    device = "sauron:/srv/media/movies";
    fsType = "nfs";
    options = [
      "x-systemd.automount"
      "noauto"
    ];
  };
}
