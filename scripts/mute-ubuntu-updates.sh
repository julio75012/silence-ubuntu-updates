#!/usr/bin/env bash
# Mute Ubuntu 24.04 automatic update checks and Software Updater popups.
# Safe to re-run. Does not uninstall packages.
set -euo pipefail

need_sudo() {
  if [[ ${EUID} -eq 0 ]]; then
    return 0
  fi
  sudo -v
}

say() { printf '\n==> %s\n' "$*"; }

need_sudo

say "Mask APT timers and unattended-upgrades"
sudo systemctl stop    apt-daily.timer apt-daily-upgrade.timer unattended-upgrades || true
sudo systemctl disable apt-daily.timer apt-daily-upgrade.timer unattended-upgrades || true
sudo systemctl mask    apt-daily.timer apt-daily-upgrade.timer unattended-upgrades

say "Write APT periodic policy (all zeros)"
printf '%s\n' \
  'APT::Periodic::Update-Package-Lists "0";' \
  'APT::Periodic::Download-Upgradeable-Packages "0";' \
  'APT::Periodic::AutocleanInterval "0";' \
  'APT::Periodic::Unattended-Upgrade "0";' \
| sudo tee /etc/apt/apt.conf.d/10periodic /etc/apt/apt.conf.d/20auto-upgrades >/dev/null
apt-config dump APT::Periodic

say "Mask motd-news"
sudo systemctl stop    motd-news.timer motd-news.service 2>/dev/null || true
sudo systemctl disable motd-news.timer motd-news.service 2>/dev/null || true
sudo systemctl mask    motd-news.timer motd-news.service 2>/dev/null || true
if [[ -f /etc/default/motd-news ]]; then
  sudo sed -i 's/^ENABLED=.*/ENABLED=0/' /etc/default/motd-news
fi

say "Disable MOTD update scripts (ignore missing files)"
for f in \
  /etc/update-motd.d/50-motd-news \
  /etc/update-motd.d/88-esm-announce \
  /etc/update-motd.d/90-updates-available \
  /etc/update-motd.d/91-release-upgrade \
  /etc/update-motd.d/91-contract-ua-esm-status \
  /etc/update-motd.d/92-unattended-upgrades \
  /etc/update-motd.d/95-hwe-eol \
  /etc/update-motd.d/98-reboot-required
do
  sudo chmod -x "$f" 2>/dev/null || true
done

sudo mkdir -p /var/lib/update-notifier /var/lib/ubuntu-advantage
sudo touch /var/lib/update-notifier/hide-esm-in-motd \
           /var/lib/ubuntu-advantage/hide-esm-in-motd
sudo rm -f /var/lib/motd-news/new \
           /var/lib/update-notifier/updates-available \
           /var/lib/update-notifier/updates-available-flag

say "Mask PackageKit"
sudo systemctl stop    packagekit.service 2>/dev/null || true
sudo systemctl disable packagekit.service 2>/dev/null || true
sudo systemctl mask    packagekit.service 2>/dev/null || true

say "Mask update-notifier system timers"
sudo systemctl stop    update-notifier-download.timer update-notifier-motd.timer \
                       update-notifier-download.service update-notifier-motd.service 2>/dev/null || true
sudo systemctl disable update-notifier-download.timer update-notifier-motd.timer 2>/dev/null || true
sudo systemctl mask    update-notifier-download.timer update-notifier-motd.timer \
                       update-notifier-download.service update-notifier-motd.service 2>/dev/null || true

say "Mask update-notifier user units"
systemctl --user stop  update-notifier-crash.path update-notifier-livepatch.path \
                       update-notifier-release.path \
                       update-notifier-crash.service update-notifier-livepatch.service \
                       update-notifier-release.service 2>/dev/null || true
systemctl --user mask  update-notifier-crash.path update-notifier-livepatch.path \
                       update-notifier-release.path \
                       update-notifier-crash.service update-notifier-livepatch.service \
                       update-notifier-release.service 2>/dev/null || true

say "Disable autostart and kill running GUI"
if [[ -f /etc/xdg/autostart/update-notifier.desktop ]]; then
  sudo mv /etc/xdg/autostart/update-notifier.desktop \
          /etc/xdg/autostart/update-notifier.desktop.disabled
fi
if [[ -f /etc/xdg/autostart/ubuntu-advantage-notification.desktop ]]; then
  sudo mv /etc/xdg/autostart/ubuntu-advantage-notification.desktop \
          /etc/xdg/autostart/ubuntu-advantage-notification.desktop.disabled
fi
killall update-notifier update-manager 2>/dev/null || true
rm -rf "${HOME}/.cache/update-notifier"

say "GSettings (24.04 keys)"
if command -v gsettings >/dev/null; then
  gsettings set com.ubuntu.update-notifier no-show-notifications true
  gsettings set com.ubuntu.update-notifier hide-reboot-notification true
  gsettings set com.ubuntu.update-notifier notify-ubuntu-advantage-available false
  gsettings set com.ubuntu.update-notifier show-livepatch-status-icon false
  gsettings set com.ubuntu.update-notifier show-apport-crashes false
  gsettings set com.ubuntu.update-notifier regular-auto-launch-interval 36500
  gsettings set org.gnome.software download-updates false 2>/dev/null || true
  gsettings set org.gnome.software allow-updates false 2>/dev/null || true
fi

say "Stock desktop extras: Snap, Ubuntu Pro hooks, fwupd"
if command -v snap >/dev/null 2>&1; then
  sudo snap refresh --hold=forever || true
  snap refresh --time || true
else
  echo "snap not installed, skip"
fi
sudo systemctl stop    apt-news.service esm-cache.service 2>/dev/null || true
sudo systemctl disable apt-news.service esm-cache.service 2>/dev/null || true
sudo systemctl mask    apt-news.service esm-cache.service 2>/dev/null || true
sudo pro config set apt_news=false 2>/dev/null || true
sudo systemctl stop    fwupd-refresh.timer fwupd-refresh.service 2>/dev/null || true
sudo systemctl disable fwupd-refresh.timer 2>/dev/null || true
sudo systemctl mask    fwupd-refresh.timer fwupd-refresh.service 2>/dev/null || true
sudo chmod -x /etc/update-motd.d/85-fwupd 2>/dev/null || true

say "Done. Run scripts/verify-muted.sh after a reboot."
echo "Manual updates: sudo apt update && sudo apt upgrade"
