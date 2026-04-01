# Janitorr Declarative Setup Plan

Janitorr is a Kotlin/Spring Boot media library cleanup tool that connects to Sonarr, Radarr, Jellyfin, and Jellyseerr. It runs as an OCI container. No ports need to be exposed — it communicates outbound to the other services.

Reference: <https://github.com/Schaka/janitorr>

---

## Tagging Strategy

### Tags to create in Radarr and Sonarr

| Tag | Meaning |
|-----|---------|
| `janitorr-keep` | Permanent exclusion — content is never deleted by janitorr |

**Core principle:** Content requested via Jellyseerr gets *no tags* → follows the standard deletion schedule → is cleaned up first. Manually curated or admin-added content gets `janitorr-keep` → never deleted.

This achieves "jellyseerr requests considered first for cleanup" without any special Jellyseerr-specific logic: untagged content is the default deletion target.

### Deletion priority within untagged content

Janitorr evaluates untagged media using:
1. **Age** — grab date from Sonarr/Radarr history. Oldest content expires first.
2. **Rating** — lower-rated content has shorter retention periods (via `movie-expiration` / `season-expiration` tiered mapping). Lowest rated goes first.
3. **Watch recency** — if media was recently watched in Jellyfin, janitorr resets its age clock. Unwatched content is always targeted first.

### Operational workflow

- When adding content manually (not via Jellyseerr): apply `janitorr-keep` in Radarr/Sonarr.
- All Jellyseerr-requested content: leave untagged. Janitorr will clean it up per schedule.
- When janitorr deletes a movie/show, it also removes the associated Jellyseerr request (`delete-requests: true`).

---

## Secrets Strategy

The user's preference is for the bulk of the config to be declarative Nix, with only API keys encrypted via agenix. Spring Boot supports environment variable overrides for any config property, so we can:

- Write the static `application.yml` as a Nix string (no secrets, fully readable)
- Inject API keys via a single `environmentFiles` secret (`janitorr-env.age`)
- Spring Boot relaxed binding maps `CLIENTS_SONARR_APIKEY` → `clients.sonarr.api-key` automatically

**Contents of `nixos/sauron/media/janitorr-env.age`** (create with agenix-rekey):
```
CLIENTS_SONARR_APIKEY=<sonarr-api-key-value>
CLIENTS_RADARR_APIKEY=<radarr-api-key-value>
CLIENTS_JELLYFIN_APIKEY=<jellyfin-api-key-value>
CLIENTS_JELLYSEERR_APIKEY=<jellyseerr-api-key-value>
```

> The existing `sonarr-api-key` and `radarr-api-key` agenix secrets (used by recyclarr) can't be directly reused in env var format. Copy their values into this new consolidated env file.

Create with:
```bash
nix run '.#agenix-rekey.x86_64-linux.edit-view' -- nixos/sauron/media/janitorr-env.age
```

---

## application.yml (Static Nix Config)

Written as a Nix string — fully declarative, no secrets. Ports are interpolated from `config.services.*` at build time.

```yaml
server:
  port: 8978

logging:
  level:
    com.github.schaka: INFO
  file:
    name: "/logs/janitorr.log"

clients:
  sonarr:
    enabled: true
    base-url: "http://127.0.0.1:${toString config.services.sonarr.settings.server.port}"
    # api-key injected via CLIENTS_SONARR_APIKEY env var
  radarr:
    enabled: true
    base-url: "http://127.0.0.1:${toString config.services.radarr.settings.server.port}"
    # api-key injected via CLIENTS_RADARR_APIKEY env var
  jellyfin:
    enabled: true
    base-url: "http://127.0.0.1:8096"
    # api-key injected via CLIENTS_JELLYFIN_APIKEY env var
  jellyseerr:
    enabled: true
    base-url: "http://127.0.0.1:${toString config.services.jellyseerr.port}"
    # api-key injected via CLIENTS_JELLYSEERR_APIKEY env var

file-system:
  access: true
  validate-seeding: true
  free-space-check-dir: "/srv/media"

application:
  dry-run: true                     # FLIP TO FALSE after verifying dry-run logs
  run-once: true                    # exit after single scan; systemd timer drives schedule
  whole-tv-show: false
  leaving-soon: 7d                  # show in "Leaving Soon" collection 7 days before deletion
  leaving-soon-threshold-offset-percent: 5
  exclusion-tags:
    - "janitorr-keep"               # Radarr/Sonarr tag = permanent protection

media-deletion:
  enabled: true
  delete-requests: true             # remove Jellyseerr request when media is deleted

  # Movies: tiered retention by rating (lower = sooner deletion)
  # Rating scale is janitorr's internal 0–20 range
  movie-expiration:
    5: 30d     # very low rated: 30 days unwatched → deleted
    10: 60d    # below average: 60 days
    15: 90d    # average to good: 90 days
    20: 120d   # highly rated: 120 days

  # TV seasons: same tiered approach
  season-expiration:
    5: 30d
    10: 60d
    15: 90d
    20: 120d
```

---

## File Changes

### 1. `nixos/sauron/media/janitorr-env.age`

New agenix-encrypted file. See **Secrets Strategy** above.

### 2. `nixos/sauron/media/default.nix`

Add to the `let` block (requires `config` in scope, which it already has):
```nix
janitorrConfig = pkgs.writeText "janitorr-application.yml" ''
  server:
    port: 8978

  logging:
    level:
      com.github.schaka: INFO
    file:
      name: "/logs/janitorr.log"

  clients:
    sonarr:
      enabled: true
      base-url: "http://127.0.0.1:${toString config.services.sonarr.settings.server.port}"
    radarr:
      enabled: true
      base-url: "http://127.0.0.1:${toString config.services.radarr.settings.server.port}"
    jellyfin:
      enabled: true
      base-url: "http://127.0.0.1:8096"
    jellyseerr:
      enabled: true
      base-url: "http://127.0.0.1:${toString config.services.jellyseerr.port}"

  file-system:
    access: true
    validate-seeding: true
    free-space-check-dir: "/srv/media"

  application:
    dry-run: true
    run-once: true
    whole-tv-show: false
    leaving-soon: 7d
    leaving-soon-threshold-offset-percent: 5
    exclusion-tags:
      - "janitorr-keep"

  media-deletion:
    enabled: true
    delete-requests: true
    movie-expiration:
      5: 30d
      10: 60d
      15: 90d
      20: 120d
    season-expiration:
      5: 30d
      10: 60d
      15: 90d
      20: 120d
'';
```

Add agenix secret:
```nix
age.secrets."janitorr-env" = {
  rekeyFile = ./janitorr-env.age;
  mode = "0440";
};
```

Add OCI container (alongside `rarbg` and `flaresolverr`):
```nix
janitorr = {
  image = "ghcr.io/schaka/janitorr:jvm-stable";
  volumes = [
    "${janitorrConfig}:/config/application.yml:ro"
    "/srv/data/janitorr/logs:/logs"
    "/srv/media:/srv/media"
  ];
  environmentFiles = [config.age.secrets."janitorr-env".path];
  extraOptions = ["--network=host" "--memory=256m"];
  pull = "always";
  serviceName = "janitorr";
  autoStart = false;   # managed by systemd timer, not continuous
};
```

Add systemd timer for weekly execution (Sunday 03:00):
```nix
# Override the generated podman-janitorr service to be oneshot
systemd.services.podman-janitorr = {
  serviceConfig = {
    Type = lib.mkForce "oneshot";
    Restart = lib.mkForce "no";
  };
};

systemd.timers.janitorr = {
  description = "Weekly janitorr media cleanup";
  wantedBy = ["timers.target"];
  timerConfig = {
    OnCalendar = "Sun 03:00:00";
    Persistent = true;
    Unit = "podman-janitorr.service";
  };
};
```

### 3. Rekey secrets

```bash
nix run '.#agenix-rekey.x86_64-linux.rekey'
```

---

## Deployment Checklist

1. [ ] Create `janitorr-env.age` with 4 API keys in env var format
2. [ ] Create `janitorr-keep` tag in Radarr and Sonarr UIs
3. [ ] Tag manually curated/admin-added content with `janitorr-keep` in both apps
4. [ ] Add Nix changes to `default.nix` (secret, config, container, timer)
5. [ ] Rekey secrets
6. [ ] Deploy with `dry-run: true` first — check logs at `/srv/data/janitorr/logs/janitorr.log`
7. [ ] Verify "Leaving Soon" collection appears in Jellyfin (if configured)
8. [ ] Flip `dry-run: false` once logs look correct
9. [ ] Optionally: create `/srv/media/leaving-soon` dir and wire up a "Leaving Soon" Jellyfin library

---

## Open Questions

1. **Leaving Soon library** — Janitorr can populate a special Jellyfin library showing media about to be deleted. Worth setting up so users get a 7-day warning. Requires creating `/srv/media/leaving-soon` and adding it as a Jellyfin library.
2. **Jellyfin user account** — Janitorr may need a Jellyfin user (not just API key) with delete permissions for file-level deletion. Check janitorr docs for whether the API key alone suffices.
3. **Watch history** — Currently no Jellystat/Streamystats. Janitorr will use Jellyfin's built-in watch history via API, which is sufficient for basic use.
4. **Media path mapping** — Janitorr needs the same paths that Radarr/Sonarr use. Currently `/srv/media/movies` and `/srv/media/tv` — confirm these match what Sonarr/Radarr report in their API responses.

---

## Summary

| Item | Detail |
|------|--------|
| New files | `nixos/sauron/media/janitorr-env.age` |
| Modified files | `nixos/sauron/media/default.nix` |
| Container | `ghcr.io/schaka/janitorr:jvm-stable`, `--network=host`, no exposed ports |
| Secrets | Single env file (`janitorr-env.age`) with 4 API keys; rest of config is plain Nix |
| Schedule | Weekly, Sunday 03:00, via systemd timer; `run-once: true` so container exits cleanly |
| Jellyseerr cleanup | `delete-requests: true` — removes request from Jellyseerr when media is deleted |
| Tagging | `janitorr-keep` in Radarr/Sonarr protects content; untagged (Jellyseerr requests) cleaned up first |
| Deletion order | Oldest + lowest rated untagged content deleted first |
