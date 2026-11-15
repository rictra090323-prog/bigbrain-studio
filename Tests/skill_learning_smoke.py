"""Exercise opt-in learning, review approval, replay and vault isolation."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

bridge = Path(sys.argv[1]).resolve()
with tempfile.TemporaryDirectory(prefix="bigbrain-skill-learning-") as directory:
    root = Path(directory).resolve()
    vault, other = root / "one", root / "two"
    for library in (vault, other):
        (library / ".obsidian").mkdir(parents=True)
    env = dict(os.environ, BIGBRAIN_VAULT=str(vault), BIGBRAIN_AGENT_HOME=str(root / "agent"),
               CODEX_HOME=str(root / "codex"))

    def run(*args, data=None, library=vault, fail=False):
        result = subprocess.run([str(bridge), *args], input=json.dumps(data), text=True, capture_output=True,
                                env=dict(env, BIGBRAIN_VAULT=str(library)), timeout=25)
        assert (result.returncode != 0) == fail, (args, result.stdout, result.stderr)
        return json.loads(result.stdout)

    def observe(task, learn=True):
        request = run("local-prompt", data={"mode": "explore", "query": task, "learnSkills": learn})
        run("local-finish", data={"state": request["state"], "reply": {"answer": "Compare two research routes."}})

    assert not run("skill-review-ready")["ready"]
    observe("Untracked workflow", learn=False)
    observe("Compare temperatures")
    observe("Compare temperatures")
    observe("Compare pressure")
    assert not run("skill-review-ready")["ready"]
    observe("Compare humidity")
    assert run("skill-review-ready")["ready"]
    assert not run("skill-review-ready", library=other)["ready"]
    prepared = run("local-prompt", data={"mode": "skill-review"})
    payload = {"state": prepared["state"], "reply": {
        "answer": "A repeatable comparison method.", "path": "../untrusted", "rule": "Comparing experiments.",
        "replacement": "## Method\n\nCompare two routes and check the same outcome.", "reason": "The workflows share a method."}}
    run("local-finish", data=payload, fail=True)
    payload["reply"]["path"] = "compare-experiment-routes"
    proposed = run("local-finish", data=payload)["proposal"]
    assert proposed
    assert not run("search", "--scope", "skills", "compare-experiment-routes")
    assert not run("skill-review-ready")["ready"]
    assert run("local-finish", data=payload)["proposal"] is None
    run("apply", proposed)
    hits = run("search", "--scope", "skills", "compare-experiment-routes")
    assert hits and hits[0]["kind"] == "skill"
    assert not run("search", "--scope", "skills", "compare-experiment-routes", library=other)

print("PASS: skill learning opt-in, distinct workflow count, safe path, review, replay and vault isolation")
