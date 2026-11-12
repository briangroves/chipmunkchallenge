"""Shared bits for the daily board pipeline: config, the state folder, and the two git checkouts it works in.

The pipeline never touches the working checkout you develop in. It keeps its own clones under STATE:
  queue/  the private queue repo the Board Reviewer app reads and writes
          queue.json        boards waiting for review (the app shows these)
          decisions/<id>.json  approve/deny written by the app, one file per board
          history.jsonl     every board ever decided, with the decision (for judge training later)
          tried.json        every subject name ever generated, so new days pick new subjects
  feed/   a clone of the game repo's gh-pages branch, which serves the public board feed (boards/approved.json)
"""
import json
import os
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
TOOLS = os.path.dirname(HERE)
ROOT = os.path.dirname(TOOLS)
sys.path.insert(0, TOOLS)

# Tests point these at a scratch folder and a config whose repos are local paths.
STATE = os.environ.get("CHIPMUNK_BOARDS_STATE") or os.path.expanduser("~/Library/Application Support/ChipmunkBoards")
QUEUE = os.path.join(STATE, "queue")
FEED = os.path.join(STATE, "feed")
RUNS = os.path.join(STATE, "runs")
CFG = json.load(open(os.environ.get("CHIPMUNK_BOARDS_CONFIG") or os.path.join(HERE, "config.json")))


def log(*a):
    print(time.strftime("%Y-%m-%d %H:%M:%S"), *a, flush=True)


def git(repo, *args, check=True):
    r = subprocess.run(["git", "-C", repo, *args], capture_output=True, text=True)
    if check and r.returncode:
        raise RuntimeError(f"git {' '.join(args)} failed in {repo}:\n{r.stdout}{r.stderr}")
    return r.stdout.strip()


def ensure_clone(path, repo, branch=None):
    """Clone the repo once; afterwards hard-reset to the remote branch (these clones hold no local work)."""
    if not os.path.isdir(os.path.join(path, ".git")):
        os.makedirs(os.path.dirname(path), exist_ok=True)
        url = repo if repo.startswith("/") else f"https://github.com/{repo}.git"
        subprocess.run(["git", "clone", "-q", url, path], check=True)
    git(path, "rebase", "--abort", check=False)  # a push race that died mid-rebase last time
    git(path, "fetch", "-q", "origin")
    branch = branch or git(path, "rev-parse", "--abbrev-ref", "origin/HEAD").split("/", 1)[1]
    git(path, "checkout", "-q", "-B", branch, f"origin/{branch}")
    git(path, "reset", "-q", "--hard", f"origin/{branch}")
    git(path, "clean", "-qfd")
    return branch


def push(path, branch, message, files):
    """Commit the files and push; on a race with another push, rebase and retry."""
    git(path, "add", "-A", "--", *files)
    if not git(path, "status", "--porcelain", "--", *files):
        return False
    git(path, "commit", "-q", "-m", message)
    for attempt in range(4):
        r = subprocess.run(["git", "-C", path, "push", "-q", "origin", f"HEAD:{branch}"], capture_output=True, text=True)
        if r.returncode == 0:
            return True
        log("push rejected, rebasing:", r.stderr.strip())
        git(path, "pull", "-q", "--rebase", "origin", branch)
        time.sleep(2 * (attempt + 1))
    raise RuntimeError(f"could not push {path}")


def load(path, default):
    return json.load(open(path)) if os.path.exists(path) else default


def save(path, data, indent=None):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path + ".tmp", "w") as f:
        json.dump(data, f, indent=indent)
        f.write("\n")
    os.replace(path + ".tmp", path)
