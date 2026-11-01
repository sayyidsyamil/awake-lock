#!/bin/sh
set -eu
if [ "$(id -u)" != 0 ]; then
  printf 'Run this helper-removal script with sudo.\n' >&2
  exit 1
fi
/bin/launchctl bootout system/com.user.awake-lock-helper 2>/dev/null || true
marker=/var/db/com.user.awake-lock-previous-sleep.plist
if [ -f "$marker" ]; then
  previous=$(/usr/bin/plutil -extract previous raw "$marker")
  if [ "$previous" = true ]; then /usr/bin/pmset -a disablesleep 1
  else /usr/bin/pmset -a disablesleep 0; fi
  /bin/rm -f "$marker"
fi
/bin/rm -f /Library/LaunchDaemons/com.user.awake-lock-helper.plist \
  /Library/PrivilegedHelperTools/com.user.awake-lock-helper \
  /var/run/com.user.awake-lock-helper.plist
printf 'Closed-lid helper removed; previous sleep setting restored.\n'
