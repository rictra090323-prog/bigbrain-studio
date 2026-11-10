"""Check the native library migration, local learning and boundaries."""
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

bridge = Path(sys.argv[1]).resolve()
spec = importlib.util.spec_from_file_location("public_source", bridge.parent / "public_source.py")
source = importlib.util.module_from_spec(spec)
spec.loader.exec_module(source)
for url in ("http://127.0.0.1", "http://2130706433", "http://169.254.169.254",
            "http://[::1]", "https://user@example.org", "file:///tmp/foo"):
    try:
        source.public_target(url)
        raise AssertionError(f"Unsafe source accepted: {url}")
    except ValueError:
        pass

with tempfile.TemporaryDirectory(prefix="bigbrain-native-test-") as tmp:
    root = Path(tmp)
    vault = root / "legacy"
    (vault / ".obsidian").mkdir(parents=True)
    (vault / "notes").mkdir()
    (vault / "notes/A.md").write_text("# Alpha\n\n[[Beta]]\n")
    (vault / "notes/Beta.md").write_text("# Beta\n\n[Gamma](Gamma.md)\n")
    (vault / "notes/Gamma.md").write_text("# Gamma\n\nExternal [resource](https://example.org/source.md).\n")
    (vault / "notes/symbolic.md").symlink_to(vault / "notes/A.md")
    (vault / "notes/figure.png").write_bytes(b"asset bytes")
    home = root / "engine"
    env = dict(os.environ, BIGBRAIN_AGENT_HOME=str(home), BIGBRAIN_VAULT=str(vault), CODEX_HOME=str(root / "codex"))
    def call(*args, payload=None, fail=False):
        result = subprocess.run([str(bridge), *args], env=env, text=True, input=payload,
                                capture_output=True, timeout=35)
        assert (result.returncode != 0) == fail, (args, result.stdout, result.stderr)
        return json.loads(result.stdout)

    base = call("note", "notes/Gamma.md")["revision"]
    staged = call("propose", "notes/Gamma.md", base, "fixture", "-", payload="# Gamma\n\nA revised fact.\n")
    imported = call("adopt", "--from=" + str(vault))
    del env["BIGBRAIN_VAULT"]
    library = Path(imported["library"])
    assert library != vault and (library / ".bigbrain-library.json").is_file()
    assert not (library / ".obsidian").exists() and not (library / "notes/symbolic.md").exists()
    assert (library / "notes/figure.png").read_bytes() == b"asset bytes"
    assert call("dashboard")["config"]["native"]
    assert call("proposal", staged["id"])["status"] == "pending"
    assert call("search", "Alpha", "--fast")[0]["path"] == "notes/A.md"
    graph = call("atlas", "--focus=note:notes/A.md")
    signals = {node["path"]: node["signal"] for node in graph["nodes"]}
    assert signals["notes/A.md"] > signals["notes/Beta.md"] > signals["notes/Gamma.md"] > 0
    assert len({node["z"] for node in graph["nodes"]}) >= 2
    edges = [edge for edge in graph["edges"] if edge["kind"] == "explicit"]
    assert {(edge["a"], edge["b"]) for edge in edges} >= {("note:notes/A.md", "note:notes/Beta.md"), ("note:notes/Beta.md", "note:notes/Gamma.md")}

    a, b = "note:notes/A.md", "note:notes/Gamma.md"
    recent = call("atlas", "--notes-only", "--recent=" + b, "--recent=note:deleted.md",
                  "--recent=skill:writing", "--recent=" + a, "--recent=" + b)
    assert [hit["id"] for hit in recent["recent"]] == [b, a]
    assert all(node["kind"] != "skill" for node in recent["nodes"])
    first = call("activate", a, b)
    second = call("activate", b, a)
    assert 0 < first["weight"] < second["weight"] < 1
    graph = call("atlas", "--focus=" + a)
    assert any(edge["kind"] == "learned" and edge["count"] == 2 for edge in graph["edges"])
    assert not call("activate", a, "note:nonexistent.md")["learned"]
    call("configure", payload='{"learning":false}')
    assert not call("activate", a, b)["learned"]

    created = call("capture", "Nytt", "Ett påstående.", "--note")
    assert created["path"].startswith("Anteckningar/")
    edited = call("save-note", created["path"], created["revision"], "-", payload="# Nytt\n\nNy text.")
    assert "Ny text." in edited["body"]
    call("apply", staged["id"])
    assert "A revised fact." in (library / "notes/Gamma.md").read_text()
    assert "A revised fact." not in (vault / "notes/Gamma.md").read_text()

    related = call("capture", "Nytt [exempel]", "Ny text om kursplanen.", "--note")
    hits = call("related", edited["path"])
    assert any(hit["path"] == related["path"] for hit in hits)
    assert all(hit["path"] != edited["path"] and hit["kind"] == "note" for hit in hits)
    proposal = call("propose-link", edited["path"], edited["revision"], related["path"])
    assert proposal["status"] == "pending" and proposal["source"] == related["path"]
    edge = ("note:" + edited["path"], "note:" + related["path"])
    def graph_edges():
        return {(item["a"], item["b"]) for item in call("atlas", "--focus=" + edge[0])["edges"]
                if item["kind"] == "explicit"}
    assert edge not in graph_edges()
    call("apply", proposal["id"])
    assert edge in graph_edges()

    # A generated link must resolve relative to the source, even if another folder shadows the target.
    nested = library / "notes/notes"
    nested.mkdir()
    (nested / "Beta.md").write_text("# Shadow Beta\n")
    source = call("note", "notes/Gamma.md")
    link = call("propose-link", source["path"], source["revision"], "notes/Beta.md")
    call("apply", link["id"])
    graph = call("atlas", "--focus=note:notes/Gamma.md")
    outgoing = {row["b"] for row in graph["edges"] if row["kind"] == "explicit" and row["a"] == "note:notes/Gamma.md"}
    assert "note:notes/Beta.md" in outgoing and "note:notes/notes/Beta.md" not in outgoing

    source = call("note", "notes/A.md")
    link = call("propose-link", source["path"], source["revision"], "notes/Gamma.md")
    (library / "notes/Gamma.md").write_text("# Different source\n")
    assert call("proposal", link["id"])["conflict"]
    assert call("apply", link["id"], fail=True)["error"]
    assert call("note", source["path"])["revision"] == source["revision"]
    call("dismiss", link["id"])
    link = call("propose-link", source["path"], source["revision"], "notes/Gamma.md")
    (library / "notes/Gamma.md").unlink()
    assert call("proposal", link["id"])["link_conflict"]
    assert call("apply", link["id"], fail=True)["error"]
    assert call("note", source["path"])["revision"] == source["revision"]

    prepared = call("local-prompt", payload='{"mode":"explore","query":"Alpha"}')
    assert "Alpha" in prepared["content"]
    result = call("local-finish", payload=json.dumps({
        "state": prepared["state"], "reply": {"answer": "Bounded response.", "path": "notes/A.md", "replacement": "ignored"}
    }))
    assert result["answer"] == "Bounded response." and result["proposal"] is None
    print("PASS: source boundaries, native migration, editing, graph learning, local prompts and reviewed links")
