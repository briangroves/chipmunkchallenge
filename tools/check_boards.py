#!/usr/bin/env python3
"""Blind check of board pictures: can someone tell what each board is, just from looking at it?

    python3 tools/check_boards.py                    # every new board in Resources/boards.json
    python3 tools/check_boards.py --pack farm        # one pack
    python3 tools/check_boards.py --dry-run          # render the images and the review sheet, no API calls

Each board is rendered as the player sees it and shown to Claude with no hint of the answer. Claude says what the
picture shows (a best guess and two alternatives), how readable it is (1-5), and which features it can make out (a
face, eyes, legs...). The guess is then compared with the board's real subject:

    pass  - the best guess names the subject and readability is 3 or more
    weak  - only an alternative names it, or readability is under 3
    fail  - none of the guesses name it

and scored out of 100: 50 if the best guess names the subject (20 if only an alternative does), up to 30 for
readability, up to 20 for the features Claude could make out. Each board is also measured from its own blocks
(colors used, how much is black, the biggest flat patch, how much of the board the subject covers, its theme), and
the report shows which of these go with high and low scores, so we learn what makes a good board good.

After a run: tools/packs/checks/ranking.md lists every board best to worst, with worst.png and best.png sheets.
`--verify-top N` asks again about the N best boards, blind, with more careful reasoning, and flags any where the
second answer doesn't agree.

Results go to tools/packs/checks/<pack>.json (one entry per board, kept between runs so a rerun only checks boards
whose picture changed) and a review sheet with each board's grade, tools/packs/checks/<pack>-graded.png. Boards that
don't pass need a touch-up (tools/packs/touchups/) or a different source picture.

Needs the Anthropic Python SDK (`pip install anthropic`) and credentials (ANTHROPIC_API_KEY, or `ant auth login`).
Each board is one small request with one image (about $0.004 a board on Claude Opus 5.5).
"""
import argparse
import base64
import hashlib
import json
import os
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from image_to_board import RGB  # noqa: E402

ROOT = os.path.dirname(HERE)
BOARDS = os.path.join(ROOT, "Engine/Sources/ChipmunkEngine/Resources/boards.json")
ORIGINALS = os.path.join(ROOT, "Engine/Sources/ChipmunkEngine/Resources/levels.json")
SUFFIX = ""   # "-originals" when checking the original 170 boards (separate report and sheets)
CHECKS = os.path.join(HERE, "packs", "checks")
MODEL = "claude-opus-5-5"

PROMPT = """This is a 40x40 pixel-art picture from a puzzle game for kids. Each square is one block.
Look at it as a player would and say what the main picture shows.

Reply with:
- guess: your best guess for the main subject, in a few words (e.g. "cow", "red tractor")
- alternatives: two other things it could be
- readability: 1-5, how easily a child would recognise the subject (1 = can't tell, 3 = recognisable with effort,
  5 = obvious at a glance)
- features: the parts of the subject you can actually make out (for an animal: face, eyes, nose or beak, ears, legs,
  tail...; for an object: its main parts)
- problems: anything that makes it hard to read (blobby shape, no face, colors blending into the background...)
Judge only what is in the picture."""

SCHEMA = {
    "type": "object",
    "properties": {
        "guess": {"type": "string"},
        "alternatives": {"type": "array", "items": {"type": "string"}},
        "readability": {"type": "integer"},
        "features": {"type": "array", "items": {"type": "string"}},
        "problems": {"type": "array", "items": {"type": "string"}},
    },
    "required": ["guess", "alternatives", "readability", "features", "problems"],
    "additionalProperties": False,
}

# Words that count as the same subject (the guess may be more or less specific than the board's name).
SYNONYMS = {
    "bunny": {"rabbit", "hare"}, "rabbit": {"bunny", "hare"}, "chick": {"chicken", "baby chicken", "bird"},
    "pony": {"horse"}, "lamb": {"sheep"}, "bull": {"cow", "ox", "bison", "buffalo"}, "goose": {"duck", "swan"},
    "barn cat": {"cat", "kitten"}, "farm dog": {"dog", "puppy"}, "field mouse": {"mouse", "rat"},
    "rooster": {"chicken", "cockerel", "hen"}, "puppy": {"dog"}, "kitten": {"cat"},
    "hare": {"rabbit", "bunny"}, "seal pup": {"seal"}, "musk ox": {"ox", "bison", "yak", "buffalo"},
    "toad": {"frog"}, "orca": {"killer whale", "whale"}, "beluga": {"whale"}, "husky": {"dog", "wolf"},
    "reindeer": {"deer", "caribou", "moose", "elk"}, "caribou": {"reindeer", "deer"}, "elk": {"deer", "moose"},
    "moose": {"elk"}, "yeti": {"bigfoot", "abominable snowman", "sasquatch"}, "mittens": {"mitten", "glove"},
    "ice skates": {"skate"}, "snow globe": {"globe"}, "lemming": {"hamster", "mouse", "vole"},
    "groundhog": {"marmot", "woodchuck", "beaver", "gopher"}, "bobcat": {"lynx", "wildcat"},
    "lynx": {"bobcat", "wildcat"}, "sea turtle": {"turtle", "tortoise"}, "jaguar": {"leopard", "panther"},
    "panther": {"jaguar", "black cat", "leopard"}, "ape": {"gorilla", "monkey"}, "gorilla": {"ape"},
    "orangutan": {"ape", "monkey"}, "baboon": {"monkey"}, "lemur": {"monkey"}, "gazelle": {"antelope", "deer"},
    "warthog": {"boar", "pig"}, "crocodile": {"alligator"}, "earmuffs": {"ear muffs", "headphones"},
    "snowboard": {"snowboarder"}, "angelfish": {"angel fish", "fish"}, "lionfish": {"lion fish"},
    "sunfish": {"sun fish", "mola"}, "leaning tower of pisa": {"leaning tower", "tower of pisa"},
    "big ben": {"clock tower", "elizabeth tower"}, "kremlin": {"basil", "onion dome", "cathedral", "kremlin"},
    "space needle": {"needle", "observation tower"}, "taj mahal": {"taj"}, "mosque": {"minaret"},
    "seashell": {"shell", "conch", "scallop"}, "succulent": {"cactus", "aloe", "plant"},
    "comet": {"shooting star", "meteor"}, "dalmatian": {"dog", "puppy"}, "gecko": {"lizard"},
    "doe": {"deer", "fawn"}, "gondola": {"boat", "canoe"}, "fawn": {"deer", "bambi"}, "cub": {"bear", "lion", "fox", "tiger"},
    "explorer": {"hiker", "adventurer", "eskimo", "inuit", "person", "boy", "girl", "kid", "child"},
    "diver": {"scuba", "swimmer", "snorkel"}, "boar": {"pig", "hog", "warthog"}, "family": {"bear", "bears"},
    "tropical fish": {"fish"}, "stump": {"log", "tree"}, "honey pot": {"honey", "jar"},
    "birdhouse": {"bird house", "birdhouse", "nest box"}, "mushroom house": {"mushroom"},
    "snowmobile": {"snow mobile", "sled"}, "sleigh": {"sled", "sleigh"}, "bunny": {"rabbit", "hare"}, "parrotfish": {"parrot fish"}, "chipmunk": {"squirrel"},
}


def render_png(rows, path, z=12):
    """The board as a picture: one z-by-z square per block, with a thin darker line between blocks like the game's
    tiles, so the model sees blocks rather than a smooth image."""
    n = len(rows)
    size = n * z
    img = bytearray(size * size * 3)
    for r, row in enumerate(rows):
        for c, ch in enumerate(row):
            red, grn, blu = RGB[ch]
            edge = (max(0, red - 28), max(0, grn - 28), max(0, blu - 28))
            for y in range(z):
                base = ((r * z + y) * size + c * z) * 3
                for x in range(z):
                    p = edge if x == z - 1 or y == z - 1 else (red, grn, blu)
                    img[base + x * 3: base + x * 3 + 3] = bytes(p)
    with tempfile.TemporaryDirectory() as d:
        ppm = os.path.join(d, "b.ppm")
        with open(ppm, "wb") as f:
            f.write(f"P6 {size} {size} 255\n".encode())
            f.write(img)
        subprocess.run(["sips", "-s", "format", "png", ppm, "--out", path], capture_output=True, check=True)


def names_match(subject, text):
    """Does a guess name the board's subject? The subject's main word (the last one: "snow leopard" needs "leopard",
    not just "snow"), the whole name, or a known synonym, in the guess."""
    s, t = subject.lower(), text.lower()
    head = s.replace("-", " ").split()[-1]
    words = {s, head, head.rstrip("s")} | SYNONYMS.get(s, set()) | SYNONYMS.get(head, set())
    return any(w in t for w in words if len(w) > 2 or w == s)


def grade(subject, answer):
    best = names_match(subject, answer["guess"])
    alt = any(names_match(subject, a) for a in answer["alternatives"])
    if best and answer["readability"] >= 3:
        return "pass"
    if best or alt:
        return "weak"
    return "fail"


KEY_FEATURES = ("face", "eye", "nose", "beak", "snout", "muzzle", "ear", "leg", "feet", "paw", "hoof", "tail",
                "wing", "horn", "mouth", "wheel")


def score(subject, answer):
    """0-100: recognised (50, or 20 via an alternative), readability (up to 30), features seen (up to 20)."""
    s = 50 if names_match(subject, answer["guess"]) else \
        (20 if any(names_match(subject, a) for a in answer["alternatives"]) else 0)
    s += 6 * max(0, min(5, answer["readability"]))
    seen = {k for k in KEY_FEATURES for f in answer["features"] if k in f.lower()}
    s += min(20, 4 * len(seen))
    return s


def measure(rows):
    """What a board is made of, from its blocks alone (to compare against scores)."""
    from collections import Counter
    cells = "".join(rows)
    count = Counter(cells)
    # Biggest single-color patch, as a share of the board.
    seen, biggest = set(), 0
    for start in range(len(cells)):
        if start in seen:
            continue
        k, stack, n = cells[start], [start], 0
        seen.add(start)
        while stack:
            i = stack.pop()
            n += 1
            r, c = divmod(i, 40)
            for j in ((i - 40) if r else -1, (i + 40) if r < 39 else -1, (i - 1) if c else -1, (i + 1) if c < 39 else -1):
                if j >= 0 and j not in seen and cells[j] == k:
                    seen.add(j)
                    stack.append(j)
        biggest = max(biggest, n)
    return {"colors": len(count), "black": round(count["K"] / len(cells), 3), "biggest_patch": round(biggest / len(cells), 3)}


def ask(client, png_path, effort="low"):
    import anthropic
    data = base64.standard_b64encode(open(png_path, "rb").read()).decode()
    response = client.beta.messages.create(
        model=MODEL,
        max_tokens=2000,
        output_config={"effort": effort, "format": {"type": "json_schema", "schema": SCHEMA}},
        # If a safety classifier declines, the API retries on its recommended fallback model in the same call.
        betas=["server-side-fallback-2026-07-01"],
        fallbacks="default",
        messages=[{"role": "user", "content": [
            {"type": "image", "source": {"type": "base64", "media_type": "image/png", "data": data}},
            {"type": "text", "text": PROMPT},
        ]}],
    )
    if response.stop_reason == "refusal":
        raise RuntimeError("declined")
    text = next(b.text for b in response.content if b.type == "text")
    return json.loads(text)


def sheet(entries, out, z=6):
    """All checked boards with a colored bar under each: green pass, amber weak, red fail."""
    colors = {"pass": (46, 160, 67), "weak": (230, 160, 30), "fail": (210, 50, 50), None: (90, 90, 90)}
    cols, n, bar = 5, 40, 10
    tile = n * z
    rows_n = (len(entries) + cols - 1) // cols
    W, H = cols * (tile + 6), rows_n * (tile + bar + 8)
    img = bytearray(bytes((30, 30, 30)) * (W * H))
    for i, (rows, g) in enumerate(entries):
        oy, ox = (i // cols) * (tile + bar + 8), (i % cols) * (tile + 6)
        for r, row in enumerate(rows):
            for c, ch in enumerate(row):
                p = bytes(RGB[ch]) * z
                for y in range(z):
                    base = ((oy + r * z + y) * W + ox + c * z) * 3
                    img[base:base + 3 * z] = p
        for y in range(tile + 2, tile + 2 + bar):
            base = ((oy + y) * W + ox) * 3
            img[base:base + 3 * tile] = bytes(colors[g]) * tile
    with tempfile.TemporaryDirectory() as d:
        ppm = os.path.join(d, "s.ppm")
        with open(ppm, "wb") as f:
            f.write(f"P6 {W} {H} 255\n".encode())
            f.write(img)
        subprocess.run(["sips", "-s", "format", "png", ppm, "--out", out], capture_output=True, check=True)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--pack", help="check only this pack")
    ap.add_argument("--dry-run", action="store_true", help="render images and sheets, but don't call the API")
    ap.add_argument("--all", action="store_true", help="re-check boards even if their picture hasn't changed")
    ap.add_argument("--verify-top", type=int, default=10, help="ask again about the N best boards (0 to skip)")
    ap.add_argument("--originals", action="store_true",
                    help="check the original 170 boards (levels.json) instead; report goes to ranking-originals.md")
    a = ap.parse_args()
    global SUFFIX
    if a.originals:
        SUFFIX = "-originals"
        data = {"packs": [dict(p, id="orig-" + p["id"]) for p in json.load(open(ORIGINALS))["packs"]]}
    else:
        data = json.load(open(BOARDS))
    os.makedirs(CHECKS, exist_ok=True)
    client = None
    if not a.dry_run:
        import anthropic
        client = anthropic.Anthropic()
    totals = {"pass": 0, "weak": 0, "fail": 0}
    everything = []
    for pack in data["packs"]:
        if a.pack and pack["id"] != a.pack:
            continue
        path = os.path.join(CHECKS, pack["id"] + ".json")
        results = json.load(open(path)) if os.path.exists(path) else {}
        entries = []
        for L in pack["levels"]:
            digest = hashlib.sha256("".join(L["rows"]).encode()).hexdigest()[:16]
            old = results.get(L["id"])
            if old and old.get("digest") == digest and old.get("grade") and not a.all:
                res = old
            elif a.dry_run:
                res = {"digest": digest, "grade": None}
            else:
                with tempfile.TemporaryDirectory() as d:
                    png = os.path.join(d, "board.png")
                    render_png(L["rows"], png)
                    try:
                        ans = ask(client, png)
                        res = dict(ans, digest=digest, grade=grade(L["name"], ans), score=score(L["name"], ans))
                    except Exception as e:  # noqa: BLE001 - one failed request shouldn't stop the run
                        res = {"digest": digest, "grade": None, "error": str(e)}
                        print(f"error {L['name']}: {str(e)[:120]}")
                        if "authentication" in str(e).lower():
                            sys.exit("No API key: set ANTHROPIC_API_KEY and run again.")
            res.update(measure(L["rows"]), theme=L.get("theme"), name=L["name"], pack=pack["id"],
                       touched=bool(L.get("touched")))
            results[L["id"]] = res
            everything.append((L, res))
            entries.append((L["rows"], res.get("grade")))
            if res.get("grade"):
                totals[res["grade"]] += 1
                print(f"{res['grade']:4}  {L['name']:<14} guess: {res.get('guess', '')!r:<28} "
                      f"readability {res.get('readability', '-')}  {', '.join(res.get('problems', []))[:70]}")
        json.dump(results, open(path, "w"), indent=1)
        sheet(entries, os.path.join(CHECKS, pack["id"] + "-graded.png"))
    if not a.dry_run:
        print(f"\npass {totals['pass']}  weak {totals['weak']}  fail {totals['fail']}")
        if a.verify_top:
            verify(client, everything, a.verify_top)
        report(everything)


def verify(client, everything, n):
    """Ask again about the best boards, blind and more carefully; flag any where the answers disagree."""
    best = sorted([e for e in everything if e[1].get("score") is not None], key=lambda e: -e[1]["score"])[:n]
    for L, res in best:
        with tempfile.TemporaryDirectory() as d:
            png = os.path.join(d, "board.png")
            render_png(L["rows"], png)
            try:
                ans = ask(client, png, effort="high")
            except Exception as e:  # noqa: BLE001
                res["verify"] = {"error": str(e)}
                continue
        again = score(L["name"], ans)
        res["verify"] = {"guess": ans["guess"], "score": again, "agrees": names_match(L["name"], ans["guess"])}
        flag = "" if res["verify"]["agrees"] else "  <-- second look disagrees"
        print(f"verify {L['name']:<14} {res['score']:3} -> {again:3}  {ans['guess']!r}{flag}")
    for pack in {L_res[1]["pack"] for L_res in best}:
        path = os.path.join(CHECKS, pack + ".json")
        results = json.load(open(path))
        for L, res in best:
            if res["pack"] == pack:
                results[L["id"]] = res
        json.dump(results, open(path, "w"), indent=1)


def report(everything):
    """ranking.md (best to worst, with what tends to go with good and bad scores) and best/worst sheets."""
    scored = sorted([e for e in everything if e[1].get("score") is not None], key=lambda e: -e[1]["score"])
    if not scored:
        return
    lines = ["# Board ranking", "", "Blind check: what Claude guessed each board shows, without being told.", "",
             "| # | Score | Board | Guess | Readability | Problems |", "|---|---|---|---|---|---|"]
    for i, (L, r) in enumerate(scored, 1):
        v = r.get("verify")
        mark = "" if not v else (" ✓" if v.get("agrees") else " ⚠ second look: " + v.get("guess", "?"))
        lines.append(f"| {i} | {r['score']} | {L['name']} ({L['id']}) | {r['guess']}{mark} | {r['readability']} | "
                     f"{'; '.join(r.get('problems', []))[:90]} |")
    # What goes with good boards: average of each measurement in the top and bottom thirds.
    k = max(1, len(scored) // 3)
    top, bottom = scored[:k], scored[-k:]
    avg = lambda group, f: sum(e[1][f] for e in group) / len(group)
    lines += ["", "## What the best and worst boards look like", "",
              "| Measure | Best third | Worst third |", "|---|---|---|"]
    for f, label in (("colors", "Colors used"), ("black", "Share of black blocks"),
                     ("biggest_patch", "Biggest flat patch (share of board)")):
        lines.append(f"| {label} | {avg(top, f):.2f} | {avg(bottom, f):.2f} |")
    lines.append(f"| Touched up by hand | {sum(e[1]['touched'] for e in top)}/{k} | "
                 f"{sum(e[1]['touched'] for e in bottom)}/{k} |")
    themes = lambda group: ", ".join(sorted({e[1]['theme'] or '?' for e in group}))
    lines += ["", f"Best third's themes: {themes(top)}", "", f"Worst third's themes: {themes(bottom)}"]
    open(os.path.join(CHECKS, f"ranking{SUFFIX}.md"), "w").write("\n".join(lines) + "\n")
    sheet([(L["rows"], r["grade"]) for L, r in scored[-15:][::-1]], os.path.join(CHECKS, f"worst{SUFFIX}.png"))
    sheet([(L["rows"], r["grade"]) for L, r in scored[:15]], os.path.join(CHECKS, f"best{SUFFIX}.png"))
    print(f"Ranking: {os.path.join(CHECKS, f'ranking{SUFFIX}.md')}")


if __name__ == "__main__":
    main()
