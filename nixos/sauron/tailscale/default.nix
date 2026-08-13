{config, ...}: {
  age.secrets.tailscale-authkey.rekeyFile = ./authkey.age;
  services.tailscale.authKeyFile = config.age.secrets.tailscale-authkey.path;

  services.tailscale = {
    # Subnet router for the house. sauron sits on 192.168.1.0/24 via eno2
    # (192.168.1.110). Who may *use* the route is enforced tailnet-side by the
    # headscale ACL in ../ops-kube/base/headscale/policy.json — group:friends
    # gets 192.168.1.0/24:*, and autoApprovers (keyed on group:admin, which owns
    # this node via middleearth@) approves the route automatically.
    #
    # extraSetFlags, NOT extraUpFlags: tailscaled-autoconnect only runs
    # `tailscale up` when the backend state is NeedsLogin/NeedsMachineAuth/
    # Stopped. sauron is already Running, so anything in extraUpFlags would be
    # silently ignored. tailscaled-set runs `tailscale set` unconditionally on
    # every activation.
    extraSetFlags = ["--advertise-routes=192.168.1.0/24"];

    # Enables net.ipv4.conf.all.forwarding and net.ipv6.conf.all.forwarding.
    # Distinct from the net.ipv4.ip_forward key set in ../configuration.nix for
    # podman, so the two do not collide.
    useRoutingFeatures = "server";
  };

  # Deliberately no --snat-subnet-routes=false. sauron is not the LAN's default
  # gateway (192.168.1.1 is), so LAN hosts have no route back to 100.64.0.0/10;
  # without SNAT their replies would go to the router and be dropped. The
  # tradeoff is that LAN devices see this traffic as coming from 192.168.1.110
  # rather than the real tailnet client IP.
}
