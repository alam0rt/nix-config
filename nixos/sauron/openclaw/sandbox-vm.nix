{
  config,
  pkgs,
  inputs,
  ...
}: let
  sandboxBridge = "microvm";
  sandboxSubnet = "10.0.100";
  hostIp = "${sandboxSubnet}.1";
  vmIp = "${sandboxSubnet}.2";
  sshKeyDir = "/var/lib/openclaw/.ssh";
  sshKeyPath = "${sshKeyDir}/sandbox_ed25519";
in {
  # --- Host-side networking ---
  # Enable systemd-networkd for the virtual bridge only.
  # Traditional networking continues to manage eno2 and physical interfaces.
  systemd.network.enable = true;

  systemd.network.netdevs."10-${sandboxBridge}" = {
    netdevConfig = {
      Kind = "bridge";
      Name = sandboxBridge;
    };
  };

  systemd.network.networks."10-${sandboxBridge}" = {
    matchConfig.Name = sandboxBridge;
    networkConfig = {
      Address = ["${hostIp}/24"];
    };
    linkConfig.RequiredForOnline = "no";
  };

  # Attach MicroVM TAP interfaces to the bridge
  systemd.network.networks."11-microvm" = {
    matchConfig.Name = "vm-*";
    networkConfig.Bridge = sandboxBridge;
  };

  # --- NAT for MicroVM outbound ---
  networking.nat = {
    enable = true;
    externalInterface = "eno2";
    internalInterfaces = [sandboxBridge];
  };

  # --- Outbound filtering: DNS + HTTPS only ---
  networking.firewall.extraCommands = ''
    iptables -I FORWARD -i ${sandboxBridge} -o eno2 -p tcp --dport 443 -j ACCEPT
    iptables -I FORWARD -i ${sandboxBridge} -o eno2 -p tcp --dport 53 -j ACCEPT
    iptables -I FORWARD -i ${sandboxBridge} -o eno2 -p udp --dport 53 -j ACCEPT
    iptables -I FORWARD -i ${sandboxBridge} -o eno2 -j DROP
    iptables -I FORWARD -i eno2 -o ${sandboxBridge} -m state --state RELATED,ESTABLISHED -j ACCEPT
  '';

  # Allow DHCP on the bridge (for future VMs) and let host reach VM SSH
  networking.firewall.interfaces.${sandboxBridge} = {
    allowedTCPPorts = [22];
  };

  # --- SSH key auto-generation ---
  # Generates an ed25519 key pair for OpenClaw -> MicroVM SSH on first boot.
  # Persists in /var/lib/openclaw/.ssh/ across reboots.
  systemd.services.openclaw-sandbox-keygen = {
    description = "Generate SSH key for OpenClaw sandbox VM";
    wantedBy = ["multi-user.target"];
    before = ["microvm@openclaw-sandbox.service"];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      User = "openclaw";
      Group = "openclaw";
    };
    script = ''
      if [ ! -f "${sshKeyPath}" ]; then
        ${pkgs.coreutils}/bin/mkdir -p "${sshKeyDir}"
        ${pkgs.openssh}/bin/ssh-keygen -t ed25519 \
          -f "${sshKeyPath}" -N "" -C "openclaw-sandbox"
      fi
    '';
  };

  # --- MicroVM declaration ---
  microvm.autostart = ["openclaw-sandbox"];

  microvm.vms.openclaw-sandbox = {
    inherit pkgs;

    config = {
      microvm = {
        hypervisor = "qemu";
        mem = 1024;
        vcpu = 2;

        interfaces = [
          {
            type = "tap";
            id = "vm-sandbox";
            mac = "02:00:00:00:00:01";
          }
        ];

        shares = [
          {
            proto = "virtiofs";
            tag = "ro-store";
            source = "/nix/store";
            mountPoint = "/nix/.ro-store";
          }
          {
            proto = "virtiofs";
            tag = "workspace";
            source = "/var/lib/openclaw/workspace";
            mountPoint = "/workspace";
          }
          {
            proto = "virtiofs";
            tag = "ssh-keys";
            source = sshKeyDir;
            mountPoint = "/host-keys";
          }
        ];
      };

      # --- VM NixOS configuration ---
      networking.hostName = "openclaw-sandbox";

      systemd.network.enable = true;
      systemd.network.networks."20-lan" = {
        matchConfig.Type = "ether";
        networkConfig = {
          Address = ["${vmIp}/24"];
          Gateway = hostIp;
          DNS = [hostIp "1.1.1.1"];
          DHCP = "no";
        };
      };

      # Sandbox user with UID matching host openclaw user for virtiofs compat
      users.users.sandbox = {
        uid = 976;
        isNormalUser = false;
        home = "/home/sandbox";
        group = "sandbox";
      };
      users.groups.sandbox.gid = 976;

      services.openssh = {
        enable = true;
        settings = {
          PasswordAuthentication = false;
          KbdInteractiveAuthentication = false;
          PermitRootLogin = "no";
        };
        extraConfig = ''
          AuthorizedKeysFile /host-keys/sandbox_ed25519.pub
        '';
      };

      networking.firewall.allowedTCPPorts = [22];

      environment.systemPackages = with pkgs; [
        coreutils
        git
        curl
        jq
        python3
        ripgrep
        file
        gnutar
        gzip
        findutils
        gnugrep
        gnused
        procps
        iproute2
      ];

      system.stateVersion = "25.11";
    };
  };
}
