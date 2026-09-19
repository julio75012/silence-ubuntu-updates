# Silence Ubuntu Updates

Kill the Software Updater window and every background update check on **Ubuntu 24.04 LTS**. After this, updates run only when you type `sudo apt update && sudo apt upgrade`.

> This disables automatic security installs. You are responsible for applying patches yourself.

The Software & Updates GUI cannot do this. *Automatically check for updates* accepts *Never*, but *When there are security updates* and *When there are other updates* do not. The key `com.ubuntu.update-notifier auto-launch` does not exist on 24.04.

---

## Ubuntu 24.04 LTS defaults vs muted

Stock column = Noble Desktop packaging (verified against 24.04.4 unit files and schemas). Server is the same APT stack without GNOME Software / App Center.

| Component | Stock 24.04 LTS | Muted |
|---|---|---|
| `/etc/apt/apt.conf.d/20auto-upgrades` | `Update-Package-Lists "1"`; `Unattended-Upgrade "1"` | both `"0"` |
| `/etc/apt/apt.conf.d/10periodic` (`update-notifier-common`) | `Update-Package-Lists "1"`; `Unattended-Upgrade "1"` | all four periodic keys `"0"` |
| `/etc/apt/apt.conf.d/20apt-esm-hook.conf` | present; starts `apt-news` / `esm-cache` on `apt update` | file stays; units masked |
| `apt-daily.timer` | enabled | masked |
| `apt-daily-upgrade.timer` | enabled | masked |
| `unattended-upgrades.service` | enabled | masked |
| `update-notifier-download.timer` | enabled | masked |
| `update-notifier-motd.timer` | enabled | masked |
| `motd-news.timer` / `motd-news.service` | enabled (`/etc/default/motd-news` often **absent** on Desktop) | masked |
| `packagekit.service` | enabled (D-Bus activate) | masked |
| `fwupd-refresh.timer` | enabled; `fwupd` daemon running | masked |
| `apt-news.service` / `esm-cache.service` | static (started by the ESM APT hook) | masked |
| `/etc/xdg/autostart/update-notifier.desktop` | installed | renamed `.disabled` |
| `/etc/xdg/autostart/ubuntu-advantage-notification.desktop` | installed | renamed `.disabled` |
| user units `update-notifier-*.path` | wanted by `graphical-session.target` | masked |
| `com.ubuntu.update-notifier no-show-notifications` | `false` | `true` |
| `com.ubuntu.update-notifier regular-auto-launch-interval` | `7` | `36500` |
| `com.ubuntu.update-notifier hide-reboot-notification` | `false` | `true` |
| `com.ubuntu.update-notifier notify-ubuntu-advantage-available` | `true` | `false` |
| MOTD `50-motd-news`, `90-updates-available`, `91-release-upgrade`, `91-contract-ua-esm-status`, `92-unattended-upgrades`, `95-hwe-eol`, `98-reboot-required`, `85-fwupd` | executable | `chmod -x` |
| MOTD `00-header`, `10-help-text`, `98-fsck-at-reboot` | executable | leave as-is (not update nags) |
| Snap refresh | `00:00~24:00/4` if `snapd` is installed | `snap refresh --hold=forever` or no `snap` binary |
| `org.gnome.software` download/allow-updates | `true` only if the schema exists | `false`, or skip if schema missing |
| Ubuntu Pro | client installed; machine may be unattached | stay unattached; mask hooks |

These units stay `static` and are not a leak by themselves: `apt-daily.service`, `apt-daily-upgrade.service`, `packagekit-offline-update.service`, `fwupd-refresh.service`. They run only if a timer or an APT hook starts them.

---

## What remains if you only mute APT + Software Updater

A 24.04.4 machine that has masked the APT / update-notifier stack but has **not** yet applied the firmware and Pro hooks still shows:

- `fwupd-refresh.timer` **enabled and scheduled**
- `/usr/libexec/fwupd/fwupd` running
- `/etc/update-motd.d/85-fwupd` still executable
- `apt-news.service` and `esm-cache.service` **static** (the next `sudo apt update` can start them via `20apt-esm-hook.conf`)

Those three items are independent of Software Updater. The apply block below covers them.

`88-esm-announce` is not shipped on 24.04. Ignore `chmod: cannot access` for missing MOTD files.

---

## Apply (copy and paste)

Run as the desktop user. `sudo` will prompt once.

```bash
# APT timers + unattended-upgrades
sudo systemctl stop    apt-daily.timer apt-daily-upgrade.timer unattended-upgrades
sudo systemctl disable apt-daily.timer apt-daily-upgrade.timer unattended-upgrades
sudo systemctl mask    apt-daily.timer apt-daily-upgrade.timer unattended-upgrades

# Periodic policy
printf '%s\n' \
  'APT::Periodic::Update-Package-Lists "0";' \
  'APT::Periodic::Download-Upgradeable-Packages "0";' \
  'APT::Periodic::AutocleanInterval "0";' \
  'APT::Periodic::Unattended-Upgrade "0";' \
| sudo tee /etc/apt/apt.conf.d/10periodic /etc/apt/apt.conf.d/20auto-upgrades

# MOTD news + update MOTD scripts
sudo systemctl stop    motd-news.timer motd-news.service
sudo systemctl disable motd-news.timer motd-news.service
sudo systemctl mask    motd-news.timer motd-news.service
if [ -f /etc/default/motd-news ]; then sudo sed -i 's/^ENABLED=.*/ENABLED=0/' /etc/default/motd-news; fi
sudo chmod -x /etc/update-motd.d/50-motd-news \
              /etc/update-motd.d/85-fwupd \
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

# PackageKit
sudo systemctl stop    packagekit.service
sudo systemctl disable packagekit.service
sudo systemctl mask    packagekit.service

# update-notifier system timers (package: update-notifier-common)
sudo systemctl stop    update-notifier-download.timer update-notifier-motd.timer \
                       update-notifier-download.service update-notifier-motd.service
sudo systemctl disable update-notifier-download.timer update-notifier-motd.timer
sudo systemctl mask    update-notifier-download.timer update-notifier-motd.timer \
                       update-notifier-download.service update-notifier-motd.service

# update-notifier user paths (package: update-notifier)
systemctl --user stop  update-notifier-crash.path update-notifier-livepatch.path \
                       update-notifier-release.path \
                       update-notifier-crash.service update-notifier-livepatch.service \
                       update-notifier-release.service
systemctl --user mask  update-notifier-crash.path update-notifier-livepatch.path \
                       update-notifier-release.path \
                       update-notifier-crash.service update-notifier-livepatch.service \
                       update-notifier-release.service

# Autostart
killall update-notifier update-manager 2>/dev/null || true
sudo mv -n /etc/xdg/autostart/update-notifier.desktop \
           /etc/xdg/autostart/update-notifier.desktop.disabled 2>/dev/null || true
sudo mv -n /etc/xdg/autostart/ubuntu-advantage-notification.desktop \
           /etc/xdg/autostart/ubuntu-advantage-notification.desktop.disabled 2>/dev/null || true
rm -rf ~/.cache/update-notifier

# GSettings — keys shipped by 24.04 (auto-launch does not exist)
gsettings set com.ubuntu.update-notifier no-show-notifications true
gsettings set com.ubuntu.update-notifier hide-reboot-notification true
gsettings set com.ubuntu.update-notifier notify-ubuntu-advantage-available false
gsettings set com.ubuntu.update-notifier show-livepatch-status-icon false
gsettings set com.ubuntu.update-notifier show-apport-crashes false
gsettings set com.ubuntu.update-notifier regular-auto-launch-interval 36500
gsettings set org.gnome.software download-updates false 2>/dev/null || true
gsettings set org.gnome.software allow-updates false 2>/dev/null || true

# Ubuntu Pro APT hooks
sudo systemctl stop    apt-news.service esm-cache.service 2>/dev/null || true
sudo systemctl mask    apt-news.service esm-cache.service
sudo pro config set apt_news=false 2>/dev/null || true

# Firmware metadata (independent of APT)
sudo systemctl stop    fwupd-refresh.timer fwupd-refresh.service 2>/dev/null || true
sudo systemctl disable fwupd-refresh.timer 2>/dev/null || true
sudo systemctl mask    fwupd-refresh.timer fwupd-refresh.service

# Snap (no-op if snapd is absent)
if command -v snap >/dev/null 2>&1; then
  sudo snap refresh --hold=forever
fi
```

Same steps live in [`scripts/mute-ubuntu-updates.sh`](scripts/mute-ubuntu-updates.sh). The script is idempotent.

---

## Verify

```bash
bash scripts/verify-muted.sh
```

Or:

```bash
systemctl list-timers --all --no-pager | grep -Ei 'apt|update|unattended|motd|packagekit|fwupd-refresh' \
  || echo 'OK: no update timers scheduled'
apt-config dump APT::Periodic
gsettings get com.ubuntu.update-notifier no-show-notifications
gsettings get com.ubuntu.update-notifier regular-auto-launch-interval
test -f /etc/xdg/autostart/update-notifier.desktop && echo FAIL || echo 'OK: autostart off'
systemctl is-enabled fwupd-refresh.timer
systemctl is-masked apt-news.service esm-cache.service
```

Expect `APT::Periodic::*` = `"0"`, `no-show-notifications` = `true`, interval = `36500`, `fwupd-refresh.timer` masked, `apt-news` / `esm-cache` masked, autostart file renamed.

---

## What each layer does

**`20auto-upgrades` / `10periodic`** — read by `/usr/lib/apt/apt.systemd.daily`. Write both; one leftover `"1"` re-enables the job.

**Timers** — `mask` points the unit at `/dev/null` so a package upgrade cannot re-enable it.

**Desktop notifier** — three launch paths: xdg autostart, `regular-auto-launch-interval` (schema default 7 days; security still launches immediately), user `.path` units.

**`20apt-esm-hook.conf`** — do not delete `ubuntu-pro-client`. Mask `apt-news` and `esm-cache` so the hook cannot start them.

**fwupd** — separate daemon and timer. Software Updater mute does not touch it.

**Snap** — separate from APT. Four checks per day on stock Desktop until held or removed.

---

## Do not

- Purge `update-notifier`, `update-manager`, or `ubuntu-pro-client`.
- Purge `unattended-upgrades` if a mask is enough.
- Run `gsettings set com.ubuntu.update-notifier auto-launch false` — the key is absent on 24.04.

---

## Revert to stock 24.04 behaviour

```bash
sudo systemctl unmask apt-daily.timer apt-daily-upgrade.timer unattended-upgrades \
                      motd-news.timer motd-news.service \
                      packagekit.service \
                      update-notifier-download.timer update-notifier-motd.timer \
                      update-notifier-download.service update-notifier-motd.service \
                      apt-news.service esm-cache.service \
                      fwupd-refresh.timer fwupd-refresh.service
sudo systemctl enable --now apt-daily.timer apt-daily-upgrade.timer fwupd-refresh.timer

systemctl --user unmask update-notifier-crash.path update-notifier-livepatch.path \
                        update-notifier-release.path \
                        update-notifier-crash.service update-notifier-livepatch.service \
                        update-notifier-release.service

sudo mv /etc/xdg/autostart/update-notifier.desktop.disabled \
        /etc/xdg/autostart/update-notifier.desktop
sudo mv /etc/xdg/autostart/ubuntu-advantage-notification.desktop.disabled \
        /etc/xdg/autostart/ubuntu-advantage-notification.desktop

sudo chmod +x /etc/update-motd.d/50-motd-news \
              /etc/update-motd.d/85-fwupd \
              /etc/update-motd.d/90-updates-available \
              /etc/update-motd.d/91-release-upgrade \
              /etc/update-motd.d/91-contract-ua-esm-status \
              /etc/update-motd.d/92-unattended-upgrades \
              /etc/update-motd.d/95-hwe-eol \
              /etc/update-motd.d/98-reboot-required

printf '%s\n' \
  'APT::Periodic::Update-Package-Lists "1";' \
  'APT::Periodic::Unattended-Upgrade "1";' \
| sudo tee /etc/apt/apt.conf.d/20auto-upgrades

gsettings reset-recursively com.ubuntu.update-notifier
command -v snap >/dev/null && sudo snap refresh --unhold
```

---

## Scope

- Target: Ubuntu 24.04 LTS (Noble), including 24.04.4, systemd.
- Flatpak remotes are not touched.
- 22.04 / 25.10 / 26.04 may rename units. Check `systemctl list-unit-files '*update-notifier*'` first.

MIT. Use at your own risk.
