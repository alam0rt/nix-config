# Ebook library (Calibre + calibre-web → KOReader on the Kindle)

All open source: [Calibre](https://calibre-ebook.com) (GPL-3) owns the
library, [calibre-web](https://github.com/janeczku/calibre-web) (GPL-3,
nixpkgs `services.calibre-web`) serves it, and
[KOReader](https://koreader.rocks) (AGPL-3, launched from KUAL) reads it on
the Kindle over OPDS. Nothing goes through Amazon: no Send-to-Kindle email, no
Amazon account needed on the device.

| What                 | Where                                                |
| -------------------- | ---------------------------------------------------- |
| Web UI / OPDS        | `https://books.iced.cool`, OPDS at `/opds`           |
| Calibre library      | `/srv/data/calibre/library` (`metadata.db` + files)  |
| calibre-web state    | `/srv/data/calibre-web/app.db` (users, shelves, settings) |
| Drop folder          | `\\sauron\public\books-inbox` (= `/srv/share/public/books-inbox`) |
| Rejects              | `\\sauron\public\books-failed`                       |

Both `/srv/data` paths are in the hourly borg `srv-data` job.

## First deploy

1. Generate the admin password secret (YubiKey), then rekey:

   ```bash
   nix run '.#agenix-rekey.x86_64-linux.generate'
   nix run '.#agenix-rekey.x86_64-linux.rekey'
   ```

   The build fails until `calibre-web-admin.age` exists. That's deliberate:
   calibre-web ships with `admin` / `admin123` and the vhost is public, so
   every start sets the `admin` password from this secret. A password changed in
   the web UI is put back on the next restart, so change the secret instead.
   Read it with `edit-view`.

2. Check that `books.iced.cool` resolves to sauron (nginx's `*.iced.cool`
   wildcard vhost suggests the DNS is a wildcard too).

3. Log in as `admin`. Under *Admin → Edit Basic Configuration → Feature
   Configuration*, leave **anonymous browsing off**: with it off, OPDS needs
   HTTP basic auth, and that login is the only thing protecting the library.
   Create a normal (non-admin) user for the Kindle and give it the
   *Download* permission.

## Adding books

- **Drop folder.** Copy files (or whole folders) into `books-inbox` over SMB.
  `calibre-ingest.path` notices; `calibredb add` imports each file and deletes
  it once it's in the library, or already was. Anything calibre won't take is
  moved to `books-failed`. Dotfiles are ignored. A timer re-runs the import
  every 10 minutes, so files that were still copying get picked up later.
  Logs: `journalctl -u calibre-ingest`.
- **Web upload.** Use the upload button in calibre-web (enabled; up to 500 MB).
- Both write the same `metadata.db`. Edit metadata and covers in calibre-web
  (*Edit metadata → fetch metadata*).

## On the Kindle (KOReader)

Install KOReader through KUAL if it isn't already, then in KOReader's file
browser:

1. **Search (magnifier) → OPDS catalog → +**: URL
   `https://books.iced.cool/opds/new`, plus the Kindle user's name and
   password. Tick **Sync catalog**. Use the `/new` feed (newest first), not the
   root `/opds`. The reason is below.
2. Browse and tap a book to download it. KOReader reads EPUB natively, so no
   conversion is needed.
3. **To pull new books automatically:** long-press the catalog → *Set sync
   folder* (for example `/mnt/us/books`). From the top-left menu of the catalog
   list, set *File types to sync* to `epub` (otherwise each book comes in
   whichever format calibre-web lists first) and *Set max number of files to
   sync* (default 50). *Sync all catalogs* turns Wi-Fi on if it needs to, then
   downloads every book added since the last sync.
   - KOReader's sync assumes the feed is newest-first. It walks from the top
     until it reaches the last book it downloaded. `/opds/new` is ordered by
     date added, so that works. **Shelf feeds (`/opds/shelf/<id>`) don't:**
     they are in shelf order, oldest first, so after the first sync they always
     look up to date.
   - Tagging an *old* book doesn't move it up `/opds/new`. Only newly imported
     books sync. Download older ones by hand, or use *Force sync*, which walks
     the feed again from the top (up to the max).
   - To run it hands-free, create a KOReader *Profile* (Tools → Profiles) with
     the action *Sync all OPDS catalogs* and set it to auto-execute *on
     wake-up*, or bind the action to a gesture.

### If you'd rather read in the stock Kindle reader

The stock reader doesn't do EPUB. Use calibre-web's *Convert* on the book page
to make an AZW3 (conversion is enabled), then in KOReader download the AZW3 into
`/mnt/us/documents/`. The Kindle indexes it like any sideloaded book.

## Not set up (yet)

- **Reading-progress sync** (KOReader *Progress sync*) needs a kosync server.
  Only worth it if you also read on a phone or a second device. The official
  [koreader-sync-server](https://github.com/koreader/koreader-sync-server)
  (AGPL, container) works. Calibre-Web-Automated has one built in. It isn't in
  nixpkgs.
- **Calibre-Web-Automated** (GPL-3) is a calibre-web fork with a richer ingest
  pipeline: auto-convert, metadata fetch on import, kosync. It's a
  container-only image, though, and stock calibre-web from nixpkgs plus the
  small ingest unit here covers the same core need without that. Both read the
  same `app.db` and library, so switching later is a migration, not a rebuild.
- **Booklore** is out. Reports say its repo was taken down in early 2026 after
  a dispute over a move away from AGPL. The community fork **Grimmory** (AGPL)
  carries it on if you want a more modern UI later.

## Caveats

- `enableBookConversion` runs `ebook-convert` inside calibre-web's hardened
  unit (`MemoryDenyWriteExecute`, `ProtectSystem=strict`). It hasn't been tried
  here. If conversions fail, check `journalctl -u calibre-web` first.
- The inbox is on the guest-writable `public` share, so anyone on the LAN or
  tailnet can add books. Nobody outside can.
