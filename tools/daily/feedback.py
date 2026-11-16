"""Brian's decisions from the Board Review app (queue repo history.jsonl), used to steer the board maker.

When he denies a board he can say why (quick reasons and his own words). The maker passes that on:
  - the judge sees his latest approved and denied boards, with his reasons, next to its older examples;
  - the subject picker reads his notes and the reasons he gives most often.
"""
import json
import os
from collections import Counter

from common import QUEUE


def history():
    path = os.path.join(QUEUE, "history.jsonl")
    if not os.path.exists(path):
        return []
    out = []
    for line in open(path):
        try:
            out.append(json.loads(line))
        except ValueError:
            pass
    return [h for h in out if h.get("rows") and h.get("decision") in ("approve", "deny")]


def for_judge(n_denied=12, n_approved=8):
    """His latest denials with feedback and latest approvals, oldest first."""
    h = history()
    denied = [b for b in h if b["decision"] == "deny" and (b.get("reasons") or b.get("note"))][-n_denied:]
    approved = [b for b in h if b["decision"] == "approve"][-n_approved:]
    keep = {id(b) for b in denied + approved}
    return [b for b in h if id(b) in keep]


def for_subjects(n=40):
    """A few lines for the subject picker: his most common reasons and his latest notes, or "" if none yet."""
    denied = [b for b in history() if b["decision"] == "deny"][-n:]
    reasons = Counter(r for b in denied for r in b.get("reasons") or [])
    notes = [f'- "{b["name"]}": {b["note"]}' for b in denied if b.get("note")][-12:]
    if not reasons and not notes:
        return ""
    lines = ["", "The designer's recent feedback on boards he denied. Choose subjects, colors and settings that avoid "
                 "these problems:"]
    if reasons:
        lines.append("Most common reasons: " + ", ".join(f"{r} ({k})" for r, k in reasons.most_common(6)) + ".")
    if notes:
        lines.append("His notes:")
        lines += notes
    return "\n".join(lines)
