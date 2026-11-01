#!/bin/sh
set -eu
resources=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
app=${resources%/Contents/Resources}
uid=$(/usr/bin/stat -f %u "$app")
home=$(/usr/bin/dscl . -read "/Users/$(/usr/bin/id -nu "$uid")" NFSHomeDirectory | /usr/bin/cut -d ' ' -f 2-)
if [ "$uid" = 0 ] || [ -z "$home" ]; then exit 1; fi
target=/Library/PrivilegedHelperTools/com.user.awake-lock-helper
plist=/Library/LaunchDaemons/com.user.awake-lock-helper.plist
/bin/mkdir -p /Library/PrivilegedHelperTools
/bin/launchctl bootout system/com.user.awake-lock-helper 2>/dev/null || true
/usr/bin/install -o root -g wheel -m 755 "$resources/awake-lock-helper" "$target"
/bin/rm -f "$plist"
/usr/bin/plutil -create xml "$plist"
/usr/bin/plutil -insert Label -string com.user.awake-lock-helper "$plist"
/usr/bin/plutil -insert ProgramArguments -array "$plist"
/usr/bin/plutil -insert ProgramArguments.0 -string "$target" "$plist"
/usr/bin/plutil -insert ProgramArguments.1 -string "$uid" "$plist"
/usr/bin/plutil -insert ProgramArguments.2 -string "$home/Library/Application Support/Awake Lock/request.plist" "$plist"
/usr/bin/plutil -insert ProgramArguments.3 -string "$app/Contents/MacOS/AwakeLock" "$plist"
/usr/bin/plutil -insert RunAtLoad -bool true "$plist"
/usr/bin/plutil -insert KeepAlive -bool true "$plist"
/usr/bin/plutil -insert ThrottleInterval -integer 2 "$plist"
/usr/bin/plutil -insert ProcessType -string Background "$plist"
/usr/sbin/chown root:wheel "$plist"
/bin/chmod 644 "$plist"
/bin/launchctl bootstrap system "$plist"
