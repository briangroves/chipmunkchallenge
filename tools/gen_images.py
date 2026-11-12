#!/usr/bin/env python3
"""Generate source pictures for new boards on this Mac (no API calls), with Z-Image-Turbo through mflux.

    tools/.venv/bin/python tools/gen_images.py tools/pilot/subjects.json --seeds 8

Each subject gets `--seeds` pictures, made round-robin (seed 1 of every subject, then seed 2...) so the first full set
is ready early. Pictures go to ~/Library/Caches/chipmunk-boards/gen/<subject>/s<seed>.png; existing ones are skipped,
so a stopped run picks up where it left off.

The prompt asks for what Brian's 5-star boards have in common: one big, centered, cute subject, whole and not cut off,
with a bold outline, bright saturated colors with simple shading, and a simple backdrop that suits it.
"""
import argparse
import json
import os
import re
import time

MODEL = "filipstrand/Z-Image-Turbo-mflux-4bit"
OUT = os.path.expanduser("~/Library/Caches/chipmunk-boards/gen")
STYLE = ("Cute cartoon illustration for a children's game: {thing}. The {name} is big and centered, filling about "
         "two thirds of the picture, with a clear margin of background on every side so no part touches the edge. "
         "Thick bold black outlines, bright saturated colors with rich shading in light and dark tones, and bold "
         "patterns on the {name} (spots, stripes, panels or markings that suit it). Background: a colorful scene with "
         "three or four big, bold, simple features chosen from: {scene}. Each background feature is large and chunky "
         "with a thick outline and solid colors, so it still reads when the whole picture is shrunk to a tiny 40 by "
         "40 pixel icon; no tiny details and no big empty areas. The background colors contrast with the {name} so "
         "it stands out. Clean cartoon art, no text, no border, no frame.")


def slug(name):
    return re.sub(r"[^a-z0-9]+", "-", name.lower()).strip("-")


def prompt(s):
    return STYLE.format(thing=s["thing"], name=s["name"].lower(), scene=s["scene"])


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("spec")
    ap.add_argument("--seeds", type=int, default=8)
    ap.add_argument("--size", type=int, default=768)
    ap.add_argument("--steps", type=int, default=9)
    ap.add_argument("--out", default=OUT, help="folder for the pictures (one subfolder per subject)")
    a = ap.parse_args()
    subjects = json.load(open(a.spec))["subjects"]
    from mflux.models.common.config import ModelConfig
    from mflux.models.z_image import ZImage
    model = ZImage(model_config=ModelConfig.z_image_turbo(), model_path=MODEL)
    for seed in range(1, a.seeds + 1):
        for s in subjects:
            d = os.path.join(a.out, slug(s["name"]))
            os.makedirs(d, exist_ok=True)
            path = os.path.join(d, f"s{seed}.png")
            if os.path.exists(path):
                continue
            t = time.time()
            img = model.generate_image(seed=seed * 1000 + len(s["name"]), prompt=prompt(s),
                                       num_inference_steps=a.steps, width=a.size, height=a.size)
            img.save(path + ".tmp.png")
            os.replace(path + ".tmp.png", path)
            print(f"{s['name']} seed {seed}: {time.time() - t:.0f}s", flush=True)


if __name__ == "__main__":
    main()
