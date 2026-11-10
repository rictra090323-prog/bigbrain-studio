"""Exercise the packaged bridge against a disposable vault and Codex home."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

bridge = Path(sys.argv[1]).resolve()

with tempfile.TemporaryDirectory(prefix="bigbrain-tests-") as tmp:
    root = Path(tmp)
    vault = root / "vault"
    (vault / ".obsidian").mkdir(parents=True)
    (vault / "Notes").mkdir()
    target = vault / "Notes/Risk.md"
    target.write_text("# Riskmodell\n\nLook-ahead bias affects simulated execution. [[Missing]]\n")
    agent_home = root / "agent"
    codex = root / "codex"
    codex.mkdir()
    (codex / "AGENTS.md").write_text("# Existing instructions\n\nKeep this text.\n")
    env = dict(os.environ, BIGBRAIN_AGENT_HOME=str(agent_home), BIGBRAIN_VAULT=str(vault), CODEX_HOME=str(codex))

    def run(*args, data=None, fail=False):
        if data is not None and not isinstance(data, str):
            data = json.dumps(data)
        p = subprocess.run([str(bridge), *args], input=data, text=True, capture_output=True, env=env, timeout=30)
        assert (p.returncode != 0) == fail, (args, p.stdout, p.stderr)
        return json.loads(p.stdout)

    stats = run("dashboard")
    assert stats["notes"] == 1
    assert stats["skills"] >= 9
    assert run("search", "framtidsläckage", "--fast")[0]["path"] == "Notes/Risk.md"
    assert run("search", "formal Swedish English", "--scope", "skills", "--fast")[0]["title"] == "bilingual-writing-coach"
    full = run("context", "riskmodell", "--fast")
    assert full["text"].startswith("[1]")
    assert run("context", "riskmodell", "--fast", "--compact") == {"text": full["text"]}
    full_skills = run("search", "writing", "--scope", "skills", "--fast", "--limit", "3")
    compact_skills = run("search", "writing", "--scope", "skills", "--fast", "--compact", "--limit", "3")
    assert [hit["file"] for hit in compact_skills] == [hit["file"] for hit in full_skills]
    assert run("lint")["broken"] == [{"path": "Notes/Risk.md", "link": "Missing"}]

    existing_skill = codex / "skills/wiki-lint/SKILL.md"
    existing_skill.parent.mkdir(parents=True)
    existing_skill.write_text("Custom wiki-lint skill\n")
    instructions = (codex / "AGENTS.md").read_text()
    assert "En egen version av wiki-lint" in run("install", fail=True)["error"]
    assert existing_skill.read_text() == "Custom wiki-lint skill\n"
    assert list(existing_skill.parent.parent.iterdir()) == [existing_skill.parent]
    assert (codex / "AGENTS.md").read_text() == instructions
    existing_skill.write_text((bridge.parent / "Skills/wiki-lint/SKILL.md").read_text())

    run("install")
    run("install")
    assert (codex / "AGENTS.md").read_text().count("BigBrain Agent start") == 1
    assert "Keep this text." in (codex / "AGENTS.md").read_text()
    assert (codex / "skills/bigbrain-agent/bridge-path.txt").read_text().strip() == str(bridge)

    source = run("capture", "Calibration note", "-", "--source", "https://example.org/report", data="A synthetic test result.")
    assert "A synthetic test result." in (vault / source["path"]).read_text()
    assert run("search", "calibration", "--scope", "inbox")[0]["path"] == source["path"]
    revision = run("note", "Notes/Risk.md")["revision"]
    change = run("propose", "Notes/Risk.md", revision, "Test approval", "-", data="# Riskmodell\n\nNew finding.\n")
    assert "+New finding." in change["diff"]
    assert "Look-ahead bias" in target.read_text()
    target.write_text("# Riskmodell\n\nEdit from Obsidian.\n")
    assert run("proposal", change["id"])["conflict"] is True
    assert "ändrats" in run("apply", change["id"], fail=True)["error"]
    assert "Edit from Obsidian." in target.read_text()
    run("dismiss", change["id"])
    revision = run("note", "Notes/Risk.md")["revision"]
    change = run("propose", "Notes/Risk.md", revision, "Test approval", "-", data="# Riskmodell\n\nNew finding.\n")
    assert run("apply", change["id"])["status"] == "accepted"
    assert run("apply", change["id"])["status"] == "accepted"
    assert "New finding." in target.read_text()
    assert run("search", "New finding", "--fast")[0]["path"] == "Notes/Risk.md"
    assert run("note", "../private.md", fail=True)["error"]

    learn = {"language": "sv", "genre": "rapport", "before": "I syfte att", "after": "För att", "rule": "Skriv För att där syftet kan sägas direkt."}
    run("learn", data=learn)
    run("learn", data=learn)
    saved = run("style", "sv")["examples"]
    assert len(saved) == 1 and saved[0]["after"] == "För att"
    assert run("style", "en")["examples"] == []
    run("unlearn", saved[0]["id"])
    assert run("style", "sv")["examples"] == []

    fake = root / "fake-codex"
    fake.write_text("""#!/usr/bin/python3
import json, pathlib, sys
payload=json.loads(sys.stdin.read().split("BEGIN_BIGBRAIN_INPUT\\n", 1)[1])
raw=payload["additional_material"]
assert "Calibration note" in raw["source_text"]
path=pathlib.Path(sys.argv[sys.argv.index("-o")+1])
path.write_text(json.dumps(dict(answer="New source [1]", path="BigBrain Agent/Wiki/Calibration.md",
replacement="# Calibration\\n\\nSynthetic finding.\\n", reason="New source", rule="")))
""")
    fake.chmod(0o755)
    run("configure", data={"codex": str(fake), "auto": True})
    new = run("capture", "Calibration note new", "A synthetic follow-up.")
    result = run("auto")
    assert result["status"] == "complete" and result["proposal"]
    assert not (vault / "BigBrain Agent/Wiki/Calibration.md").exists()
    run("apply", result["proposal"])
    assert (vault / "BigBrain Agent/Wiki/Calibration.md").exists()
    print("PASS: retrieval, skill discovery, source intake, lint, proposal conflict and apply, language isolation, install, background proposal")
