---
name: wiki-ingest
description: Integrate new sources, links, and notes into the local BigBrain Obsidian wiki with provenance and a reviewable change proposal.
---

# Integrate a source into BigBrain

Use the bridge described in the `bigbrain-agent` skill. Search by names and claims before proposing a new topic note. Read the most relevant current notes and the original source. Keep dated evidence, scope, disagreements, and open questions distinct. Cite the primary source at the affected claim, plus the local intake note as provenance. An excerpt, secondary summary, or inaccessible link supports a narrower claim.

Propose one focused Markdown change at a time. Prefer extending the existing topic page. Preserve human-authored text outside the specific change and keep the raw intake item. Use `propose` with the relative path, the revision returned by `note` (or `new` for a new page), the full replacement, and a short explanation. The review queue shows the diff and controls application. Re-read and regenerate if the source note changed.
