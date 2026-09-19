#!/usr/bin/env bash
# Print a mute/fail report for Ubuntu update automation.
set -u

fail=0

section() { printf '\n==> %s\n' "$*"; }

section "Scheduled timers (must be empty)"
if systemctl list-timers --all --no-pager | grep -Ei 'apt|update|unattended|motd|packagekit'; then
  echo "FAIL: an update-related timer is still scheduled"
  fail=1
else
  echo "OK: no APT/update timers scheduled"
fi

section "Unit files"
systemctl list-unit-files '*apt-daily*' '*unattended*' '*motd-news*' '*packagekit*' '*update-notifier*' --no-pager || true
systemctl --user list-unit-files '*update-notifier*' --no-pager 2>/dev/null || true

section "Processes"
if ps -eo pid,cmd | grep -Ei 'update-notifier|update-manager|unattended-upgrades|packagekit' | grep -v grep; then
  echo "FAIL: an update process is running"
  fail=1
else
  echo "OK: no update processes"
fi

section "APT periodic policy"
apt-config dump APT::Periodic || true
if apt-config dump APT::Periodic 2>/dev/null | grep -E '"(1|[2-9][0-9]*)"'; then
  echo "FAIL: a periodic value is not 0"
  fail=1
else
  echo "OK: periodic values look disabled"
fi

section "Autostart"
if [[ -f /etc/xdg/autostart/update-notifier.desktop ]]; then
  echo "FAIL: /etc/xdg/autostart/update-notifier.desktop still present"
  fail=1
else
  echo "OK: update-notifier autostart disabled"
fi

section "GSettings"
if command -v gsettings >/dev/null; then
  gsettings get com.ubuntu.update-notifier no-show-notifications || true
  gsettings get com.ubuntu.update-notifier regular-auto-launch-interval || true
else
  echo "gsettings not available (headless?)"
fi

if [[ ${fail} -eq 0 ]]; then
  printf '\nRESULT: MUTE\n'
else
  printf '\nRESULT: NOT FULLY MUTE\n'
  exit 1
fi
