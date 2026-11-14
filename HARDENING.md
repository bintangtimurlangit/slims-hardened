# slims-hardened

A fork of [SLiMS 9 Bulian](https://github.com/slims/slims9_bulian) with a locked-down container image. The SLiMS code is unchanged apart from one line (session cookie, below), so upstream releases merge cleanly.

Image: `ghcr.io/bintangtimurlangit/slims-hardened:<slims version>` (for example `9.8.0`). It is rebuilt on every push to `hardened` and on the 1st of each month, so PHP and Apache security patches arrive without code changes.

## What changes compared to upstream's Docker setup

**Image**
- Built on the current `php:8.3-apache` instead of a pinned 2024 release.
- Composer runs only in a build stage, so Composer and its tooling are not in the final image.
- `composer audit` runs during the build, and the build fails if any dependency has a known advisory.
- `setasign/fpdi` is bumped past CVE-2026-45802.
- The stock `ifsnop/mysqldump-php` is left out of `vendor/`. SLiMS ships its own patched copy in `lib/`, and the stock one broke System > Backup with "Empty DSN string".
- PEAR `File_MARC` is installed, so Bibliography > MARC Import works.
- The installer is removed.

**Runs without root**
- Apache listens on 8080 and runs as `www-data`.
- Code is owned by root and read-only to the web server. Only `files/`, `images/`, `repository/` and `config/` are writable.

**PHP** (`docker/php-hardening.ini`)
- `exec`, `shell_exec`, `system`, `passthru`, `proc_open`, `popen`, `pcntl_exec`, `dl` and `show_source` are disabled. SLiMS 9.8 only uses `exec` to gzip backups and checks for it first, so backups are still made, just as plain `.sql`.
- `open_basedir` is limited to the app, `/tmp` and the PEAR library path.
- PHP version is hidden, errors are not displayed, and sessions use strict mode with HttpOnly and SameSite cookies.

**Apache** (`docker/apache-hardening.conf`)
- `images/`, `files/` and `repository/` never execute code, whatever the file extension.
- Denied from the web: `config/`, `vendor/`, `src/`, `lib/` (except the thumbnail generator), `api/`, `repository/` (served through PHP), `files/backup`, `files/cache`, `files/chat`, `install/`, `upgrade/`, `indexing_engine/`, dotfiles, `*.inc.php`, `*.sql`, `*.md`, OAI-PMH and the chat server.
- The real client IP is taken from `CF-Connecting-IP`, and only from private (proxy) addresses.
- Server tokens are hidden and TRACE is disabled.

**Code**
- `sysconfig.inc.php`: the session cookie is marked `Secure` whenever the visitor is on HTTPS. Upstream hard-coded `false`.

**Entrypoint**
- No longer prints the database password to the logs.
- Writes `config/url.php` so links use `https://` when `FORCE_HTTPS=1`.
- Accepts `ADMIN_INITIAL_PASSWORD` for the first start. Otherwise it generates a password and prints it once.

## Deploying

`deploy/compose.yaml` runs one library: the app plus MariaDB 11.8.
- The database is on an internal network.
- The app is reachable only over the `<library>-edge` network, which the reverse proxy joins. That network is internal too, so the app has no outbound internet access.
- The app runs with `cap_drop: ALL` and `no-new-privileges`, under memory and process limits.

Copy `deploy/.env.example` to `.env` and fill it in.

## Updating from upstream

```sh
git fetch upstream --tags
git merge v9.x.y          # new upstream release
git push                  # CI builds and pushes the new image
```
