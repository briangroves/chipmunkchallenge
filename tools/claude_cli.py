"""Ask Claude through the `claude` command line, signed in to Brian's Claude account, instead of the API key.

The board maker's two Claude calls (proposing subjects, judging boards) go through `ask`, so they count against the
Claude plan's usage limits rather than API credits. Sign in once in Terminal:

    claude auth login

`ask(content, schema)` takes Messages-API content blocks (text and base64 images) and returns the JSON object
matching `schema`.
"""
import glob
import json
import os
import shutil
import subprocess
import tempfile

MODEL = "claude-opus-5-5"


def find():
    """The `claude` program: on PATH, the standalone install, or the copy inside the Claude desktop app."""
    for p in [shutil.which("claude"), os.path.expanduser("~/.local/bin/claude"), os.path.expanduser("~/.claude/local/claude")]:
        if p and os.path.exists(p):
            return p
    bundled = sorted(glob.glob(os.path.expanduser(
        "~/Library/Application Support/Claude/claude-code/*/*/claude.app/Contents/MacOS/claude")), key=os.path.getmtime)
    if bundled:
        return bundled[-1]
    raise RuntimeError("the claude command line isn't installed")


def ask(content, schema, effort="medium", timeout=900):
    env = {k: v for k, v in os.environ.items() if k != "ANTHROPIC_API_KEY"}  # use the Claude account sign-in
    msg = {"type": "user", "message": {"role": "user", "content": content}}
    with tempfile.TemporaryDirectory() as cwd:  # nowhere near a project: no CLAUDE.md, no project settings
        r = subprocess.run(
            [find(), "-p", "--input-format", "stream-json", "--output-format", "stream-json", "--verbose",
             "--model", MODEL, "--effort", effort, "--json-schema", json.dumps(schema), "--tools", "",
             "--setting-sources", "", "--strict-mcp-config", "--no-session-persistence"],
            input=json.dumps(msg) + "\n", capture_output=True, text=True, env=env, cwd=cwd, timeout=timeout)
    result = None
    for line in r.stdout.splitlines():
        try:
            ev = json.loads(line)
        except ValueError:
            continue
        if ev.get("type") == "result":
            result = ev
    if result is None:
        raise RuntimeError(f"claude gave no result (exit {r.returncode}): {(r.stderr or r.stdout)[-500:]}")
    if result.get("is_error"):
        raise RuntimeError(f"claude: {result.get('result') or result.get('subtype')}")
    out = result.get("structured_output")
    if out is None:
        out = json.loads(result["result"])
    return out
