"""Exercise cache and radar isolation across disposable vaults."""
import fcntl
import json
import os
from pathlib import Path
import sqlite3
import subprocess
import sys
import tempfile

bridge = Path(sys.argv[1]).resolve()

with tempfile.TemporaryDirectory(prefix="bigbrain-vault-isolation-") as temporary:
    root = Path(temporary).resolve()
    state = root / "state"
    first = root / "first"
    second = root / "second"
    for vault, note in ((first, "# First\n\nVaultABoundaryMarker"), (second, "# Second\n\nVaultBBoundaryMarker")):
        (vault / ".obsidian").mkdir(parents=True)
        (vault / "note.md").write_text(note)
    (first / "only-first.md").write_text("# Other note")
    inbox = first / "BigBrain Agent/Inkorg/source.md"
    inbox.parent.mkdir(parents=True)
    inbox.write_text("# Source\n\nVault A-only input.")

    def call(vault, *args, payload=None, fail=False):
        env = dict(os.environ, BIGBRAIN_AGENT_HOME=str(state), CODEX_HOME=str(root / "codex"))
        if vault is not None:
            env["BIGBRAIN_VAULT"] = str(vault)
        else:
            env.pop("BIGBRAIN_VAULT", None)
        result = subprocess.run([str(bridge), *args], env=env, text=True, capture_output=True,
                                input=json.dumps(payload) if payload is not None else None, timeout=10)
        assert (result.returncode != 0) == fail, (args, result.stdout, result.stderr)
        return json.loads(result.stdout)

    call(first, "index")
    with (state / "index.lock").open("a") as guard:
        fcntl.flock(guard, fcntl.LOCK_EX)
        hits = call(first, "search", "VaultABoundaryMarker", "--fast")
        assert len(hits) == 1 and hits[0]["file"] == str(first / "note.md")
        assert call(second, "search", "VaultABoundaryMarker", "--fast") == []
        assert call(second, "atlas")["nodes"] == []
        assert call(second, "dashboard")["notes"] == 0
        assert not call(second, "activate", "note:note.md", "note:only-first.md")["learned"]
    assert not call(second, "activate", "note:note.md", "note:only-first.md")["learned"]
    assert call(first, "activate", "note:note.md", "note:only-first.md")["learned"]

    # A read-only caller can read a correctly scoped snapshot after a write failure.
    index_lock = state / "index.lock"
    index_lock.unlink()
    index_lock.mkdir()
    assert call(first, "search", "VaultABoundaryMarker", "--fast")[0]["file"] == str(first / "note.md")
    assert call(second, "search", "VaultABoundaryMarker", "--fast") == []
    index_lock.rmdir()

    (state / "radar.json").write_text(json.dumps({"answer": "Legacy report"}))
    assert call(first, "dashboard")["radar"] == {}
    (state / "radar.json").write_text(json.dumps({"vault": str(first), "result": {"answer": "Vault A report"}}))
    assert call(first, "dashboard")["radar"]["answer"] == "Vault A report"
    assert call(second, "dashboard")["radar"] == {}
    hits = call(second, "search", "VaultBBoundaryMarker", "--fast")
    assert len(hits) == 1 and hits[0]["file"] == str(second / "note.md")

    # Simulate a vector index that still holds a deleted excerpt from an older snapshot.
    fake_qmd = root / "fake-qmd"
    fake_qmd.write_text("""#!/bin/sh
printf '%s\n' '[{"file":"qmd://bigbrain/note.md","snippet":"DeletedVectorExcerpt"}]'
""")
    fake_qmd.chmod(0o700)
    (state / "settings.json").write_text(json.dumps({"qmd": str(fake_qmd)}))
    with sqlite3.connect(state / "library.sqlite3") as db:
        db.execute("INSERT OR REPLACE INTO metadata VALUES (?, ?)", ("vector_vault", str(second)))
    vector_hits = call(second, "search", "DeletedVectorExcerpt")
    assert len(vector_hits) == 1 and vector_hits[0]["match"] == "vector"
    assert "VaultBBoundaryMarker" in vector_hits[0]["excerpt"]
    assert "DeletedVectorExcerpt" not in vector_hits[0]["excerpt"]
    with (state / "vectors.lock").open("a") as guard:
        fcntl.flock(guard, fcntl.LOCK_EX)
        assert call(second, "search", "DeletedVectorExcerpt") == []
    assert call(first, "search", "DeletedVectorExcerpt") == []

    ingest = {"mode": "ingest", "path": str(inbox.relative_to(first))}
    prepared = call(first, "local-prompt", payload=ingest)
    reply = {"answer": "Done", "path": "BigBrain Agent/Wiki/new.md", "replacement": "# Vault A-only output"}
    finish = {"state": prepared["state"], "reply": reply}
    assert "Biblioteket ändrades" in call(second, "local-finish", payload=finish, fail=True)["error"]
    assert not call(second, "dashboard")["proposals"]
    staged = call(first, "local-finish", payload=finish)["proposal"]
    assert call(first, "proposal", staged)["replacement"] == "# Vault A-only output\n"

    fake_codex = root / "fake-codex"
    fake_codex.write_text(f"""#!/usr/bin/env python3
import json
from pathlib import Path
import sys
sys.stdin.read()
Path({str(state / "settings.json")!r}).write_text(json.dumps({{"vault": {str(second)!r}}}))
Path(sys.argv[sys.argv.index("-o") + 1]).write_text(json.dumps({reply!r}))
""")
    fake_codex.chmod(0o700)
    (state / "settings.json").write_text(json.dumps({"vault": str(first), "codex": str(fake_codex)}))
    assert "Biblioteket ändrades" in call(None, "agent", payload=ingest, fail=True)["error"]
    assert not call(second, "dashboard")["proposals"]
    print("PASS: scoped caches, read-only fallback, radar, vector excerpts, graph learning and agent runs")
