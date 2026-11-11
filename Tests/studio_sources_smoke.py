"""Exercise exact citations, frozen source versions and author-labelled history."""
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile

bridge = Path(sys.argv[1]).resolve()

with tempfile.TemporaryDirectory(prefix="bigbrain-citations-") as directory:
    root = Path(directory).resolve()
    vault = root / "library"
    (vault / ".obsidian").mkdir(parents=True)
    (vault / "Rapporter").mkdir()
    (vault / "Källor").mkdir()
    doc = vault / "Rapporter/Kalibrering.md"
    doc.write_text("# Kalibrering\n\nDokumentets första version.\n")
    source = vault / "Källor/Vägning åäö.md"
    excerpt = "Provet 🍓 vägdes två gånger efter kalibrering."
    original_source = f"# Vägning åäö\n\nInledning med 🍓.\n\n{excerpt}\n"
    source.write_text(original_source)
    env = dict(os.environ, BIGBRAIN_VAULT=str(vault), BIGBRAIN_AGENT_HOME=str(root / "agent"),
               CODEX_HOME=str(root / "codex"))

    def run(*args, input="", fail=False, environment=env):
        if not isinstance(input, str):
            input = json.dumps(input)
        result = subprocess.run([str(bridge), *args], input=input, text=True, capture_output=True,
                                env=environment, timeout=30)
        assert (result.returncode != 0) == fail, (args, result.stdout, result.stderr)
        return json.loads(result.stdout)

    document = "Rapporter/Kalibrering.md"
    target = "Källor/Vägning åäö.md"
    expected = "--expected-file=" + str(doc)

    def command(name, *args, **options):
        return run(name, expected, "--", document, *args, **options)

    results = command("source-search", "kalibrering")
    assert results and results[0]["path"] == target
    assert all(result["path"] != document and result["kind"] != "skill" for result in results)
    preview = command("source-preview", target, str(source), "vägdes kalibrering")
    passage = preview["passages"][0]
    assert passage["text"] == excerpt
    assert original_source[passage["start"]:passage["start"] + passage["length"]] == excerpt
    cite_args = (target, str(source), preview["revision"], str(passage["start"]), str(passage["length"]))
    command("source-cite", target, str(doc), *cite_args[2:], fail=True)
    command("source-cite", *cite_args[:-1], "999999", fail=True)
    link = command("source-cite", *cite_args)["markdown"]
    assert link == command("source-cite", *cite_args)["markdown"]
    match = re.fullmatch(r'\[Vägning åäö\]\(<([^>]+)> "BigBrain:([a-f0-9]+):([0-9]+):([0-9]+)"\)', link)
    assert match is not None

    source.write_text("# Vägning åäö\n\nEtt ändrat källstycke.\n")
    command("source-cite", *cite_args, fail=True)
    archive = command("source-version", *match.groups())
    assert archive["excerpt"] == excerpt and archive["body"] == original_source
    command("source-version", "../../outside.md", *match.groups()[1:], fail=True)

    before = run("note", document)
    saved = command("save-note", before["revision"], "-", input=before["body"] + "\nResultat: " + link + ".\n")
    assert "Resultat: " + link in saved["body"]
    events = command("note-history")
    assert len(events) == 1 and events[0]["author"] == "writer"
    event = command("history-entry", str(events[0]["id"]))
    assert event["body"] == saved["body"] and event["before"] == before["body"]
    assert "+Resultat:" in event["diff"]
    graph = run("atlas", "--focus=note:" + document)
    assert any({edge["a"], edge["b"]} == {"note:" + document, "note:" + target}
               and edge["kind"] == "explicit" for edge in graph["edges"])

    prepared = run("local-prompt", input={"mode": "lint", "query": "Kalibrering"})
    agent = run("local-finish", input={"state": prepared["state"], "reply": {
        "answer": "Ett syntetiskt granskningsförslag.", "path": document,
        "replacement": saved["body"] + "\nGodkänd formulering.\n", "reason": "Förtydliga slutsatsen."}})
    assert agent["proposal"] and len(command("note-history")) == 1
    run("apply", agent["proposal"])
    run("apply", agent["proposal"])
    events = command("note-history")
    assert [entry["author"] for entry in events] == ["agent", "writer"]
    assert command("history-entry", str(events[0]["id"]))["before"] == saved["body"]

    other = root / "another-library"
    (other / ".obsidian").mkdir(parents=True)
    (other / "Rapporter").mkdir()
    other_file = other / document
    other_file.write_text("# Kalibrering i ett annat bibliotek\n")
    other_env = dict(env, BIGBRAIN_VAULT=str(other))
    run("source-version", "--expected-file=" + str(other_file), "--", document, *match.groups(),
        environment=other_env, fail=True)
    assert run("note-history", "--expected-file=" + str(other_file), "--", document, environment=other_env) == []

print("PASS: exact Unicode excerpt, stale source rejection, frozen citation, Atlas edge, author history and vault isolation")
