#!/bin/zsh
# Installs (or reinstalls) the board pipeline. Run it from your checkout:  tools/daily/install.sh [branch]
#   - clones the repo into ~/Library/Application Support/ChipmunkBoards/code (the jobs only run that copy, at the
#     branch as pushed to GitHub, default version-2.0; the maker moves to newer pushes by itself)
#   - links the checkout's tools/.venv as the jobs' Python
#   - com.groveseng.chipmunk-boards.maker    always running (restarted if it stops), pushes to the queue every 2 hours
#   - com.groveseng.chipmunk-boards.publish  every 15 minutes
# Remove with: tools/daily/install.sh uninstall
set -e
here=${0:A:h}
checkout=${here:h:h}
agents="$HOME/Library/LaunchAgents"
state="$HOME/Library/Application Support/ChipmunkBoards"
code="$state/code"
mkdir -p "$agents" "$state/logs"
for job in batch maker publish; do
  launchctl bootout "gui/$UID/com.groveseng.chipmunk-boards.$job" 2>/dev/null || true
  rm -f "$agents/com.groveseng.chipmunk-boards.$job.plist"
done
if [[ ${1:-} == uninstall ]]; then echo "removed the board pipeline jobs"; exit 0; fi

branch=${1:-version-2.0}
echo "$branch" > "$state/branch"
[[ -d "$code/.git" ]] || git clone -q "$(git -C "$checkout" remote get-url origin)" "$code"
git -C "$code" fetch -q origin "$branch"
git -C "$code" checkout -q -B "$branch" "origin/$branch"
[[ -x "$checkout/tools/.venv/bin/python" ]] || { echo "no venv at $checkout/tools/.venv"; exit 1; }
ln -sfn "$checkout/tools/.venv" "$state/venv"
echo "code: $(git -C "$code" log --oneline -1)"

for job in maker publish; do
  label="com.groveseng.chipmunk-boards.$job"
  if [[ $job == maker ]]; then
    when='<key>RunAtLoad</key><true/><key>KeepAlive</key><true/><key>ThrottleInterval</key><integer>300</integer>'
    ptype=Standard   # Background would throttle image generation
  else
    when='<key>RunAtLoad</key><true/><key>StartInterval</key><integer>900</integer>'
    ptype=Background
  fi
  # run.sh is read from the pipeline's copy, so it updates with the code.
  cat > "$agents/$label.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>$label</string>
  <key>ProgramArguments</key><array>
    <string>/bin/zsh</string><string>-lic</string><string>"$code/tools/daily/run.sh" $job</string>
  </array>
  $when
  <key>StandardOutPath</key><string>$state/logs/launchd-$job.out</string>
  <key>StandardErrorPath</key><string>$state/logs/launchd-$job.out</string>
  <key>ProcessType</key><string>$ptype</string>
</dict></plist>
PLIST
  launchctl bootstrap "gui/$UID" "$agents/$label.plist"
  echo "installed $label"
done
