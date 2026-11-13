#!/bin/zsh
# Runs one pipeline job from the pipeline's own copy of the repo (STATE/code, version-2.0 as pushed), so work in
# progress in the checkout you develop in can't break it. Logs go to STATE/logs.
#   run.sh maker     nonstop: subjects -> pictures -> boards -> judge, pushed to the queue every 2 hours
#   run.sh publish   every 15 min: approved boards -> public feed, decided boards out of the queue
# launchd starts it through `zsh -lic` so ANTHROPIC_API_KEY from ~/.zshrc is set. install.sh sets it all up.
set -u
job=${1:?maker or publish}
state="$HOME/Library/Application Support/ChipmunkBoards"
code="$state/code"
branch=$(cat "$state/branch" 2>/dev/null || echo version-2.0)
mkdir -p "$state/logs"
log="$state/logs/$job.log"
py="$state/venv/bin/python"
export TQDM_DISABLE=1 PYTHONUNBUFFERED=1
case $job in
  maker)
    # Start from the latest pushed code (the maker restarts itself when the branch moves on).
    {
      echo "=== maker start $(date '+%Y-%m-%d %H:%M:%S')"
      git -C "$code" fetch -q origin "$branch" && git -C "$code" reset -q --hard "origin/$branch" && git -C "$code" clean -qfd
      echo "code: $(git -C "$code" log --oneline -1)"
    } >> "$log" 2>&1
    cd "$code"
    # Keep the Mac from idle-sleeping while it works; run at low CPU priority so the Mac stays usable.
    exec caffeinate -i nice -n 10 "$py" tools/daily/maker.py >> "$log" 2>&1 ;;
  publish)
    lock="$state/publish.lock"
    mkdir "$lock" 2>/dev/null || { [[ -n $(find "$lock" -maxdepth 0 -mmin +60) ]] && rm -rf "$lock" && mkdir "$lock"; } || exit 0
    trap 'rm -rf "$lock"' EXIT
    cd "$code"
    "$py" tools/daily/publish.py >> "$log" 2>&1
    # Keep this log short (it's written every 15 minutes).
    tail -n 3000 "$log" > "$log.tmp" && mv "$log.tmp" "$log" ;;
  *) echo "unknown job $job"; exit 2 ;;
esac
