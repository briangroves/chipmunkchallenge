#!/usr/bin/env python3
"""A board judge calibrated to Brian's own star ratings.

Claude sees example boards Brian rated (1 to 5 stars), then rates a new board the way he would. A new board maker
uses it to keep only boards that would earn 4 or 5 stars.

    python3 tools/judge_boards.py --ratings ratings.csv --test           # rate the held-out boards, compare with Brian
    python3 tools/judge_boards.py --ratings ratings.csv --test --limit 20

The examples are a fixed, stratified sample of the ratings (EXAMPLES_PER_STAR per star level); the rest are held out
to measure agreement. Results are cached by board digest in ~/Library/Caches/chipmunk-boards/judge.
"""
import argparse
import base64
import csv
import hashlib
import json
import os
import random
import statistics as st
import sys
import tempfile
from concurrent.futures import ThreadPoolExecutor

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import check_boards as cb  # noqa: E402

ROOT = os.path.dirname(HERE)
RES = os.path.join(ROOT, "Engine/Sources/ChipmunkEngine/Resources")
CACHE = os.path.expanduser("~/Library/Caches/chipmunk-boards/judge")
MODEL = "claude-opus-5-5"
EXAMPLES_PER_STAR = 8
PROMPT_VERSION = "v1"

RUBRIC = """You rate pictures for a kids' puzzle game the way the game's designer does. Each picture is a 40x40 grid
of colored blocks (pixel art) with a subject and a backdrop. The designer rates each 1 to 5 stars:

5 - delightful: a big, centered subject filling most of the board, never cut off; bright saturated colors with
    light and dark shades inside the subject so it looks rounded; a clear dark outline; often a cute character with
    a face and eyes; a backdrop that suits the subject (a fish underwater, a crab on a beach) and contrasts with it.
4 - good: clearly the named thing and pleasant to look at, with one small weakness.
3 - okay: recognisable but plain - flat colors, so-so size, generic backdrop.
2 - weak: hard to read or unappealing - small or awkward subject, muddy or dark colors, backdrop that clashes or
    doesn't fit, odd pose, looks like a different thing.
1 - bad: a dark or muddy blob with no detail, a flat silhouette, a leftover rectangle/card/frame from the source
    image, a subject cut off or tiny, a photo shrunk to mush, a scene that makes no sense (a whale on a brick wall),
    or something that doesn't look like its name at all.

The designer is strict: most boards get 2 or 3; 5 is rare. Judge appeal as much as recognisability. The designer
knows each board's name, so a board that doesn't look like its name loses stars."""

SCHEMA = {
    "type": "object",
    "properties": {"reason": {"type": "string"}, "stars": {"type": "integer"}},
    "required": ["reason", "stars"],
    "additionalProperties": False,
}


def all_rows():
    rows = {}
    for p in json.load(open(os.path.join(RES, "levels.json")))["packs"]:
        for L in p["levels"]:
            rows[L["id"]] = L["rows"]
    nb = json.load(open(os.path.join(RES, "boards.json")))
    for R in nb.get("replace", {}).values():
        rows[R["id"]] = R["rows"]
    for p in nb["packs"]:
        for L in p["levels"]:
            rows[L["id"]] = L["rows"]
    return rows


def png_b64(rows):
    with tempfile.TemporaryDirectory() as d:
        path = os.path.join(d, "b.png")
        cb.render_png(rows, path, z=10)
        return base64.standard_b64encode(open(path, "rb").read()).decode()


def split(ratings):
    """A fixed stratified sample of examples per star level; the rest are held out."""
    rnd = random.Random(7)
    examples = []
    for s in range(1, 6):
        group = [r for r in ratings if r["stars"] == s]
        rnd.shuffle(group)
        examples += group[:EXAMPLES_PER_STAR]
    ids = {r["id"] for r in examples}
    rnd.shuffle(examples)
    return examples, [r for r in ratings if r["id"] not in ids]


def example_blocks(examples, rows):
    content = [{"type": "text", "text": RUBRIC + "\n\nHere are boards the designer has rated:"}]
    for r in examples:
        content.append({"type": "image", "source": {"type": "base64", "media_type": "image/png",
                                                    "data": png_b64(rows[r["id"]])}})
        content.append({"type": "text", "text": f'"{r["name"]}": {r["stars"]} star{"s" if r["stars"] > 1 else ""}'})
    content[-1]["cache_control"] = {"type": "ephemeral"}
    return content


class Judge:
    def __init__(self, client, examples, rows):
        self.client = client
        self.prefix = example_blocks(examples, rows)
        self.key = hashlib.sha1((PROMPT_VERSION + RUBRIC + json.dumps(
            [(r["id"], r["stars"]) for r in examples])).encode()).hexdigest()[:10]
        os.makedirs(CACHE, exist_ok=True)

    def rate(self, name, rows):
        digest = hashlib.sha1((self.key + name + "".join(rows)).encode()).hexdigest()[:16]
        path = os.path.join(CACHE, digest + ".json")
        if os.path.exists(path):
            return json.load(open(path))
        response = self.client.beta.messages.create(
            model=MODEL,
            max_tokens=3000,
            output_config={"effort": "medium", "format": {"type": "json_schema", "schema": SCHEMA}},
            betas=["server-side-fallback-2026-07-01"],
            fallbacks="default",
            messages=[{"role": "user", "content": self.prefix + [
                {"type": "text", "text": f'Now rate this board, named "{name}". Give a one-sentence reason, then '
                                         'the stars (1-5) the designer would give.'},
                {"type": "image", "source": {"type": "base64", "media_type": "image/png", "data": png_b64(rows)}},
            ]}],
        )
        if response.stop_reason == "refusal":
            raise RuntimeError("declined")
        out = json.loads(next(b.text for b in response.content if b.type == "text"))
        out["stars"] = max(1, min(5, int(out["stars"])))
        json.dump(out, open(path, "w"))
        return out


def load_ratings(path):
    return [dict(id=r["id"], name=r["name"], stars=int(r["stars"]), claude=int(r["claude_score"] or 0))
            for r in csv.DictReader(open(path))]


def corr(xs, ys):
    mx, my = st.mean(xs), st.mean(ys)
    sx = sum((x - mx) ** 2 for x in xs) ** 0.5
    sy = sum((y - my) ** 2 for y in ys) ** 0.5
    return sum((x - mx) * (y - my) for x, y in zip(xs, ys)) / (sx * sy)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--ratings", required=True)
    ap.add_argument("--test", action="store_true")
    ap.add_argument("--limit", type=int)
    ap.add_argument("--out")
    a = ap.parse_args()
    import anthropic
    client = anthropic.Anthropic()
    rows = all_rows()
    ratings = load_ratings(a.ratings)
    examples, held = split(ratings)
    if a.limit:
        held = random.Random(3).sample(held, a.limit)
    judge = Judge(client, examples, rows)

    def go(r):
        try:
            return r, judge.rate(r["name"], rows[r["id"]])
        except Exception as e:  # noqa: BLE001
            if "authentication" in str(e).lower():
                raise
            print("  error", r["id"], e, file=sys.stderr)
            return r, None

    with ThreadPoolExecutor(8) as pool:
        results = [(r, j) for r, j in pool.map(go, held) if j]
    you = [r["stars"] for r, _ in results]
    it = [j["stars"] for _, j in results]
    n = len(results)
    print(f"{len(examples)} examples, {n} held-out boards rated")
    print(f"exact match {sum(x == y for x, y in zip(you, it)) / n:.0%}, within one star "
          f"{sum(abs(x - y) <= 1 for x, y in zip(you, it)) / n:.0%}, correlation {corr(you, it):+.2f}")
    print(f"(blind-check score vs your stars on the same boards: {corr(you, [r['claude'] for r, _ in results]):+.2f})")
    print("your stars -> judge's average:")
    for s in range(1, 6):
        g = [j["stars"] for r, j in results if r["stars"] == s]
        if g:
            print(f"  {s}: n={len(g):3d} judge mean {st.mean(g):.2f}  "
                  f"dist {[g.count(k) for k in range(1, 6)]}")
    keep = [(r, j) for r, j in results if j["stars"] >= 4]
    if keep:
        ks = [r["stars"] for r, _ in keep]
        print(f"boards the judge would keep (4+): {len(keep)}; your average for them {st.mean(ks):.2f}; "
              f"{sum(k >= 4 for k in ks)} you rated 4+, {sum(k <= 2 for k in ks)} you rated 1-2")
    if a.out:
        json.dump([dict(r, judge=j) for r, j in results], open(a.out, "w"), indent=1)


if __name__ == "__main__":
    main()
