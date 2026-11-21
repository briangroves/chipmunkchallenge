"""One picture-level score for the board judge, from a local CLIP model (open_clip ViT-B-32, laion2b weights, about
600 MB, downloaded once into ~/.cache/huggingface; no API calls).

`face(rows_list)` renders each board in the game's colors and asks CLIP how much more it looks like "a cartoon animal
with a clear cute face and big eyes" than "a blurry unclear blob". Tested 2026-11-21 on Brian's 534 decisions: added
to the blob stats, it raised AUC on the 224 re-reviewed game boards from 0.76 to 0.79 (trained on the new boards
only), and catches some "Face hard to read" / "Doesn't look like its name" boards that blob stats can't see.
Training CLIP's whole picture embedding on his decisions did worse (it overfits 534 boards); this one fixed question
generalizes.

Scores are cached by board (STATE/clip-face.json), so refitting the judge each subject costs nothing new.
If open_clip or its weights aren't available, `available()` is False and the judge runs on blob stats alone.
"""
import hashlib
import json
import os

STATE = os.environ.get("CHIPMUNK_BOARDS_STATE", os.path.expanduser("~/Library/Application Support/ChipmunkBoards"))
CACHE = os.path.join(STATE, "clip-face.json")
GOOD, BAD = "a cartoon animal with a clear cute face and big eyes", "a blurry unclear blob"
_model = None


def _load():
    global _model
    if _model is None:
        import open_clip
        import torch
        try:  # the weights are cached after the first download; don't ask the Hugging Face hub every refit
            os.environ["HF_HUB_OFFLINE"] = "1"
            m, _, pre = open_clip.create_model_and_transforms("ViT-B-32", pretrained="laion2b_s34b_b79k")
        except Exception:  # noqa: BLE001  (not downloaded yet)
            os.environ.pop("HF_HUB_OFFLINE")
            m, _, pre = open_clip.create_model_and_transforms("ViT-B-32", pretrained="laion2b_s34b_b79k")
        finally:  # only for this load: leave the rest of the process (the image model) as it was
            os.environ.pop("HF_HUB_OFFLINE", None)
        m.eval()
        tok = open_clip.get_tokenizer("ViT-B-32")
        with torch.no_grad():
            e = m.encode_text(tok([GOOD, BAD]))
            e = e / e.norm(dim=-1, keepdim=True)
        _model = (m, pre, (e[0] - e[1]).numpy())
    return _model


def available():
    try:
        _load()
        return True
    except Exception:  # noqa: BLE001  (not installed, or weights can't be fetched offline)
        return False


def render(rows, z=8):
    import numpy as np
    from PIL import Image
    from palette import DROPPED, PALETTE
    col = {**PALETTE, **DROPPED}
    a = np.full((len(rows), max(map(len, rows)), 3), 255, np.uint8)
    for r, row in enumerate(rows):
        for c, ch in enumerate(row):
            v = col.get(ch, 0xFFFFFF)
            a[r, c] = ((v >> 16) & 255, (v >> 8) & 255, v & 255)
    return Image.fromarray(a).resize((a.shape[1] * z, a.shape[0] * z), Image.NEAREST)


def key(rows):
    return hashlib.sha1("\n".join(rows).encode()).hexdigest()[:16]


def face(rows_list):
    import torch
    try:
        cache = json.load(open(CACHE))
    except (OSError, ValueError):
        cache = {}
    todo = [rows for rows in rows_list if key(rows) not in cache]
    if todo:
        m, pre, d = _load()
        for i in range(0, len(todo), 32):
            batch = todo[i:i + 32]
            with torch.no_grad():
                e = m.encode_image(torch.stack([pre(render(r)) for r in batch]))
                e = (e / e.norm(dim=-1, keepdim=True)).numpy()
            for rows, s in zip(batch, e @ d):
                cache[key(rows)] = round(float(s), 5)
        os.makedirs(os.path.dirname(CACHE), exist_ok=True)
        with open(CACHE + ".tmp", "w") as f:
            json.dump(cache, f)
        os.replace(CACHE + ".tmp", CACHE)
    return [cache[key(rows)] for rows in rows_list]
