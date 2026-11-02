{
  config,
  lib,
  pkgs,
  ...
}: let
  cw = config.services.calibre-web;
  calibre = cw.calibrePackage;

  # The Calibre library proper (metadata.db + Author/Title/ folders). On
  # /srv/data so the hourly borg srv-data job picks it up.
  library = "/srv/data/calibre/library";

  # Home's public addresses, as seen by Cloudflare. IPv4 is the WAN address.
  # IPv6: the interface IDs rotate (DHCPv6 lease, privacy addresses) but the
  # delegated /48 has been stable since at least 2026-08. Both are set by the
  # ISP: if either changes, the site 403s from home.
  homeIPv4 = "202.153.220.8";
  homeIPv6 = "2403:5804:66ea::/48";

  # https://www.cloudflare.com/ips-v4 and /ips-v6, fetched 2026-11-03.
  cloudflareRanges = [
    "173.245.48.0/20"
    "103.21.244.0/22"
    "103.22.200.0/22"
    "103.31.4.0/22"
    "141.101.64.0/18"
    "108.162.192.0/18"
    "190.93.240.0/20"
    "188.114.96.0/20"
    "197.234.240.0/22"
    "198.41.128.0/17"
    "162.158.0.0/15"
    "104.16.0.0/13"
    "104.24.0.0/14"
    "172.64.0.0/13"
    "131.0.72.0/22"
    "2400:cb00::/32"
    "2606:4700::/32"
    "2803:f800::/32"
    "2405:b500::/32"
    "2405:8100::/32"
    "2a06:98c0::/29"
    "2c0f:f248::/32"
  ];

  # calibre-web's built-in administrator; see the ExecStartPre below.
  adminUser = "admin";

  # Drop folder on the guest-writable `public` SMB share. Anything that lands
  # here (subfolders too) is imported into the library and then deleted. Files
  # calibre doesn't take go to `failed` — deliberately outside the inbox, so
  # nothing left lying in the inbox can keep re-triggering the import.
  inbox = "/srv/share/public/books-inbox";
  failed = "/srv/share/public/books-failed";

  # Calibre writes its prefs/caches under $HOME/.config unless told otherwise,
  # and wants a Qt platform even for headless cover rendering.
  calibreEnv = {
    CALIBRE_CONFIG_DIRECTORY = "/var/lib/calibre-ingest";
    CALIBRE_TEMP_DIR = "/var/cache/calibre-ingest";
    QT_QPA_PLATFORM = "offscreen";
  };

  ingest = pkgs.writeShellScript "calibre-ingest" ''
    set -u
    # The path unit fires as soon as the first file of a batch is closed; give
    # the rest of the copy a moment, then skip anything written in the last 10s
    # (the timer comes back for those).
    sleep 15
    find ${lib.escapeShellArg inbox} -mindepth 1 -type f ! -name '.*' \
      ! -newermt '10 seconds ago' -print0 |
      while IFS= read -r -d "" f; do
        out=$(${calibre}/bin/calibredb add --with-library ${lib.escapeShellArg library} -- "$f" 2>&1)
        echo "$f: $out"
        # calibredb exits 0 for duplicates and for files it silently ignores, so
        # judge by what it says: only delete what is now in the library.
        if grep -qE 'Added book ids|Merged book ids|already exist in the database' <<<"$out"; then
          rm -f -- "$f"
        else
          echo "not imported, moving to ${failed}: $f" >&2
          mv -f --backup=numbered -- "$f" ${lib.escapeShellArg failed}/
        fi
      done
    # Folders dropped in whole leave their (now empty) skeleton behind.
    find ${lib.escapeShellArg inbox} -mindepth 1 -type d -empty -delete
  '';
in {
  services.calibre-web = {
    enable = true;
    listen = {
      ip = "127.0.0.1";
      port = 8083;
    };
    dataDir = "/srv/data/calibre-web"; # app.db: users, shelves, settings
    options = {
      calibreLibrary = library;
      enableBookUploading = true;
      # ebook-convert, so a book can be turned into AZW3 for the stock
      # Kindle reader. KOReader reads EPUB directly and doesn't need it.
      enableBookConversion = true;
    };
  };

  # calibre-web creates an `admin` account with the well-known password
  # `admin123`, and this vhost is public. Pin the admin password to a secret on
  # every start, after the module's own pre-start has created/migrated app.db,
  # so the default is never live. The unit fails rather than start if this
  # doesn't work — e.g. after renaming `admin` in the UI (change it here too).
  # Changing the admin password in the web UI won't stick; edit the secret.
  age.secrets.calibre-web-admin = {
    rekeyFile = ./calibre-web-admin.age;
    owner = cw.user;
    mode = "0400";
    # calibre-web's default password policy wants upper, lower, digit and a
    # non-alphanumeric character, so the stock `alnum` generator gets rejected
    # by `-s`. pwgen's -c/-n/-y each guarantee at least one of their class.
    generator.script = {pkgs, ...}: ''
      ${pkgs.pwgen}/bin/pwgen -s -c -n -y 32 1
    '';
  };
  systemd.services.calibre-web.serviceConfig.ExecStartPre = lib.mkAfter [
    (pkgs.writeShellScript "calibre-web-admin-password" ''
      exec ${cw.package}/bin/calibre-web \
        -p ${cw.dataDir}/app.db -g ${cw.dataDir}/gdrive.db \
        -s "${adminUser}:$(cat ${config.age.secrets.calibre-web-admin.path})"
    '')
  ];

  # calibre-web refuses to start without a metadata.db (its pre-start checks for
  # one). Opening a library path that has none makes calibre create an empty one.
  systemd.services.calibre-library-init = {
    description = "Create an empty Calibre library if there is none";
    wantedBy = ["calibre-web.service"];
    before = ["calibre-web.service"];
    unitConfig.ConditionPathExists = "!${library}/metadata.db";
    environment = calibreEnv;
    serviceConfig = {
      Type = "oneshot";
      User = cw.user;
      Group = cw.group;
      StateDirectory = "calibre-ingest";
      CacheDirectory = "calibre-ingest";
      ExecStart = "${calibre}/bin/calibredb list --with-library ${library}";
    };
  };

  # PathChanged fires when a file in the inbox is closed after writing, i.e. a
  # copy has finished. The timer catches anything that arrived while an import
  # was already running (those events are not queued) or was still too fresh.
  systemd.paths.calibre-ingest = {
    wantedBy = ["multi-user.target"];
    pathConfig.PathChanged = inbox;
  };
  systemd.timers.calibre-ingest = {
    wantedBy = ["timers.target"];
    timerConfig = {
      OnBootSec = "5m";
      OnUnitInactiveSec = "10m";
    };
  };
  systemd.services.calibre-ingest = {
    description = "Import books dropped in ${inbox} into the Calibre library";
    after = ["calibre-library-init.service"];
    environment = calibreEnv;
    serviceConfig = {
      Type = "oneshot";
      User = cw.user;
      Group = cw.group;
      StateDirectory = "calibre-ingest";
      CacheDirectory = "calibre-ingest";
      ExecStart = ingest;
      # A big batch import shouldn't compete with Jellyfin.
      Nice = 10;
      IOSchedulingClass = "idle";
    };
  };

  systemd.tmpfiles.rules = [
    "d /srv/data/calibre 0750 ${cw.user} ${cw.group} -"
    "d ${library} 0750 ${cw.user} ${cw.group} -"
    # 0777 like the rest of the guest share: samba writes as nobody, the ingest
    # service runs as calibre-web and has to delete what it imported.
    "d ${inbox} 0777 ${cw.user} ${cw.group} -"
    "d ${failed} 0777 ${cw.user} ${cw.group} -"
  ];

  # KOReader can't sit behind tailscaleAuth (the Kindle isn't on the tailnet),
  # so calibre-web's own login gates everything — anonymous browsing stays off
  # (the default), and OPDS then asks for HTTP basic auth.
  #
  # For now it is also home-only: only our own public addresses are let in.
  # books.iced.cool sits behind Cloudflare's proxy (the *.iced.cool wildcard),
  # so the TCP peer is always a Cloudflare edge; the real client is in
  # CF-Connecting-IP, trusted only when the peer is in Cloudflare's ranges.
  # Anyone hitting the WAN IP directly with this Host header is judged on their
  # own address and denied. Drop the allow/deny lines to open it up.
  services.nginx.virtualHosts."books.iced.cool" = {
    forceSSL = true;
    useACMEHost = "iced.cool";
    extraConfig = ''
      ${lib.concatMapStrings (r: "set_real_ip_from ${r};\n") cloudflareRanges}
      real_ip_header CF-Connecting-IP;

      allow ${homeIPv4};
      allow ${homeIPv6};
      deny all;

      # Web uploads of whole PDFs/comics. Cloudflare's proxy caps request
      # bodies at 100 MB on the free plan regardless.
      client_max_body_size 500M;
    '';
    locations."/" = {
      proxyPass = "http://127.0.0.1:${toString cw.listen.port}";
      recommendedProxySettings = true;
      # calibre-web builds absolute URLs (OPDS links, redirects) from X-Scheme,
      # not X-Forwarded-Proto; without it the OPDS feed hands out http:// links.
      extraConfig = ''
        proxy_set_header X-Scheme $scheme;
      '';
    };
    locations."= /login" = {
      proxyPass = "http://127.0.0.1:${toString cw.listen.port}";
      recommendedProxySettings = true;
      extraConfig = ''
        proxy_set_header X-Scheme $scheme;
        limit_req zone=login burst=3 nodelay;
      '';
    };
  };
}
