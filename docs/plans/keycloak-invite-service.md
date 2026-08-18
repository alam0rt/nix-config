# keycloak-invite-service

Let a signed-in friend generate an invite link that provisions a new GoblinID
end to end: Keycloak account, `/friends` membership, and a Matrix registration
token. Replaces the current flow, where self-registration is open and approval
is Sam reading a `signup-notify` email and clicking through the Keycloak admin
console.

Status: **planned, nothing built.** Every fact below was checked against the
live config on 2026-08-18; the "verified" markers say how.

## Why this is smaller than it looks

`/friends` group membership is already the single lever for most of the estate.
Three of the four services need nothing new:

| Service | What an invite must do | Why |
|---|---|---|
| **Jellyfin** | nothing | The OIDC fork auto-provisions. `UserResolver.cs:79` calls `CreateUserAsync` on first login and `RbacService` maps the `friend` realm role onto libraries. |
| **Headscale (realm access)** | nothing | `oidc.allowed_groups` gates on `/friends`. |
| **Headscale (ACL `group:friends`)** | nothing — stays manual | Headscale does not map OIDC groups onto ACL groups (`ops-kube/docs/headscale-lan-subnet-router.md:240`). Needs a commit to `base/headscale/policy.json`. |
| **Matrix / MAS** | **issue a registration token** | `registration_token_required: true` is set on the Keycloak upstream provider itself. |

So the service's real job is: *create a Keycloak user, put them in `/friends`,
and mint one MAS token.* Everything else follows.

### The MAS finding, in full

Decrypting `ops-kube/clusters/omar/synapse/mas-secret.yaml` shows the gate is on
the upstream provider, not under `account:`:

```yaml
upstream_oauth2:
  providers:
    - id: "01HDWWR1EZ5STVX4Y5E1K53D4E"
      issuer: "https://auth.samlockart.com/realms/goblin"
      human_name: "GoblinID"
      # Gate Matrix account creation behind an invite token issued with
      # `mas-cli manage issue-user-registration-token`. A Keycloak account
      # alone is not enough to get a homeserver account.
      registration_token_required: true
```

A GoblinID on its own gets Jellyfin and the tailnet, but **not** Matrix. That is
deliberate and this plan keeps it — it just automates the token issuance.

## Architecture

Two new artefacts plus config changes in three repos.

```
github.com/alam0rt/keycloak-invite-service   Go service, tagged releases
nix-config/pkgs/keycloak-invite-service/     buildGoModule wrapper
nix-config/nixos/sauron/invite/              NixOS module + agenix secrets
nix-config/nixos/sauron/nginx/default.nix    public vhost
ops-kube/clusters/omar/synapse/              MAS admin API + tailnet exposure
```

The service runs **on sauron**, not in the omar cluster. That is a change from
the first sketch and it costs one thing: MAS's admin API has to become reachable
from sauron. Phase 1 solves that with the pattern already used for Keycloak's
admin console. In exchange, storage becomes SQLite instead of a CNPG database
and the vhost is a five-line addition to an nginx module that already exists.

### Hostname: `invite.iced.cool`

Not negotiable, and worth writing down because the obvious choices are both
wrong:

- **Not `*.middleearth.samlockart.com`.** `nixos/sauron/nginx/default.nix:19-28`
  asserts at build time that every vhost under that domain is listed in
  `services.nginx.tailscaleAuth.virtualHosts`. Invitees are by definition not on
  the tailnet, so a tailnet-only host cannot work.
- **Not `*.samlockart.com`.** That points at the omar cluster on Hetzner, not at
  sauron.

`iced.cool` is the domain sauron already serves publicly, with a wildcard ACME
cert. An explicit `invite.iced.cool` vhost takes precedence over the existing
regex `wildcard.iced.cool` server (nginx matches exact `server_name` before
regex), so the static-file wildcard is unaffected.

One public vhost serves both audiences. The inviter-facing pages are protected
by the service's own OIDC login plus a `friend` role check — not by
tailscaleAuth — because splitting them across two hosts buys nothing the role
check does not already give.

### Data

SQLite under `StateDirectory=`, one table:

```sql
CREATE TABLE invites (
  id                INTEGER PRIMARY KEY,
  token_hash        BLOB NOT NULL UNIQUE,   -- sha256; the link is a bearer credential
  inviter_sub       TEXT NOT NULL,
  inviter_username  TEXT NOT NULL,
  note              TEXT,
  created_at        INTEGER NOT NULL,
  expires_at        INTEGER NOT NULL,
  max_uses          INTEGER NOT NULL DEFAULT 1,
  used_count        INTEGER NOT NULL DEFAULT 0,
  revoked_at        INTEGER,
  redeemed_by_sub   TEXT,
  redeemed_at       INTEGER,
  provisioning_state TEXT,                  -- pending|keycloak_ok|group_ok|mas_ok|done|failed
  mas_token         TEXT
);
```

Store the hash, never the token.

## Phases

### Phase 0 — verify prerequisites

Two unknowns that change the design if they come back wrong. Do these before
writing code.

1. **Does the `goblin` realm have SMTP configured?** The plan mails invitees a
   Keycloak `execute-actions-email` (set password + verify email) rather than
   handling passwords itself. If SMTP is unset, that leg does not exist and the
   service must send the mail itself via SES, the way
   `ops-kube/clusters/omar/keycloak-extra/signup-notify.yaml` already does.

   ```bash
   kcadm get realms/goblin --fields smtpServer
   ```

   (Credentials and the kcadm alias: `ops-kube/docs/keycloak-admin-cli.md`.)

2. **Confirm the live MAS version.** `mas-deployment.yaml` says `0.8.0` and that
   tag is ignored — Flux image automation overrides it. As of this plan the real
   tag is `1.22.0`, set in `flux/clusters/omar/kustomization-synapse.yaml:21`.
   Re-check before relying on the admin API shape:

   ```bash
   kubectl get imagepolicy mas -n flux-system
   ```

### Phase 1 — expose the MAS admin API (ops-kube)

Independently testable, and useful on its own. Three edits to `mas-config` plus
one new pair of manifests.

**Verified:** `POST /api/admin/v1/user-registration-tokens` exists in MAS —
`crates/handlers/src/admin/v1/mod.rs:201` routes it to `list`/`add` handlers.
The request body is a direct match for invite semantics:

```rust
token: Option<String>,          // random if omitted
usage_limit: Option<u32>,       // → 1
expires_at: Option<DateTime<Utc>>,
```

It currently 404s because the API is not mounted, **not** because of the
version. The `web` listener serves `discovery, human, oauth, compat, graphql,
assets` and no `adminapi`.

1. **Mount it.** Add `- name: adminapi` to a listener in `mas-config`. The
   resource name is lowercase `adminapi` (`crates/config/src/sections/http.rs`
   uses `#[serde(tag = "name", rename_all = "lowercase")]` on the `AdminApi`
   variant); it serves at `/api/admin/v1`. Put it on a **new** listener bound to
   `[::]:8082`, not on `web` — mounting it on `web` publishes it to the internet
   and leaves nginx as the only thing standing in front of it, which is exactly
   the arrangement that already causes confusion with Keycloak's `/admin`.

2. **Add a client-credentials client.** `clients:` currently holds exactly one
   entry, `0000000000000000000SYNAPSE`. Add one for the invite service with
   `client_auth_method: client_secret_basic`, secret generated locally and
   committed SOPS-encrypted.

3. **Grant it admin.** `policy.data.admin_users` lists only `sammm`. A service
   account needs `admin_clients` instead — add the new client ID there.

4. **Publish it on the tailnet.** Copy
   `clusters/omar/keycloak-extra/admin-tailnet.yaml` verbatim in shape: a
   cert-manager `Certificate` for `mas-admin.middleearth.samlockart.com` via the
   `letsencrypt-production` DNS-01 issuer, and a `Service` with
   `loadBalancerClass: tailscale` and `tailscale.com/hostname: mas-admin`. That
   annotation is load-bearing — the default LoadBalancer class here provisions a
   *public* Hetzner LB.

5. Reconcile. MAS reads config once at startup and the config volume uses
   `subPath`, so the edit only lands because `mas-deployment.yaml` carries the
   `secret.reloader.stakater.com/reload: mas-config` annotation. Confirm the pod
   actually rolled.

**Done when:** from sauron,
`curl -s https://mas-admin.middleearth.samlockart.com/api/admin/v1/user-registration-tokens`
with a client-credentials token returns 200.

### Phase 2 — a dedicated Keycloak client (ops-kube)

Do **not** reuse the `realm-config` service account. It exists for hand-driven
administration and holds broad `realm-management` roles; the invite service
should have its own credential with its own rotation and a smaller blast radius.

Create a service-account client `invite-service` in `goblin` with only:

- `manage-users` — create users, set attributes, trigger action emails
- `query-groups` / `view-groups` — resolve the `/friends` group ID

Generate the secret locally and set it via the admin API rather than letting the
console mint it, so the value lands in SOPS *and* agenix instead of being read
back out of a web page. This is the same failure mode as audit finding H4.

Realm state is not versioned (finding L8) — record what was created in the
ops-kube "known state" section of `docs/keycloak-admin-cli.md`.

### Phase 3 — the Go service

New repo, `github.com/alam0rt/keycloak-invite-service`. No Nix knowledge in it;
it just needs to build with `go build` and carry tagged releases.

**Routes**

| Method | Path | Auth | Purpose |
|---|---|---|---|
| GET | `/` | optional | Signed out: "you need an invite". Signed in + `friend`: invite list. |
| GET | `/auth/login`, `/auth/callback`, `POST /auth/logout` | — | OIDC against `goblin` |
| POST | `/invites` | `friend` | Create; returns the link once, never again |
| POST | `/invites/{id}/revoke` | owner or admin | Revoke |
| GET | `/i/{token}` | none | Redeem form (username, email) |
| POST | `/i/{token}` | none | Provision |
| GET | `/healthz` | none | — |

**Provisioning, in order.** Each step is a separate failure domain; record
`provisioning_state` after each so a half-finished redemption is diagnosable.

1. **Claim the invite atomically.** Not read-then-write:

   ```sql
   UPDATE invites SET used_count = used_count + 1
   WHERE token_hash = ? AND used_count < max_uses
     AND revoked_at IS NULL AND expires_at > ?
   RETURNING id, inviter_sub;
   ```

   Zero rows → 410 Gone.

2. **Create the Keycloak user.** `POST /admin/realms/goblin/users`, `enabled:
   true`, `emailVerified: false`, attributes `invitedBy=<inviter_sub>` and
   `inviteId=<id>`. On 409 (username taken) release the claim — decrement
   `used_count` — and re-render the form with an error, so a typo does not burn
   the invite.

3. **Join `/friends`.** `PUT /admin/realms/goblin/users/{id}/groups/{groupId}`.

4. **Mint the MAS token.** `POST /api/admin/v1/user-registration-tokens` with
   `usage_limit: 1` and `expires_at` matching the invite. Store it on the row.

5. **Send the Keycloak action email.** `PUT
   /admin/realms/goblin/users/{id}/execute-actions-email` with
   `["UPDATE_PASSWORD","VERIFY_EMAIL"]`. Depends on Phase 0 item 1.

6. **Show the MAS token on the success page** and include it in the email —
   it is needed at Matrix signup, which happens later and elsewhere.

7. **Notify Sam** with the exact line to add to `base/headscale/policy.json`.
   The ACL commit stays human; the service's job is to make it a paste rather
   than a discovery.

**Rate limits**, per inviter, configurable: 3 live unredeemed invites, 5
redemptions per 30 days.

**Config** by environment variable, secrets by file path so they can come from
`$CREDENTIALS_DIRECTORY`:

```
INVITE_PUBLIC_URL, INVITE_LISTEN
KEYCLOAK_BASE_URL, KEYCLOAK_REALM, KEYCLOAK_CLIENT_ID, KEYCLOAK_CLIENT_SECRET_FILE
OIDC_CLIENT_ID, OIDC_CLIENT_SECRET_FILE, SESSION_KEY_FILE
MAS_ADMIN_URL, MAS_CLIENT_ID, MAS_CLIENT_SECRET_FILE
DB_PATH, FRIENDS_GROUP_PATH (default /friends)
```

### Phase 4 — packaging and deployment (nix-config)

1. **`pkgs/keycloak-invite-service/default.nix`** — `buildGoModule` +
   `fetchFromGitHub`, matching `pkgs/rolecule/default.nix` and
   `pkgs/scaffold/default.nix` exactly. Add the `callPackage` line to
   `pkgs/default.nix`.

   Chicken-and-egg: `fetchFromGitHub` needs a tag to exist first. Cut `v0.1.0`
   before the first build, and iterate locally with a path override rather than
   re-tagging for every change.

2. **`nixos/sauron/invite/default.nix`** — a systemd unit with
   `DynamicUser = true`, `StateDirectory = "keycloak-invite"`, and the three
   secrets handed over as **systemd credentials**, not `/run/agenix` paths:

   ```nix
   systemd.services.keycloak-invite.serviceConfig.LoadCredential = [
     "keycloak-client-secret:${config.age.secrets.invite-keycloak-secret.path}"
     "oidc-client-secret:${config.age.secrets.invite-oidc-secret.path}"
     "mas-client-secret:${config.age.secrets.invite-mas-secret.path}"
     "session-key:${config.age.secrets.invite-session-key.path}"
   ];
   ```

   This is not a stylistic choice. `DynamicUser=yes` means the uid does not exist
   when agenix installs secrets, so a 0400 root-owned file cannot be chowned to
   it and reads fail at *use* time rather than at startup — the service looks
   healthy and every request fails. That is exactly the Alertmanager bug fixed in
   `e9b5845`; the same trap, the same fix.

3. **agenix secrets** — four `.age` files in `nixos/sauron/invite/`, rekeyed per
   `nixos/config/secrets/agenix.md`.

4. **nginx vhost** in `nixos/sauron/nginx/default.nix`:

   ```nix
   virtualHosts."invite.iced.cool" = {
     forceSSL = true;
     useACMEHost = "iced.cool";
     locations."/".proxyPass = "http://127.0.0.1:8090";
   };
   ```

   No `tailscaleAuth` entry — it must not have one, and because the host is
   under `iced.cool` rather than `middleearth`, the build-time assertion does not
   demand one.

5. **Import** `./invite` in `nixos/sauron/configuration.nix`.

### Phase 5 — cutover

1. **Close self-registration.** `kcadm update realms/goblin -s
   registrationAllowed=false`. This is the actual security win: today the gate is
   Sam's inbox, and afterwards the invite is the only door.
2. **Repoint `signup-notify`.** Its REGISTER-event query goes quiet once
   self-registration is off. Keep the *pending users* half — users enabled and in
   no group — as a reconciliation backstop for redemptions that fail between
   steps 2 and 3, and drop the `mas-cli` instructions from the mail body.
3. Update `ops-kube/docs/keycloak-admin-cli.md` known-state and the security
   audit's L5/L8 notes.

## Deferred, deliberately

- **The headscale ACL commit stays manual.** Closing it properly means teaching
  something to reconcile `policy.json` from Keycloak group membership —
  `~/projects/headscale-controller` is the obvious home. Worth doing, but it is a
  separate piece of work and this plan is useful without it.
- **A Keycloak registration SPI.** The native-looking answer — a custom
  authenticator adding an invite-code field to Keycloak's own registration form —
  needs a Java provider jar and therefore a custom Keycloak image, replacing the
  stock operator image. Large permanent cost for one form field.
- **Keycloak Organizations invites (26.x).** Admin-issued only, so it does not
  satisfy "a signed-in friend generates the link".

## Fallback if Phase 1 stalls

If exposing the MAS admin API turns out to be more trouble than it is worth,
v1 can ship without it: issue a pool of tokens by hand,

```bash
kubectl exec -n matrix deploy/mas -- mas-cli manage \
  issue-user-registration-token --config /config.yaml --usage-limit 1
```

load them into the `invites` table, and have the service hand one out per
redemption. Zero new MAS surface, and Phase 1 can land later when the pool runs
dry. Phases 2–5 are unaffected.

## Effort

Roughly 600–800 lines of Go and ~150 lines of Nix, plus the ops-kube config.
A weekend to something working; the long tail is expiry sweeps, concurrent
redemption, and making the redeem form not embarrassing on a phone.
