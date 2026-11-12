#!/bin/zsh
# Installs (or reinstalls) the board pipeline's launchd jobs for this user:
#   com.groveseng.chipmunk-boards.maker    always running (restarted if it stops), pushes to the queue every 2 hours
#   com.groveseng.chipmunk-boards.publish  every 15 minutes
# Remove with: tools/daily/install.sh uninstall
set -e
here=${0:A:h}
agents="$HOME/Library/LaunchAgents"
state="$HOME/Library/Application Support/ChipmunkBoards"
mkdir -p "$agents" "$state/logs"
for job in batch maker publish; do
  label="com.groveseng.chipmunk-boards.$job"
  plist="$agents/$label.plist"
  launchctl bootout "gui/$UID/$label" 2>/dev/null || true
  rm -f "$plist"
  [[ $job == batch || ${1:-} == uninstall ]] && continue   # batch: the old nightly job, replaced by maker
  if [[ $job == maker ]]; then
    when='<key>RunAtLoad</key><true/><key>KeepAlive</key><true/><key>ThrottleInterval</key><integer>300</integer>'
    ptype=Standard   # Background would throttle image generation
  else
    when='<key>RunAtLoad</key><true/><key>StartInterval</key><integer>900</integer>'
    ptype=Background
  fi
  cat > "$plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>$label</string>
  <key>ProgramArguments</key><array>
    <string>/bin/zsh</string><string>-lic</string><string>"$here/run.sh" $job</string>
  </array>
  $when
  <key>StandardOutPath</key><string>$state/logs/launchd-$job.out</string>
  <key>StandardErrorPath</key><string>$state/logs/launchd-$job.out</string>
  <key>ProcessType</key><string>$ptype</string>
</dict></plist>
PLIST
  launchctl bootstrap "gui/$UID" "$plist"
  echo "installed $label"
done
[[ ${1:-} == uninstall ]] && echo "removed the board pipeline jobs"
exit 0
