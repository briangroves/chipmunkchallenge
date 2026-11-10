#!/usr/bin/env python3
"""Redraw original boards that read badly, from clipart, in place.

    python3 tools/replace_originals.py              # every board listed in REDRAW below
    python3 tools/replace_originals.py pets-17      # just these original ids

Each listed original (by its id in levels.json) gets candidates the same way make_pack builds a board: clipart from
Openverse and openclipart, put on a backdrop, shown to Claude blind (check_boards). The best one replaces the original
only if it passes the blind check and scores higher than the original did (tools/packs/checks/orig-<pack>.json, from
`check_boards.py --originals`). Replacements go into boards.json under "replace", keyed by the original id; the
board keeps its number and pack in the game, only its picture changes. Backdrops use their own variant range
(from 200), so no background repeats one used elsewhere.
"""
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import backdrops  # noqa: E402
import make_pack as mp  # noqa: E402

ORIGINALS = os.path.join(mp.ROOT, "Engine/Sources/ChipmunkEngine/Resources/levels.json")
CHECKS = os.path.join(HERE, "packs", "checks")
VARIANT_BASE = 200

# Original board id -> what to draw instead (a make_pack subject). City boards get their landmark.
REDRAW = {
    "cities-2": {"name": "Big Ben", "match": ["big ben", "clock tower", "london"]},
    "cities-4": {"name": "Leaning Tower of Pisa", "query": "leaning tower of pisa clipart", "match": ["pisa", "leaning"]},
    "cities-5": {"name": "Pyramids", "match": ["pyramid"]},
    "cities-9": {"name": "Kremlin", "query": "kremlin moscow clipart", "match": ["kremlin", "basil", "moscow"]},
    "cities-11": {"name": "Space Needle", "query": "space needle seattle", "match": ["space needle", "seattle"]},
    "cities-13": {"name": "Taj Mahal", "match": ["taj mahal"]},
    "cities-16": {"name": "Gondola", "query": "venice gondola clipart", "match": ["gondola", "venice"]},
    "cities-19": {"name": "Mosque", "query": "mosque clipart", "match": ["mosque", "istanbul"]},
    "pets-4": {"name": "Hamster"},
    "pets-9": {"name": "Mouse", "avoid": ["computer", "cursor"]},
    "pets-10": {"name": "Puppy", "match": ["puppy", "dog"]},
    "pets-12": {"name": "Guinea Pig"},
    "pets-15": {"name": "Dalmatian"},
    "pets-17": {"name": "Hedgehog"},
    "pets-19": {"name": "Gecko", "match": ["gecko", "lizard"]},
    "space-6": {"name": "Comet"},
    "space-9": {"name": "Satellite"},
    "ocean-10": {"name": "Dolphin"},
    "ocean-12": {"name": "Seashell", "match": ["shell"]},
    "ocean-19": {"name": "Sea Urchin", "match": ["urchin"]},
    "plants-18": {"name": "Succulent", "match": ["succulent", "cactus"]},
    "food-18": {"name": "Fried Egg", "match": ["fried egg", "egg"]},
    "transport-12": {"name": "Motorcycle", "match": ["motorcycle", "motorbike"]},
    "forest-5": {"name": "Capybara"},
    "forest-7": {"name": "Chipmunk"},
    "forest-8": {"name": "Little Chipmunk", "query": "chipmunk cartoon clipart", "match": ["chipmunk"]},
    "forest-10": {"name": "Squirrel", "query": "squirrel acorn clipart", "match": ["squirrel"]},
    "forest-13": {"name": "Doe", "query": "deer doe cartoon clipart", "match": ["doe", "deer", "fawn"]},
    "forest-14": {"name": "Fawn", "match": ["fawn", "deer"]},
    "storybook-8": {"name": "Baby Dragon", "match": ["dragon"]},
}

THEMES = {"cities": ["city", "land"], "space": ["space"], "ocean": ["water"], "storybook": ["land", "indoor"],
          "pets": ["land", "indoor"], "food": ["indoor", "land"]}


def main():
    want = sys.argv[1:] or list(REDRAW)
    orig = {L["id"]: (p["id"], L) for p in json.load(open(ORIGINALS))["packs"] for L in p["levels"]}
    data = json.load(open(mp.BOARDS))
    data.setdefault("replace", {})
    import anthropic
    client = anthropic.Anthropic()
    names = [t["name"] for t in backdrops.THEMES]
    used = {i: VARIANT_BASE for i in range(len(names))}
    for R in data["replace"].values():
        i = names.index(R["theme"])
        used[i] = max(used[i], R["variant"] + 1)
    recent = []
    taken = {L["source"]["id"] for p in data["packs"] for L in p["levels"] if L["source"].get("id")} | \
            {R["source"]["id"] for R in data["replace"].values()}
    sigfile = os.path.join(mp.CACHE, "signatures.json")
    allsig = json.load(open(sigfile)) if os.path.exists(sigfile) else {}
    sigs = [set(v) for v in allsig.values()]
    checks_path = os.path.join(CHECKS, "replacements.json")
    checks = json.load(open(checks_path)) if os.path.exists(checks_path) else {}
    for oid in want:
        pack, L = orig[oid]
        old = json.load(open(os.path.join(CHECKS, f"orig-{pack}.json"))).get(oid, {})
        old_score = old.get("score") or 0
        subject = mp.normalize({"subjects": [dict(REDRAW[oid])]})["subjects"][0]
        index = list(orig).index(oid)
        print(f"Board {index + 1} ({oid}, '{L['name']}', scored {old_score}) -> {subject['name']}")
        groups = THEMES.get(pack, ["land"])
        board = mp.best_board(subject, lambda **kw: backdrops.pick_themes(groups, used, recent, **kw), taken, sigs,
                              client)
        if not board:
            print("   -> no usable image; keeping the original")
            continue
        c = board.pop("check", {})
        if c.get("grade") != "pass" or (c.get("score") or 0) <= old_score:
            print(f"   -> best scored {c.get('score')} ({c.get('grade')}); keeping the original")
            continue
        new_id = f"{subject['name'].lower().replace(' ', '-')}-r{index + 1}"
        sig = board.pop("sig")
        allsig[new_id] = sig
        sigs.append(set(sig))
        taken.add(board["source"]["id"])
        i = names.index(board["theme"])
        used[i] = board["variant"] + 1
        recent = (recent + [i])[-12:]
        data["replace"][oid] = {"id": new_id, "name": board["name"], "rows": board["rows"], "theme": board["theme"],
                                "variant": board["variant"], "source": board["source"]}
        checks[new_id] = dict(c, replaces=oid, was=old_score)
        print(f"   -> replaced ({old_score} -> {c['score']}) on {board['theme']} #{board['variant'] + 1}")
        # Save after each board, so a stop part way keeps what's done.
        json.dump(data, open(mp.BOARDS, "w"), separators=(",", ":"))
        json.dump(checks, open(checks_path, "w"), indent=1)
        json.dump(allsig, open(sigfile, "w"))
    print(f"{len(data['replace'])} original boards redrawn")


if __name__ == "__main__":
    main()
