#!/usr/bin/env python3
"""Publish new board packs for the app to download (no app update needed).

    python3 tools/publish_pack.py make --name "Ocean Pals" --source new-boards.json --ids-file approved.txt \\
                                       --ratings board-ratings.csv
    python3 tools/publish_pack.py status
    python3 tools/publish_pack.py promote pack-001         # players get pack-001 (and any beta packs before it)
    python3 tools/publish_pack.py pull pack-002            # drop a beta pack that isn't live yet
    python3 tools/publish_pack.py ... --push               # also push the site (otherwise it's committed locally)

The site is the repo's gh-pages branch (https://briangroves.github.io/chipmunkchallenge/), checked out at .pages/
(made with `git worktree add` on first use). Under packs/ it holds:
    files/<pack id>-<sha8>.json   one pack each, in the shape of boards.json; never changed once published
    beta/manifest.json            TestFlight and development builds read this: every live pack, then the ones on trial
    live/manifest.json            App Store builds read this

`make` puts a new pack on the end of the beta manifest. Check it on the phone (TestFlight build, Home shows
"New pack!"), then `promote` it. The live manifest is always the start of the beta one.

Level Play starts with the boards in Engine/Sources/ChipmunkEngine/Resources/levelplay.json (they ship in the app);
every later board comes from here. Old boards that aren't in levelplay.json (the clipart boards in boards.json, the
web game's originals) can be published in a pack like any new board.

APPEND ONLY: a board's number is the player's place in Level Play, and its challenge and seed come from that number.
So a live pack is never removed, reordered or edited. To swap a live board's picture, put the new picture in a later
pack with --replace OLD_ID=NEW_ID (it keeps its number). Board ids must be new: not in the app or any published pack.

Boards come from --source files: boards.json-shaped ({"packs": [{"levels": [...]}]}), a list of boards, or
{"levels": [...]}, each board {"id", "name", "rows": 40 strings of 40 palette letters}. --ratings takes the CSV the
app's Settings -> Review boards shares; only boards rated --min stars (default 4) or more can go in a pack.
"""
import argparse
import csv
import hashlib
import json
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RES = os.path.join(ROOT, "Engine/Sources/ChipmunkEngine/Resources")
PALETTE = set("ROYGBVPNWKTALDMCUIQJHESZX")
FORMAT = 1


def die(msg):
    sys.exit("publish_pack: " + msg)


def run(*args, cwd=None):
    return subprocess.run(args, cwd=cwd, check=True, capture_output=True, text=True).stdout


# MARK: - The site

def site_dir(path):
    if path:
        return os.path.abspath(path)
    site = os.path.join(ROOT, ".pages")
    if not os.path.exists(site):
        run("git", "fetch", "origin", "gh-pages", cwd=ROOT)
        run("git", "worktree", "add", site, "gh-pages", cwd=ROOT)
        print(f"Checked out gh-pages at {site}")
    return site


def manifest_path(site, channel):
    return os.path.join(site, "packs", channel, "manifest.json")


def read_manifest(site, channel):
    p = manifest_path(site, channel)
    if not os.path.exists(p):
        return {"format": FORMAT, "packs": []}
    return json.load(open(p))


def write_manifest(site, channel, m):
    p = manifest_path(site, channel)
    os.makedirs(os.path.dirname(p), exist_ok=True)
    with open(p, "w") as f:
        json.dump(m, f, indent=1)
        f.write("\n")


def check_order(beta, live):
    b, l = [e["id"] for e in beta["packs"]], [e["id"] for e in live["packs"]]
    if b[:len(l)] != l:
        die(f"the live manifest {l} isn't the start of the beta one {b}; fix by hand before publishing more")


def commit(site, message, push, git="yes"):
    if git == "no":
        return
    if not run("git", "status", "--porcelain", "--", "packs", cwd=site).strip():
        return
    run("git", "add", "packs", cwd=site)
    run("git", "commit", "-q", "-m", message, cwd=site)
    if push:
        run("git", "push", "-q", "origin", "HEAD:gh-pages", cwd=site)
        print("Pushed to gh-pages; GitHub Pages serves it within a few minutes.")
    else:
        print(f"Committed in {site}. Publish with:  git -C {site} push origin HEAD:gh-pages")


# MARK: - Boards

def app_version():
    m = re.search(r'MARKETING_VERSION:\s*"([^"]+)"', open(os.path.join(ROOT, "ios/project.yml")).read())
    return m.group(1) if m else "1.0"


def boards_in(data):
    """Every board in a source file, whatever its shape."""
    if isinstance(data, list):
        return [b for x in data for b in (boards_in(x) if "rows" not in x else [x])]
    if "rows" in data:
        return [data]
    out = []
    for p in data.get("packs", []):
        out += p.get("levels", [])
    out += data.get("levels", [])
    out += list(data.get("replace", {}).values())
    return out


def starter():
    """The boards Level Play starts with (they ship in the app)."""
    return boards_in(json.load(open(os.path.join(RES, "levelplay.json"))))


def bundled_ids():
    return {b["id"] for b in starter()}


def published_ids(site, beta):
    ids = set()
    for e in beta["packs"]:
        ids |= {b["id"] for b in boards_in(json.load(open(file_path(site, e))))}
    return ids


def file_path(site, entry):
    return os.path.normpath(os.path.join(site, "packs", "beta", entry["file"]))


def well_formed(b):
    rows = b.get("rows")
    return (bool(b.get("id")) and bool(b.get("name")) and isinstance(rows, list) and len(rows) == 40
            and all(isinstance(r, str) and len(r) == 40 and set(r) <= PALETTE for r in rows))


def slim(b):
    out = {"id": b["id"], "name": b["name"], "rows": b["rows"]}
    if b.get("source"):
        out["source"] = b["source"]
    return out


def read_ids(args):
    ids = [i.strip() for i in (args.ids or "").split(",") if i.strip()]
    if args.ids_file:
        ids += [ln.split(",")[0].strip() for ln in open(args.ids_file) if ln.strip() and not ln.startswith("#")]
    return ids


def ratings(path):
    out = {}
    with open(path) as f:
        for row in csv.DictReader(f):
            try:
                out[row["id"]] = int(row["stars"])
            except (KeyError, ValueError):
                pass
    return out


# MARK: - Commands

def cmd_make(args):
    site = site_dir(args.site)
    beta, live = read_manifest(site, "beta"), read_manifest(site, "live")
    check_order(beta, live)
    pool = {}
    for src in args.source:
        for b in boards_in(json.load(open(src))):
            pool[b["id"]] = b
    ids = read_ids(args)
    swaps = dict(r.split("=", 1) for r in args.replace)
    if not ids:
        die("no board ids (--ids or --ids-file)")
    if len(set(ids)) != len(ids):
        die("a board id is listed twice")
    missing = [i for i in ids + list(swaps.values()) if i not in pool]
    if missing:
        die(f"not in the --source files: {missing}")
    bad = [i for i in ids + list(swaps.values()) if not well_formed(pool[i])]
    if bad:
        die(f"not 40 rows of 40 palette letters: {bad}")
    taken = bundled_ids() | published_ids(site, beta)
    clash = [i for i in ids + list(swaps.values()) if i in taken]
    if clash:
        die(f"these ids are already in Level Play or a published pack (board ids must be new): {clash}")
    unknown = [old for old in swaps if old not in taken]
    if unknown:
        die(f"--replace names boards that aren't in Level Play or a published pack: {unknown}")
    if args.ratings:
        stars = ratings(args.ratings)
        low = [i for i in ids + list(swaps.values()) if stars.get(i, 0) < args.min]
        if low:
            die(f"rated below {args.min} stars or not rated: {low}")
    elif not args.unrated:
        die("pass --ratings CSV (only boards rated 4-5 stars ship), or --unrated to skip the check")
    if len(ids) != 20 and not args.any_size:
        die(f"{len(ids)} boards; packs have 20 (pass --any-size to allow it)")

    n = len(beta["packs"]) + 1
    pid = args.id or f"pack-{n:03d}"
    if any(e["id"] == pid for e in beta["packs"]):
        die(f"pack id {pid} is already published")
    name = args.name or f"New Pack {n}"
    data = {"format": FORMAT, "packs": [{"id": pid, "name": name, "levels": [slim(pool[i]) for i in ids]}]}
    if swaps:
        data["replace"] = {old: slim(pool[new]) for old, new in swaps.items()}
    blob = json.dumps(data, separators=(",", ":"), ensure_ascii=False).encode()
    sha = hashlib.sha256(blob).hexdigest()
    rel = f"../files/{pid}-{sha[:8]}.json"
    entry = {"id": pid, "name": name, "file": rel, "sha256": sha, "size": len(blob), "boards": len(ids),
             "format": FORMAT, "minAppVersion": args.min_app or app_version()}
    path = file_path(site, entry)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as f:
        f.write(blob)
    beta["packs"].append(entry)
    write_manifest(site, "beta", beta)
    if not os.path.exists(manifest_path(site, "live")):
        write_manifest(site, "live", live)
    print(f"{pid} \"{name}\": {len(ids)} boards{f', {len(swaps)} redrawn' if swaps else ''}, {len(blob):,} bytes, "
          f"on the beta manifest (beta position {n}).")
    commit(site, f"Board pack {pid} ({name}) on beta", args.push, args.git)


def cmd_promote(args):
    site = site_dir(args.site)
    beta, live = read_manifest(site, "beta"), read_manifest(site, "live")
    check_order(beta, live)
    ids = [e["id"] for e in beta["packs"]]
    if args.pack not in ids:
        die(f"{args.pack} isn't on the beta manifest: {ids}")
    upto = ids.index(args.pack) + 1
    if upto <= len(live["packs"]):
        die(f"{args.pack} is already live")
    added = beta["packs"][len(live["packs"]):upto]
    live["packs"] = beta["packs"][:upto]
    write_manifest(site, "live", live)
    print("Live now:", ", ".join(e["id"] for e in live["packs"]), f"(added {', '.join(e['id'] for e in added)})")
    commit(site, f"Board packs live through {args.pack}", args.push, args.git)


def cmd_pull(args):
    site = site_dir(args.site)
    beta, live = read_manifest(site, "beta"), read_manifest(site, "live")
    check_order(beta, live)
    ids = [e["id"] for e in beta["packs"]]
    if args.pack not in ids:
        die(f"{args.pack} isn't on the beta manifest")
    k = ids.index(args.pack)
    if k < len(live["packs"]):
        die(f"{args.pack} is live; live packs are never removed (swap pictures with make --replace instead)")
    e = beta["packs"].pop(k)
    if os.path.exists(file_path(site, e)):
        os.remove(file_path(site, e))
    write_manifest(site, "beta", beta)
    print(f"Pulled {args.pack} from beta. Test phones drop it (and any beta packs after it, which download again).")
    commit(site, f"Pull beta board pack {args.pack}", args.push, args.git)


def cmd_status(args):
    site = site_dir(args.site)
    beta, live = read_manifest(site, "beta"), read_manifest(site, "live")
    check_order(beta, live)
    total = len(starter())
    print(f"{total} boards in the app; downloaded packs start at level {total + 1}.")
    level = total + 1
    for k, e in enumerate(beta["packs"]):
        where = "live" if k < len(live["packs"]) else "beta"
        print(f"  {e['id']:10} {where:4}  levels {level}-{level + e['boards'] - 1}  {e['name']}  "
              f"(app {e['minAppVersion']}+)")
        level += e["boards"]
    if not beta["packs"]:
        print("  no packs published yet")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--site", help="gh-pages checkout to publish into (default .pages/, made on first use)")
    ap.add_argument("--push", action="store_true", help="push the site after committing")
    ap.add_argument("--git", choices=["yes", "no"], default="yes", help="'no': write files only, no commit")
    sub = ap.add_subparsers(dest="cmd", required=True)
    m = sub.add_parser("make", help="build a pack from approved boards and put it on beta")
    m.add_argument("--source", action="append", required=True, help="file with the boards (repeatable)")
    m.add_argument("--ids", help="comma-separated board ids, in play order")
    m.add_argument("--ids-file", help="file with one board id per line (first CSV column), in play order")
    m.add_argument("--name", help="pack name shown in the game")
    m.add_argument("--id", help="pack id (default pack-NNN)")
    m.add_argument("--ratings", help="ratings CSV from Settings -> Review boards")
    m.add_argument("--min", type=int, default=4, help="lowest star rating that ships (default 4)")
    m.add_argument("--unrated", action="store_true", help="skip the ratings check")
    m.add_argument("--any-size", action="store_true", help="allow a pack of other than 20 boards")
    m.add_argument("--replace", action="append", default=[], metavar="OLD=NEW",
                   help="redraw published board OLD with board NEW from the sources (keeps its number)")
    m.add_argument("--min-app", help="oldest app version that may play it (default: ios/project.yml's)")
    for name in ("promote", "pull"):
        p = sub.add_parser(name)
        p.add_argument("pack")
    sub.add_parser("status")
    args = ap.parse_args()
    {"make": cmd_make, "promote": cmd_promote, "pull": cmd_pull, "status": cmd_status}[args.cmd](args)


if __name__ == "__main__":
    main()
