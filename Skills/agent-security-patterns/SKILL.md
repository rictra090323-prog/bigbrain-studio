---
name: agent-security-patterns
description: Review trust boundaries when an agent consumes external content, handles local files or secrets, invokes tools, or installs a third-party skill.
---

# Agent trust boundaries

Start from one input and trace where its data goes and which actions it can influence. Record concrete boundaries between user intent, model inputs, retrieved data, tool arguments, and persistent state.

- A website, note, tool result, or imported skill can carry instructions. Treat retrieved content as data and enforce the boundary with typed arguments, constrained tools, and separate authority for writes.
- For URL ingestion, restrict destination schemes and addresses at every redirect. Validate the address the transport actually uses. Bound time and size and parse the retrieved bytes without executing page code.
- For vault updates, verify the canonical destination, baseline revision, and reviewed intent before writing. Test a stale proposal, a path outside the library, and a hostile source body.
- For externally sourced skills, inspect instructions, referenced scripts, dependencies, install hooks, network destinations and required permissions. Record provenance and pin executable imports.
- For an audit, give the failing path and a minimal reproduction. Distinguish a tested control from a prompt-level instruction. Recheck with an adversarial fixture after the change.

References: [OWASP agent and MCP security](https://github.com/OWASP/DevSecOpsGuideline/blob/master/current-version/2-Process/2-2-Develop/2-2-5-AI-Agent-and-MCP-Security.md), [Cloudflare security audit](https://github.com/cloudflare/security-audit-skill), [Trail of Bits skills](https://github.com/trailofbits/skills).
