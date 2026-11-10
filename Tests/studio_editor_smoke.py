"""Exercise in-place saving and reviewed links with disposable local notes."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

bridge = Path(sys.argv[1]).resolve()

with tempfile.TemporaryDirectory(prefix="bigbrain-studio-") as tmp:
    root = Path(tmp).resolve()
    vault = root / "vault"
    (vault / ".obsidian").mkdir(parents=True)
    env = dict(os.environ, BIGBRAIN_AGENT_HOME=str(root / "agent"), BIGBRAIN_VAULT=str(vault),
               CODEX_HOME=str(root / "codex"))

    def run(*args, text="", fail=False):
        result = subprocess.run([str(bridge), *args], input=text.encode(), capture_output=True, env=env, timeout=30)
        assert (result.returncode != 0) == fail, (args, result.stdout, result.stderr)
        return json.loads(result.stdout)

    draft = "# Kursanteckning\n\nNy text om institutionernas självständighet.\n\n**Viktigt**.\n"
    original = run("capture", "--note", "Kursanteckning", "-",
                   text="Sparad version.\n\n[[En befintlig länk]]")
    target = run("capture", "--note", "Religion och samhälle", "-",
                 text="Institutionernas självständighet förändrar religionens roll i samhället.")
    other = run("capture", "--note", "Teknik", "-", text="Fortsättning från föregående dag.")
    original_args = (original["path"], original["revision"])
    run("save-note", "--expected-file=/wrong/library.md", "--", *original_args, "-", text=draft, fail=True)
    assert run("suggest-link", original["path"], text="kvicksilvermätningar") is None
    match = run("suggest-link", original["path"], text="institutionernas självständighet")
    assert match["hit"]["path"] == target["path"] and match["excerpt"] in target["body"]
    assert run("note", original["path"]) == original
    target = run("save-note", target["path"], target["revision"], "-",
                 text=target["body"] + "\nEtt nytt källstycke.")
    prefix = ("confirm-link", "--expected-file=" + original["file"], "--", *original_args, target["path"])
    run(*prefix, match["revision"], text=draft, fail=True)
    assert run("note", original["path"]) == original
    match = run("suggest-link", original["path"], text="institutionernas självständighet")
    linked = run(*prefix, match["revision"], text=draft)
    assert draft.strip() in linked["body"] and "## Relaterade anteckningar" in linked["body"]
    graph = run("atlas", "--focus=note:" + original["path"])
    ids = {"note:" + original["path"], "note:" + target["path"]}
    assert any({edge["a"], edge["b"]} == ids and edge["kind"] == "explicit" for edge in graph["edges"]), graph
    run(*prefix, match["revision"], text=draft, fail=True)
    restored = run("save-note", "--expected-file=" + original["file"], "--", original["path"], linked["revision"], "-", text=draft)
    assert restored["body"] == draft
    graph = run("atlas", "--focus=note:" + original["path"])
    assert not any({edge["a"], edge["b"]} == ids for edge in graph["edges"]), graph
    assert run("note", other["path"]) == other
    assert run("save-note", "--expected-file=" + original["file"], "--", original["path"], restored["revision"], "-",
               text=draft) == restored

print("PASS: draft, source excerpt, stale-source rejection, confirmed Atlas edge and undo")
