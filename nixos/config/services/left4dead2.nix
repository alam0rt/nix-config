# left4dead2.nix
{config, pkgs, lib, ...}: let
	# Set to {id}-{branch}-{password} for betas.
	steam-app = "222860";
  group-id = "3246406";
  config = ''
    hostname "Wanky Server"
    rcon_password woofwoof

    // This states how players should contact you
    sv_contact sam@samlockart.com

    // # of rounds to play (versus)
    mp_roundlimit 2

    // Use a search key to find the server in the lobby
    sv_search_key "wankbank"
    sv_tags "omar"

    // STEAM GROUP
    sv_steamgroup ${group-id}

    //FRIENDLY FIRE 1=ON 0=OFF
    sm_cvar survivor_friendly_fire_factor_easy 1
    sm_cvar survivor_friendly_fire_factor_expert 1
    sm_cvar survivor_friendly_fire_factor_hard 1
    sm_cvar survivor_friendly_fire_factor_normal 1

    // CHEAT/CONFIG
    sv_lan 0
    sv_cheats 0
    sv_consistency 0
    sv_maxcmdrate 101
    sv_maxrate 30000

    //MOTD
    motd_enabled 1

    //GAME MODE
    sv_gametypes "coop, versus, mutation"
    sm_cvar mp_gamemode versus

    //DIFFICULTY
    //z_difficulty Normal

    //LOBBY CONNECT
    sv_allow_lobby_connect_only 0

    //BEBOP
    //l4d_maxplayers "8"
    //sv_maxplayers "8"
    //sm_cvar l4d_maxplayers "8"
    //sv_visiblemaxplayers "-1"
    //sm_cvar l4d_survivor_limit "8"
    //sm_cvar sv_removehumanlimit "1"

    //Game Settings

    mp_disable_autokick 1         //(command)prevents a userid from being auto-kicked (Usage mp_diable_autokick )
    sv_allow_wait_command 0        //default 1; Allow or disalow the wait command on clients connected to this server.
    sv_alternateticks 0        //defulat 0; (singleplayer)If set, server only simulates entities on even numbered ticks.
    sv_clearhinthistory 0        //(command)Clear memory of server side hint displayed to the player.
    sv_consistency 0        //default 1; Whether the server enforces file consistency for critical files
    sv_pausable 0            //default 0; is the server pausable
    sv_forcepreload 1        //default 0; Force server side preloading
    sv_pure_kick_clients 0        //default 1; If set to 1, the server will kick clients with mismatchng files. Otherwise, it will issue a warning to the client.
    sv_pure 0            //If set to 1, server will force all client files execpt whitelisted ones (in pure_server_whitelist.txt) to match server's files.
                    //If set to 2, the server will force all clietn files to come from steam and not load pure_server_whilelist.txt. Set to 0 for disabled.

    // Communication

    sv_voiceenable 1    //default 1; enable/disable voice comm
    sv_alltalk 1              //default 0; Players can hear all other players' voice communication, no team restrictions

    // Logging
    log on               //Creates a logfile (on | off)
    sv_logecho 0    //default 0; Echo log information to the console.
    sv_logfile 1       //default 1; Log server information in the log file.
    sv_log_onefile 0    //default 0; Log server information to only one file.
    sv_logbans 1         //default 0;Log server bans in the server logs.
    sv_logflush 0         //default 0; Flush the log files to disk on each write (slow).
    sv_logsdir logs      //Folder in the game directory where server logs will be stored.

    // Bans
    //  execute banned.cfgs at server start. Optimally at launch commandline.
    //exec banned_user.cfg  //loads banned users' ids
    //exec banned_ip.cfg      //loads banned users' ips
    writeip          // Save the ban list to banned_ip.cfg.
    writeid          // Wrties a list of permanently-banned user IDs to banned_user.cfg.

    //Network Tweaks - Increase network performance

    rate 10000              //default 10000; Max bytes/sec the host can recieve data
    sv_minrate 15000   //default "5000"; Min bandwidth rate allowed on server, 0 = unlimited
    sv_maxrate 30000   //default "0";  Max bandwidth rate allowed on server, 0 = unlimited
    sv_mincmdrate 20   //default 0; This sets the minimum value for cl_cmdrate. 0 = unlimited [cevo=67]
    sv_maxcmdrate 33    //default 40; (If sv_mincmdrate is > 0), this sets the maximum value for cl_cmdrate. [cevo=101]

    // Source: https://steamcommunity.com/app/550/discussions/0/2568690592375159630/
    //Infected improvement
    sm_cvar tank_stuck_time_suicide 30  //seconds before tank suicide if stuck
    sm_cvar director_tank_force_offer 1
    sm_cvar director_force_witch 1
    sm_cvar director_force_tank 1
    sm_cvar director_tank_max_interval 600
    sm_cvar director_tank_min_interval 200 //default 500
    sm_cvar director_threat_max_separation 5000
    sm_cvar director_threat_min_separation 500 //default 5000
    sm_cvar director_threat_radius 500 //default 1000
    sm_cvar director_max_threat_areas 8 //default 4
    sm_cvar versus_tank_flow_team_variation 0.0

    // Survivors bot improvement
    sm_cvar sb_friend_immobilized_reaction_time_normal 0 //bot reaction time when human get caught normal
    sm_cvar sb_friend_immobilized_reaction_time_hard 0 //bot reaction time when human get caught hard
    sm_cvar sb_friend_immobilized_reaction_time_expert 0 //bot reaction time when human get caught expert
    sm_cvar sb_friend_immobilized_reaction_time_vs 0 //bot reaction time when human get caught vs
    sm_cvar sb_max_team_melee_weapons 2 //bot take melee
    sm_cvar sb_melee_approach_victim 1 //bot use melee
    sm_cvar sb_sidestep_for_horde 1 //allow bot to seek better position for shooting infected
    sm_cvar sb_battlestation_human_hold_time 1 //How long the nearest human must hold their place before SurvivorBots will re-evaluate their Battlestations
    sm_cvar sb_normal_saccade_speed 115 //Better Aimbot
    sm_cvar sb_combat_saccade_speed 350 //Better Aimbot
    sm_cvar sb_toughness_buffer 30 //How much hp before a bot heal himself
    sm_cvar sb_separation_range 100 //distance between each survivors
    sm_cvar sb_max_scavenge_separation 750 //SurvivorBots wont scavenge items farther away from the group than this
  '';
  configFile = pkgs.writeTextFile {
    name = "config";
    executable = true;
    destination = "/cfg/server.cfg";
    text = config;
    };
in {
	imports = [
		./steam.nix
	];

  environment.systemPackages = with pkgs; [
    steam-run
  ];

	systemd.services.left4dead2 = {
		wantedBy = [ "multi-user.target" ];

		# Install the game before launching.
		wants = [ "steam@${steam-app}.service" ];
		after = [ "steam@${steam-app}.service" ];

		serviceConfig = {
			ExecStart = lib.escapeShellArgs [
				"${pkgs.steam-run}/bin/steam-run"
				"/var/lib/steam-app-${steam-app}/srcds_run"
				"-console"
				"-game" "left4dead2"
				"-ip" "0.0.0.0"
				"-port" "27015"
				"+exec" "${configFile}/cfg/server.cfg"
        "+map" "c1m1_hotel"
        "-debug"
        "-autoupdate"
			];
			Nice = "-5";
			PrivateTmp = true;
			Restart = "always";
			User = "steam";
			WorkingDirectory = "~";
		};
		environment = {
			SteamAppId = "222860";
      LD_LIBRARY_PATH = "/var/lib/steam-app-${steam-app}/bin:${pkgs.glibc}/lib";
		};
	};
}
