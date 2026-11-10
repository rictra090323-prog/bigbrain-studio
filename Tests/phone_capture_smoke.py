"""Exercise the Swift capture format through the Mac bridge in an isolated library."""
from concurrent.futures import ThreadPoolExecutor
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
from uuid import uuid4

bridge = Path(sys.argv[1]).resolve()
payload = Path(sys.argv[2]).read_bytes()

with tempfile.TemporaryDirectory(prefix="bigbrain-phone-") as tmp:
    root = Path(tmp).resolve()
    vault = root / "vault"
    (vault / ".obsidian").mkdir(parents=True)
    env = dict(os.environ, BIGBRAIN_AGENT_HOME=str(root / "agent"),
               BIGBRAIN_VAULT=str(vault), CODEX_HOME=str(root / "codex"))

    def run(*args, data=b"", fail=False):
        result = subprocess.run([str(bridge), *args], input=data, capture_output=True, env=env, timeout=30)
        assert (result.returncode != 0) == fail, (args, result.stdout, result.stderr)
        return json.loads(result.stdout)

    def receive(data=payload):
        return run("import-phone-capture", data=data)

    run("import-phone-capture", data=payload[:-3], fail=True)
    for invalid in (
        {"version": 2},
        {"id": "../../private"},
        {"id": 1},
        {"id": str(uuid4()), "text": "\ud800"},
        {"id": str(uuid4()), "text": "Å" * 32_769},
        {"id": str(uuid4()), "text": "\r\n "},
    ):
        run("import-phone-capture", data=json.dumps(json.loads(payload) | invalid).encode(), fail=True)
    run("import-phone-capture", data=b" " * 524_289, fail=True)
    assert not list(vault.rglob("*.md"))

    with ThreadPoolExecutor(max_workers=4) as pool:
        results = list(pool.map(receive, [payload] * 4))
    assert sum(result["created"] for result in results) == 1, results
    notes = [result["note"] for result in results]
    assert all(note == notes[0] for note in notes)
    note = notes[0]
    assert "jordgubbsnebulosa 🍓" in note["body"] and list(vault.rglob("*.md")) == [Path(note["file"])]
    hits = run("search", "--fast", "jordgubbsnebulosa")
    assert any(hit["path"] == note["path"] for hit in hits), hits
    atlas = run("atlas", "--query=jordgubbsnebulosa")
    assert any(node["path"] == note["path"] for node in atlas["nodes"]), atlas

    changed = run("save-note", note["path"], note["revision"], "-", data="Redigerat på Mac.\n".encode())
    repeated = receive()
    assert not repeated["created"] and repeated["note"] == changed
    changed_phone = json.loads(payload) | {"text": "Samma id med annan text"}
    assert receive(json.dumps(changed_phone).encode())["note"] == changed

    next_capture = json.loads(payload) | {"id": str(uuid4())}
    assert receive(json.dumps(next_capture).encode())["created"]
    assert len(list(vault.rglob("*.md"))) == 2

print("PASS: Swift file format, malformed input, concurrent retry, search, Atlas and preserved edits")
