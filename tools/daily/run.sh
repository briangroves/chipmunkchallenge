#!/bin/zsh
# Runs one pipeline job with the repo's venv, logging to ~/Library/Application Support/ChipmunkBoards/logs.
#   tools/daily/run.sh maker     nonstop: subjects -> pictures -> boards -> judge, pushed to the queue every 2 hours
#   tools/daily/run.sh publish   every 15 min: approved boards -> public feed, decided boards out of the queue
# launchd starts it through `zsh -lic` so ANTHROPIC_API_KEY from ~/.zshrc is set.
set -u
job=${1:?maker or publish}
here=${0:A:h}
repo=${here:h:h}
state="$HOME/Library/Application Support/ChipmunkBoards"
mkdir -p "$state/logs"
log="$state/logs/$job.log"
py="$repo/tools/.venv/bin/python"
cd "$repo"
export TQDM_DISABLE=1 PYTHONUNBUFFERED=1
case $job in
  maker)
    # Keep the Mac from idle-sleeping while it works; run at low CPU priority so the Mac stays usable.
    echo "=== maker start $(date '+%Y-%m-%d %H:%M:%S')" >> "$log"
    exec caffeinate -i nice -n 10 "$py" tools/daily/maker.py >> "$log" 2>&1 ;;
  publish)
    lock="$state/publish.lock"
    mkdir "$lock" 2>/dev/null || { [[ -n $(find "$lock" -maxdepth 0 -mmin +60) ]] && rm -rf "$lock" && mkdir "$lock"; } || exit 0
    trap 'rm -rf "$lock"' EXIT
    "$py" tools/daily/publish.py >> "$log" 2>&1
    # Keep this log short (it's written every 15 minutes).
    tail -n 3000 "$log" > "$log.tmp" && mv "$log.tmp" "$log" ;;
  *) echo "unknown job $job"; exit 2 ;;
esac
