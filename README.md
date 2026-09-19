# Silence Ubuntu Updates

**Kill the Software Updater window. Keep `apt` under your control.**

Tested on **Ubuntu 24.04 LTS** (English desktop). The reference machine had already dropped Snap and masked PackageKit. A stock desktop install still has Snap, Ubuntu Pro APT hooks, fwupd, and (often) GNOME Software / App Center. Those extras are in the [stock desktop](#stock-ubuntu-2404-desktop-extras) section.

The Software & Updates GUI is incomplete. The *Automatically check for updates* menu can be set to *Never*, but *When there are security updates* and *When there are other updates* still refuse `Never`. GSettings keys such as `auto-launch` no longer exist on 24.04. The popup still comes back because Ubuntu splits the job across **APT periodic config**, **systemd timers**, **unattended-upgrades**, **PackageKit**, **update-notifier autostart**, and **MOTD scripts**.

This repository documents every layer that actually fires on 24.04, and the exact commands that shut them down.

> Security note: this disables *automatic* checks and *automatic* installs. You must run `sudo apt update && sudo apt upgrade` yourself. Unpatched systems are your problem after this.

---

## Why the GUI is not enough

| Layer | What it does | GUI can stop it? |
|---|---|---|
| `Software & Updates` → Updates tab | Writes a subset of APT periodic settings | Partially |
| `/etc/apt/apt.conf.d/10periodic` and `20auto-upgrades` | Daily `apt update` / unattended upgrade policy | No (not fully) |
| `apt-daily.timer` / `apt-daily-upgrade.timer` | Wake APT even if policy is sloppy | No |
| `unattended-upgrades.service` | Installs security updates in the background | No |
| `update-notifier` + `/etc/xdg/autostart/` | Opens the Software Updater window | No |
| `update-notifier-download.timer` / `update-notifier-motd.timer` | Refresh the "updates available" flag | No |
| `packagekit.service` | Desktop software stack talking to APT | No |
| `motd-news` + `/etc/update-motd.d/*` | Login / MOTD spam about updates and ESM | No |
| `com.ubuntu.update-notifier` GSettings | Notification + auto-launch interval | Only one key |

You need all of them quiet, or the window comes back.

---

## One-shot mute (copy and paste)

Run as your desktop user. `sudo` will ask for a password.

```bash
# 1. APT timers + unattended-upgrades
sudo systemctl stop    apt-daily.timer apt-daily-upgrade.timer unattended-upgrades
sudo systemctl disable apt-daily.timer apt-daily-upgrade.timer unattended-upgrades
sudo systemctl mask    apt-daily.timer apt-daily-upgrade.timer unattended-upgrades

# 2. APT periodic policy — never check, never download, never auto-upgrade
printf '%s\n' \
  'APT::Periodic::Update-Package-Lists "0";' \
  'APT::Periodic::Download-Upgradeable-Packages "0";' \
  'APT::Periodic::AutocleanInterval "0";' \
  'APT::Periodic::Unattended-Upgrade "0";' \
| sudo tee /etc/apt/apt.conf.d/10periodic /etc/apt/apt.conf.d/20auto-upgrades

# 3. MOTD news
sudo systemctl stop    motd-news.timer motd-news.service
sudo systemctl disable motd-news.timer motd-news.service
sudo systemctl mask    motd-news.timer motd-news.service
sudo chmod -x /etc/update-motd.d/50-motd-news \
              /etc/update-motd.d/90-updates-available \
              /etc/update-motd.d/91-release-upgrade \
              /etc/update-motd.d/91-contract-ua-esm-status \
              /etc/update-motd.d/92-unattended-upgrades \
              /etc/update-motd.d/95-hwe-eol \
              /etc/update-motd.d/98-reboot-required
sudo mkdir -p /var/lib/update-notifier /var/lib/ubuntu-advantage
sudo touch /var/lib/update-notifier/hide-esm-in-motd \
           /var/lib/ubuntu-advantage/hide-esm-in-motd
sudo rm -f /var/lib/motd-news/new \
           /var/lib/update-notifier/updates-available \
           /var/lib/update-notifier/updates-available-flag

# 4. PackageKit (already masked on some machines)
sudo systemctl stop    packagekit.service
sudo systemctl disable packagekit.service
sudo systemctl mask    packagekit.service

# 5. update-notifier systemd units (this is the one people miss)
sudo systemctl stop    update-notifier-download.timer update-notifier-motd.timer \
                       update-notifier-download.service update-notifier-motd.service
sudo systemctl disable update-notifier-download.timer update-notifier-motd.timer
sudo systemctl mask    update-notifier-download.timer update-notifier-motd.timer \
                       update-notifier-download.service update-notifier-motd.service

# 6. Per-user update-notifier paths
systemctl --user stop  update-notifier-crash.path update-notifier-livepatch.path \
                       update-notifier-release.path \
                       update-notifier-crash.service update-notifier-livepatch.service \
                       update-notifier-release.service
systemctl --user mask  update-notifier-crash.path update-notifier-livepatch.path \
                       update-notifier-release.path \
                       update-notifier-crash.service update-notifier-livepatch.service \
                       update-notifier-release.service

# 7. Kill the current GUI process and disable autostart
killall update-notifier update-manager 2>/dev/null || true
sudo mv -n /etc/xdg/autostart/update-notifier.desktop \
           /etc/xdg/autostart/update-notifier.desktop.disabled 2>/dev/null || true
sudo mv -n /etc/xdg/autostart/ubuntu-advantage-notification.desktop \
           /etc/xdg/autostart/ubuntu-advantage-notification.desktop.disabled 2>/dev/null || true
rm -rf ~/.cache/update-notifier

# 8. GSettings — 24.04 keys that still exist
gsettings set com.ubuntu.update-notifier no-show-notifications true
gsettings set com.ubuntu.update-notifier hide-reboot-notification true
gsettings set com.ubuntu.update-notifier notify-ubuntu-advantage-available false
gsettings set com.ubuntu.update-notifier show-livepatch-status-icon false
gsettings set com.ubuntu.update-notifier show-apport-crashes false
gsettings set com.ubuntu.update-notifier regular-auto-launch-interval 36500
```

`gsettings set com.ubuntu.update-notifier auto-launch false` **fails on 24.04**. The key is gone. Do not waste time on it.

Missing MOTD files (`88-esm-announce`, `/etc/default/motd-news`) are normal. Ignore `chmod: cannot access`. Commands are idempotent: they are safe on a machine that was already half-muted from the GUI.

---

## Stock Ubuntu 24.04 Desktop extras

The block above is enough to stop **Software Updater**. A *from-zero* desktop still has other nags. Add this if Snap / App Center / Ubuntu Pro / firmware banners are present.

```bash
# Snap auto-refresh (installed by default; skip if snap is gone)
if command -v snap >/dev/null 2>&1; then
  sudo snap refresh --hold=forever
  snap refresh --time
fi

# Ubuntu Pro APT hooks — fire on every `apt update`, not only via timers
sudo systemctl stop    apt-news.service esm-cache.service 2>/dev/null || true
sudo systemctl disable apt-news.service esm-cache.service 2>/dev/null || true
sudo systemctl mask    apt-news.service esm-cache.service
sudo pro config set apt_news=false 2>/dev/null || true

# Firmware metadata refresh (fwupd) — MOTD + background network
sudo systemctl stop    fwupd-refresh.timer fwupd-refresh.service 2>/dev/null || true
sudo systemctl disable fwupd-refresh.timer 2>/dev/null || true
sudo systemctl mask    fwupd-refresh.timer fwupd-refresh.service
sudo chmod -x /etc/update-motd.d/85-fwupd 2>/dev/null || true

# GNOME Software / App Center background download + notify
gsettings set org.gnome.software download-updates false 2>/dev/null || true
gsettings set org.gnome.software allow-updates false 2>/dev/null || true
```

`packagekit.service` is masked in the main block. On a virgin desktop it is *enabled*, not pre-masked. The mask is required there.

Do not purge `ubuntu-pro-client`. Desktop metapackages depend on it. Mask the services and set `apt_news=false`.

---

## Verify it is actually mute

```bash
echo '=== timers that must not appear ==='
systemctl list-timers --all --no-pager | grep -Ei 'apt|update|unattended|motd|packagekit' \
  || echo 'OK: no APT/update timers scheduled'

echo '=== unit state ==='
systemctl list-unit-files '*apt-daily*' '*unattended*' '*motd-news*' '*packagekit*' '*update-notifier*' --no-pager

echo '=== processes ==='
ps -eo pid,cmd | grep -Ei 'update-notifier|update-manager|unattended|packagekit' | grep -v grep \
  || echo 'OK: no update processes'

echo '=== APT policy ==='
apt-config dump APT::Periodic

echo '=== GSettings ==='
gsettings get com.ubuntu.update-notifier no-show-notifications
gsettings get com.ubuntu.update-notifier regular-auto-launch-interval

echo '=== autostart ==='
test -f /etc/xdg/autostart/update-notifier.desktop \
  && echo 'FAIL: autostart still enabled' \
  || echo 'OK: autostart disabled'
```

Expected:

- `list-timers` prints nothing matching `apt|update|unattended|motd|packagekit`
- timers and services above show `masked`
- `APT::Periodic::*` values are `"0"`
- `no-show-notifications` is `true`
- `regular-auto-launch-interval` is `36500`
- no `update-notifier` / `update-manager` process
- `/etc/xdg/autostart/update-notifier.desktop` is gone (renamed `.disabled`)

`apt-daily.service` and `packagekit-offline-update.service` may remain `static`. That is fine. A static unit without a timer does not wake up by itself.

Re-run the verify block after a reboot.

---

## What each piece is for

### APT periodic files

`/etc/apt/apt.conf.d/20auto-upgrades` is the on/off switch that `unattended-upgrades` and `apt.systemd.daily` read.

```
APT::Periodic::Update-Package-Lists "0";
APT::Periodic::Download-Upgradeable-Packages "0";
APT::Periodic::AutocleanInterval "0";
APT::Periodic::Unattended-Upgrade "0";
```

Write the same block to `10periodic` as well. Ubuntu ships both; leaving one at `"1"` re-enables daily checks.

Confirm the merged view, not just the file on disk:

```bash
apt-config dump APT::Periodic
```

### systemd timers

| Unit | Role |
|---|---|
| `apt-daily.timer` | Refresh package lists |
| `apt-daily-upgrade.timer` | Run unattended upgrades / cleanup |
| `unattended-upgrades.service` | Apply upgrades, including at shutdown |
| `motd-news.timer` | Fetch Canonical MOTD "news" |
| `update-notifier-download.timer` | Refresh the desktop "updates available" cache |
| `update-notifier-motd.timer` | Rewrite MOTD update counts |
| `packagekit.service` | Desktop package bus |

`mask` is required. `disable` alone is not enough: a package upgrade or `systemctl enable` can put the timer back. A mask is a symlink to `/dev/null`.

### Desktop notifier

Three independent launch paths:

1. `/etc/xdg/autostart/update-notifier.desktop` — starts at graphical login
2. `regular-auto-launch-interval` — days between Software Updater windows (default `14` even when “check for updates” is *Never*)
3. user units `update-notifier-*.path` — watch crash / livepatch / release files

Rename the `.desktop` files. Do not delete them; renaming keeps a revert path. Then kill the running process:

```bash
killall update-notifier update-manager
```

### MOTD

Scripts under `/etc/update-motd.d/` run at SSH / TTY login. Making them non-executable (`chmod -x`) is the reliable mute. Marker files:

```bash
sudo touch /var/lib/update-notifier/hide-esm-in-motd
sudo touch /var/lib/ubuntu-advantage/hide-esm-in-motd
```

stop Ubuntu Pro / ESM advertising in MOTD on 24.04.

---

## What not to do

- Do **not** purge `update-notifier` or `update-manager` unless you accept pulling desktop metapackages with them.
- Do **not** purge `unattended-upgrades` if you only want it stopped. Masking is enough and is reversible.
- Do **not** rely on `gsettings … auto-launch false`. The key does not exist on 24.04.
- Do **not** leave Snap refresh enabled on a stock desktop. Hold it (`sudo snap refresh --hold=forever`) or remove Snap.

---

## Revert

```bash
sudo systemctl unmask apt-daily.timer apt-daily-upgrade.timer unattended-upgrades \
                      motd-news.timer motd-news.service \
                      packagekit.service \
                      update-notifier-download.timer update-notifier-motd.timer \
                      update-notifier-download.service update-notifier-motd.service
sudo systemctl enable --now apt-daily.timer apt-daily-upgrade.timer

systemctl --user unmask update-notifier-crash.path update-notifier-livepatch.path \
                        update-notifier-release.path \
                        update-notifier-crash.service update-notifier-livepatch.service \
                        update-notifier-release.service

sudo mv /etc/xdg/autostart/update-notifier.desktop.disabled \
        /etc/xdg/autostart/update-notifier.desktop
sudo mv /etc/xdg/autostart/ubuntu-advantage-notification.desktop.disabled \
        /etc/xdg/autostart/ubuntu-advantage-notification.desktop

sudo chmod +x /etc/update-motd.d/50-motd-news \
              /etc/update-motd.d/90-updates-available \
              /etc/update-motd.d/91-release-upgrade \
              /etc/update-motd.d/91-contract-ua-esm-status \
              /etc/update-motd.d/92-unattended-upgrades \
              /etc/update-motd.d/95-hwe-eol \
              /etc/update-motd.d/98-reboot-required

gsettings reset-recursively com.ubuntu.update-notifier
```

Restore APT periodic values to `"1"` in `/etc/apt/apt.conf.d/20auto-upgrades` if you want unattended upgrades back.

---

## Manual updates after this

```bash
sudo apt update
sudo apt upgrade
```

That is the entire remaining interface. No window, no tray nag, no daily APT lock stealing `/var/lib/dpkg/lock-frontend` while you compile.

---

## Scope

- Confirmed: Ubuntu 24.04 LTS desktop, systemd, English UI.
- Not tested here: Ubuntu 22.04, 25.10, 26.04. Unit names drift. Check `systemctl list-unit-files '*update-notifier*'` before masking.
- Snap / App Center / Ubuntu Pro / fwupd: covered in the stock-desktop section. Not present on the Snap-less reference host.
- Flatpak: not covered (`flatpak remote-ls --updates` is separate).
- Previous GUI clicks do not conflict. The files and masks overwrite them.

MIT. Use at your own risk.
