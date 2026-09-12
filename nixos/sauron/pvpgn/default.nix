{
  config,
  lib,
  pkgs,
  ...
}: let
  pvpgn = pkgs.pvpgn-server;

  stateDir = "/srv/data/pvpgn";

  # The server identifies itself with this in the channel list and in /serverinfo.
  serverName = "WankNet";

  news = ''
    {2026-09-12}

    Welcome to the jungle.

    StarCraft: Brood War 1.16.1 only. Type /help for commands.
  '';

  # Every config file other than bnetd.conf comes from the package unmodified.
  # Copying the whole etc/pvpgn tree and overwriting the few files we care about
  # is far less code than enumerating forty environment.etc entries, and it keeps
  # new upstream config files working by default. bnetd.conf itself is generated
  # separately and points back in here, which is why it is not part of this tree
  # — putting it here would make the derivation depend on its own output path.
  confDir = pkgs.runCommand "pvpgn-conf" {} ''
    cp -r ${pvpgn}/etc/pvpgn $out
    chmod -R u+w $out
    cp ${pkgs.writeText "news.txt" news} $out/i18n/news.txt
  '';

  # bnetd.conf is a flat `key = value` file. Its parser (_get_value in
  # src/common/conf.cpp) strips a surrounding pair of double quotes if it finds
  # one, and otherwise reads a single whitespace-delimited word — so quoting
  # every string is always safe, while leaving one bare silently truncates any
  # value containing a space. Numbers and booleans must stay bare.
  toConf = lib.generators.toKeyValue {
    mkKeyValue = lib.generators.mkKeyValueDefault {
      mkValueString = v:
        if lib.isInt v
        then toString v
        else if lib.isBool v
        then lib.boolToString v
        else if lib.isString v
        then ''"${v}"''
        else lib.generators.mkValueStringDefault {} v;
    } " = ";
  };

  bnetdConf = toConf {
    servername = serverName;

    # A real file, because bnetd gives us no choice. src/bnetd/main.cpp sets the
    # event stream to stderr, then unconditionally replaces it with
    # eventlog_open(prefs_get_logfile()) and exits fatally if no logfile is set —
    # and eventlog_open is a plain fopen(filename, "a") with no special case for
    # "stdout" or "-". Pointing it at /dev/stderr does not work either: under
    # StandardError=journal fd 2 is an AF_UNIX socket, and opening
    # /proc/self/fd/2 on a socket fails with ENXIO (verified). So the journal
    # carries only systemd's own lines for this unit; the server's own log is
    # here, and logrotate below keeps it bounded.
    logfile = "${stateDir}/bnetd.log";
    loglevels = "fatal,error,warn,info";

    # One SQLite file rather than the default plain-file account tree: accounts
    # are small, and a single file is far easier to back up and to hand to
    # sqlite3 when an account needs poking at by hand.
    storage_path = "sql:mode=sqlite3;name=${stateDir}/users.db;default=0;prefix=pvpgn_";

    # Read-only data shipped in the package: icons.bni, the IX86*.mpq version
    # -check archives, newbie.save. bnetd only ever reads these, so pointing at
    # the store path is fine and means a package bump updates them.
    filedir = "${pvpgn}/var/pvpgn/files";

    # Everything below is written at runtime.
    reportdir = "${stateDir}/reports";
    chanlogdir = "${stateDir}/chanlogs";
    userlogdir = "${stateDir}/userlogs";
    maildir = "${stateDir}/bnmail";
    ladderdir = "${stateDir}/ladders";
    statusdir = "${stateDir}/status";
    scriptdir = "${stateDir}/lua";
    # bnban.conf is the one "config" file bnetd rewrites (the /ipban command),
    # so it lives in the state dir and is seeded from the package on first boot.
    ipbanfile = "${stateDir}/bnban.conf";

    # Static config, from the confDir tree assembled above.
    i18ndir = "${confDir}/i18n";
    issuefile = "${confDir}/bnissue.txt";
    channelfile = "${confDir}/channel.conf";
    adfile = "${confDir}/ad.json";
    mpqfile = "${confDir}/autoupdate.conf";
    realmfile = "${confDir}/realm.conf";
    versioncheck_file = "${confDir}/versioncheck.json";
    mapsfile = "${confDir}/bnmaps.conf";
    xplevelfile = "${confDir}/bnxplevel.conf";
    xpcalcfile = "${confDir}/bnxpcalc.conf";
    topicfile = "${confDir}/topics.conf";
    command_groups_file = "${confDir}/command_groups.conf";
    tournament_file = "${confDir}/tournament.conf";
    aliasfile = "${confDir}/bnalias.conf";
    anongame_infos_file = "${confDir}/anongame_infos.conf";
    DBlayoutfile = "${confDir}/sql_DB_layout.conf";
    supportfile = "${confDir}/supportfile.conf";
    transfile = "${confDir}/address_translation.conf";
    customicons_file = "${confDir}/icons.conf";

    # These are resolved relative to i18ndir, not as paths.
    localizefile = "common.xml";
    motdfile = "bnmotd.txt";
    newsfile = "news.txt";
    helpfile = "bnhelp.conf";
    tosfile = "termsofservice.txt";
    localize_by_country = false;

    # StarCraft and Brood War only, plus CHAT so the bot protocol can log in
    # (see the botlogin note in README.md). STAR is StarCraft, SEXP is Brood
    # War, SSHR the shareware client and JSTR the Japanese build — the last two
    # cost nothing to allow and save a confusing rejection if anyone turns up
    # with one. Warcraft II/III and Diablo clients are refused at the door.
    allowed_clients = "STAR,SEXP,SSHR,JSTR,CHAT";

    # BWAPI injects into a running StarCraft.exe and does not modify the binary
    # on disk, so a BWAPI client should pass the normal hash check. These stay
    # permissive anyway: the version-check archives shipped with pvpgn are old,
    # and a rejected client gives a useless "unable to validate game version"
    # error with nothing in the journal to explain it. There is no ladder here
    # worth protecting from a patched client.
    allow_bad_version = true;
    allow_unknown_version = true;

    iconfile = "icons.bni";
    star_iconfile = "icons_STAR.bni";
    war3_iconfile = "icons-WAR3.bni";

    # Listen on all interfaces, default port 6112. Reachability is enforced by
    # the firewall rules below, not here.
    servaddrs = ":";

    new_accounts = true;
    max_accounts = 0;
    kick_old_login = true;
    ask_new_channel = true;
    report_all_games = true;
    report_diablo_games = false;
    hide_pass_games = true;
    hide_started_games = true;
    hide_temp_channels = true;
    disc_is_loss = false;
    ladder_games = "none";
    ladder_prefix = "";
    enable_conn_all = true;
    hide_addr = false;
    chanlog = false;

    usersync = 300;
    userflush = 3600;
    userstep = 100;
    userflush_connected = true;
    latency = 600;
    nullmsg = 120;
    shutdown_delay = 300;
    shutdown_decr = 60;

    # Flood protection: 5 lines per 5 seconds, 200 chars max.
    quota = "yes";
    quota_lines = 5;
    quota_time = 5;
    quota_wrapline = 40;
    quota_maxline = 200;
    quota_dobae = 10;

    mail_support = true;
    mail_quota = 5;
    log_notice = "*** Please note this channel is logged! ***";

    # Left at 0 (unlimited) because fail2ban is not watching bnetd and a
    # mistyped password locking out a friend on a LAN-only server is worse than
    # the brute-force risk. Raise if this is ever exposed publicly.
    passfail_count = 0;
    passfail_bantime = 300;

    maxusers_per_channel = 0;
    savebyname = true;
    sync_on_logoff = false;
    hashtable_size = 61;
    account_allowed_symbols = "-_[]";
    account_force_username = false;
    max_friends = 20;

    # Do not announce this server to the public PvPGN tracker list.
    track = 0;
    location = "unknown";
    description = "unknown";
    url = "https://github.com/pvpgn/pvpgn-server";
    contact_name = "a PvPGN user";
    contact_email = "unknown";

    max_connections = 1000;
    packet_limit = 1000;
    max_concurrent_logins = 0;
    use_keepalive = false;
    max_conns_per_IP = 0;
    initkill_timer = 120;

    clan_newer_time = 0;
    clan_max_members = 50;
    clan_channel_default_private = 0;
    clan_min_invites = 2;

    log_commands = true;
    log_command_groups = 2345678;
    log_command_list = "";
  };

  bnetdConfFile = pkgs.writeText "bnetd.conf" bnetdConf;
in {
  systemd.services.bnetd = {
    description = "PvPGN Battle.net server (bnetd)";
    wantedBy = ["multi-user.target"];
    after = ["network-online.target"];
    wants = ["network-online.target"];

    # bnban.conf is rewritten in place by the /ipban command, so it cannot live
    # in the store. Seed it once; never overwrite an existing one.
    preStart = ''
      if [ ! -e ${stateDir}/bnban.conf ]; then
        install -m 0644 ${pvpgn}/etc/pvpgn/bnban.conf ${stateDir}/bnban.conf
      fi

      # Generation 746 briefly ran with logfile = "stdout", which bnetd took
      # literally and created as a file in its working directory. Remove it.
      rm -f ${stateDir}/stdout
    '';

    serviceConfig = {
      # -f keeps bnetd in the foreground so systemd can supervise it directly.
      ExecStart = "${pvpgn}/sbin/bnetd -f -c ${bnetdConfFile}";
      Restart = "always";
      RestartSec = 5;

      User = "pvpgn";
      Group = "pvpgn";
      WorkingDirectory = stateDir;

      # /srv/data is on the ZFS pool, outside StateDirectory's /var/lib, so the
      # directory is created by tmpfiles below and allow-listed here.
      ReadWritePaths = [stateDir];

      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
      PrivateDevices = true;
      NoNewPrivileges = true;
      ProtectKernelTunables = true;
      ProtectKernelModules = true;
      ProtectControlGroups = true;
      RestrictNamespaces = true;
      RestrictSUIDSGID = true;
      LockPersonality = true;
      MemoryDenyWriteExecute = true;
      RestrictAddressFamilies = ["AF_INET" "AF_INET6"];
      SystemCallArchitectures = "native";
      SystemCallFilter = ["@system-service" "~@privileged"];
    };
  };

  users.users.pvpgn = {
    isSystemUser = true;
    group = "pvpgn";
    home = stateDir;
    description = "PvPGN Battle.net server";
  };
  users.groups.pvpgn = {};

  systemd.tmpfiles.rules = [
    "d ${stateDir}          0750 pvpgn pvpgn - -"
    "d ${stateDir}/reports  0750 pvpgn pvpgn - -"
    "d ${stateDir}/chanlogs 0750 pvpgn pvpgn - -"
    "d ${stateDir}/userlogs 0750 pvpgn pvpgn - -"
    "d ${stateDir}/bnmail   0750 pvpgn pvpgn - -"
    "d ${stateDir}/ladders  0750 pvpgn pvpgn - -"
    "d ${stateDir}/status   0750 pvpgn pvpgn - -"
    "d ${stateDir}/lua      0750 pvpgn pvpgn - -"
  ];

  # LAN and tailnet only. 6112/tcp is the Battle.net chat protocol; 6112/udp is
  # what StarCraft itself uses for game traffic once a lobby starts, and that
  # goes peer-to-peer between clients rather than through bnetd — but the server
  # also uses UDP 6112 to test whether a client is directly reachable, and
  # clients that fail the test get flagged as "plug" users. 6200 (w3route) is
  # Warcraft III only and is deliberately not opened.
  networking.firewall.interfaces = {
    eno1 = {
      allowedTCPPorts = [6112];
      allowedUDPPorts = [6112];
    };
    tailscale0 = {
      allowedTCPPorts = [6112];
      allowedUDPPorts = [6112];
    };
  };

  services.logrotate.settings.bnetd = {
    files = "${stateDir}/bnetd.log";
    frequency = "weekly";
    rotate = 8;
    compress = true;
    notifempty = true;
    missingok = true;
    su = "pvpgn pvpgn";
    create = "0640 pvpgn pvpgn";
    # bnetd holds the file open and has no reopen signal, so rotating out from
    # under it would leave it writing to the renamed inode forever.
    copytruncate = true;
  };

  # bnbot/bnchat are handy for testing botlogin accounts from sauron itself.
  environment.systemPackages = [pvpgn];
}
