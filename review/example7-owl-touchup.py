"""Feature pass on the converted owl: keep the converted hat (rows 0-16), redraw the body block by block.
'.' shows the backdrop; the owl sits at columns 7-31, rows 17-36."""
import json, sys
sys.path.insert(0, "/Users/briangroves/Developer/chipmunkchallenge/tools")
import image_to_board as t

src, dst = sys.argv[1], sys.argv[2]
d = json.load(open(src))
g = [list(r) for r in d["rows"]]
bg = t.backdrop()

#        cols 7........................31
OWL = [
    "..KNNNNNNNNNNNNNNNNNNK...",   # 17
    ".KNNNNWWWNNNNNWWWNNNNNK..",   # 18  eyes: white circles
    ".KNNNWWWWWNNNWWWWWNNNNK..",   # 19
    ".KNNNWWWKKNENWWWKKWNNNEK.",   # 20  pupils with a highlight, brows
    ".KNNNWWWKKNNNWWWKKWNNNEK.",   # 21
    ".KNNNNWWWNNOONNWWWNNNNEK.",   # 22  beak
    "KNNNNNNNNNNQONNNNNNNNNEEK",   # 23
    "KNNNNNNWWWWNNNNKKKKKNNEEK",   # 24  chest; briefcase handle
    "KNNEKNWWWWWWNNNKTTTKNNEEK",   # 25
    "KNNEKNWWWWWWWKKKKKKKKKKK.",   # 26  briefcase top
    "KNNEKNWWWWWWWKTTTTTTTTTTK",   # 27
    "KNNEKNWWWWWWWKNNNNYNNNNNK",   # 28  flap and clasp
    ".KNEKNWWWWWWXKTTTTTTTTTTK",   # 29
    ".KNEKNNWWWWWXKTTTTTTTTTNK",   # 30
    "..KEKNNWWWWXXKTTTTTTTTNNK",   # 31
    "...KENNNWWXXXKNNNNNNNNNNK",   # 32
    "....KENNNNNNNKKKKKKKKKKK.",   # 33
    ".....KKOOOKKOOOKK........",   # 34  feet
    "......KOQOK.KOQOK........",   # 35
    ".......K.K...K.K.........",   # 36
]
assert all(len(r) == 25 for r in OWL), [len(r) for r in OWL]
for i, row in enumerate(OWL):
    r = 17 + i
    for j, ch in enumerate(row):
        c = 7 + j
        g[r][c] = bg[r][c] if ch == "." else ch
d["rows"] = ["".join(r) for r in g]
d["name"] = "Owl off to work"
json.dump(d, open(dst, "w"), indent=1)

# The owl's shadow on the grass, as on converted boards.
d2 = json.load(open(dst))
g2 = [list(r) for r in d2["rows"]]
cells = {(17 + i, 7 + j): ch for i, row in enumerate(OWL) for j, ch in enumerate(row) if ch != "."}
t.ground_shadow(g2, cells)
d2["rows"] = ["".join(r) for r in g2]
json.dump(d2, open(dst, "w"), indent=1)
