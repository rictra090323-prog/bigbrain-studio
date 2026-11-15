"""Verify the library browse path and cached previews across scans and vaults."""
import json
import os
from pathlib import Path
import sqlite3
import subprocess
import sys
import tempfile

bridge = Path(sys.argv[1]).resolve()

with tempfile.TemporaryDirectory(prefix="bigbrain-library-") as directory:
    root = Path(directory).resolve()
    vault = root / "vault"
    (vault / ".obsidian").mkdir(parents=True)
    agent = root / "agent"
    env = dict(os.environ, BIGBRAIN_VAULT=str(vault), BIGBRAIN_AGENT_HOME=str(agent),
               CODEX_HOME=str(root / "codex"))
    for index in range(31):
        (vault / f"{index:02d}.md").write_text(f"# Anteckning {index:02d}\n\nGemensamt ord i provtext.\n")
    note = vault / "special:note.md"
    note.write_text("---\ntitle: Privat metadata\n---\n# Abborre\n\n"
                    "```sh\nkodrad\n```\n\nSyntetisk **rapport**. Andra meningen. Tredje meningen.\n")

    def run(*args, environment=env):
        output = subprocess.check_output([str(bridge), *args], env=environment, text=True, timeout=30)
        return json.loads(output)

    rows = run("library")
    assert len(rows) == 32
    assert rows[0]["title"] == "Abborre"
    assert rows[0]["preview"] == "Syntetisk rapport. Andra meningen."
    assert rows[0]["modifiedAt"] == note.stat().st_mtime
    result = run("search", "--fast", "syntetisk")[0]
    assert result["preview"] == rows[0]["preview"]
    assert result["modifiedAt"] == rows[0]["modifiedAt"]

    # Simulate an index created before this version of the app.
    with sqlite3.connect(agent / "library.sqlite3") as index:
        index.execute("DROP TABLE file_previews")
        index.execute("DELETE FROM metadata WHERE key='file_preview_version'")
    assert run("library") == rows

    note.write_text("# Abborre\n\nNy sammanfattning.\n")
    os.utime(note, (1_780_000_000, 1_780_000_000))
    run("index")
    changed = run("library")[0]
    assert changed["preview"] == "Ny sammanfattning."
    assert changed["modifiedAt"] == 1_780_000_000
    note.unlink()
    run("index")
    assert len(run("library")) == 31

    other = root / "other"
    (other / ".obsidian").mkdir(parents=True)
    (other / "other.md").write_text("# Annat bibliotek\n\nAnnat innehåll.\n")
    assert [hit["preview"] for hit in run("library", environment=dict(env, BIGBRAIN_VAULT=str(other)))] == [
        "Annat innehåll."
    ]
    assert len(run("library")) == 31

print("PASS: library browse, previews, cache migration and vault isolation")
