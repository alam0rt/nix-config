# Janitorr Declarative Setup Plan

Janitorr is a Kotlin-based media library cleanup tool that connects to Sonarr, Radarr, Jellyfin, and Jellyseerr. It runs as an OCI container with a single `application.yml` config mounted at `/config/application.yml`. No ports need to be exposed — it communicates outbound to the other services.

Reference: <https://github.com/Schaka/janitorr>

## File Changes

### 1. Create `nixos/sauron/media/janitorr-application.yml.age`

NOTE: WE SHOULD HAVE THE CONFIG STORED AS NIX CONFIG WITH SECRETS MERGED IN AFTERWARDS (that way the entire config is not opaque)

Agenix-encrypted secret containing the full Janitorr `application.yml`. Contents based on the upstream `application-template.yml`, configured for our stack:

```yaml
server:
  port: 8978

clients:
  sonarr:
    enabled: true
    base-url: "http://127.0.0.1:<sonarr-port>"
    api-key: "<secret>"
  radarr:
    enabled: true
    base-url: "http://127.0.0.1:<radarr-port>"
    api-key: "<secret>"
  jellyfin:
    enabled: true
    base-url: "http://127.0.0.1:8096"
    api-key: "<secret>"
  jellyseerr:
    enabled: true
    base-url: "http://127.0.0.1:<jellyseerr-port>"
    api-key: "<secret>"

# Retention/cleanup rules TBD
```

Create with:
```bash
nix run '.#agenix-rekey.x86_64-linux.edit-view' -- nixos/sauron/media/janitorr-application.yml.age
```

### 2. Modify `nixos/sauron/media/default.nix`

Add the agenix secret declaration alongside the existing sonarr/radarr API key secrets:

```nix
age.secrets."janitorr-application.yml" = {
  rekeyFile = ./janitorr-application.yml.age;
};
```

Add the OCI container definition alongside existing `rarbg` and `flaresolverr` containers:

```nix
virtualisation.oci-containers.containers.janitorr = {
  image = "ghcr.io/schaka/janitorr:jvm-stable";
  volumes = [
    "${config.age.secrets."janitorr-application.yml".path}:/config/application.yml:ro"
  ];
  extraOptions = ["--network=host"];
  pull = "always";
  serviceName = "janitorr";
};
```

Using `--network=host` so it can reach Sonarr, Radarr, Jellyfin, and Jellyseerr on localhost.

### 3. Rekey secrets

After creating the `.age` file:
```bash
nix run '.#agenix-rekey.x86_64-linux.rekey'
```

## Secret Strategy

The entire `application.yml` is stored as a single agenix secret. This is simpler than templating individual API keys at runtime, and the container just mounts the decrypted file read-only.

Alternative considered: using a systemd `ExecStartPre` to template secrets into the config (like recyclarr's `_secret` pattern). Rejected because the container pattern doesn't support it natively and it adds unnecessary complexity.

## Decision Points

1. **Retention/cleanup rules** — Core value of Janitorr. Need to decide on expiration policies for movies/shows (e.g., delete after X days unwatched). These go into the `application.yml`.
2. **Watch history source** — Janitorr can use Jellystat or Streamystats for watch history. Determine whether to use Jellyfin's built-in data or add one of these.
3. **File placement** — Plan keeps everything in `media/` since it's just one container + one secret. Could split into `nixos/sauron/janitorr/` if it grows.

## Summary

| Item | Detail |
|---|---|
| New files | `nixos/sauron/media/janitorr-application.yml.age` |
| Modified files | `nixos/sauron/media/default.nix` |
| Container | `ghcr.io/schaka/janitorr:jvm-stable`, `--network=host`, no ports |
| Secrets | Single agenix secret for the full `application.yml` |
| Dependencies | Sonarr, Radarr, Jellyfin, Jellyseerr (all already running on sauron) |
