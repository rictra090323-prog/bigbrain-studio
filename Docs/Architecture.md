# BigBrain architecture and credits

BigBrain is a local knowledge library for Mac. Atlas shows sources, notes and skills in a three-dimensional graph. Solid lines are document links. Dashed lines represent associations strengthened when two nodes are opened within ten minutes. Older observations decay with a half-life of 30 days. A search activates matching nodes and propagates a decreasing signal up to two steps. Markdown holds the library content. A separate local database holds weights and indexes.

## Use the app

- **Atlas** opens the graph. Drag to rotate it and select a node to inspect its nearest connections. The inspector list supports keyboard navigation and VoiceOver.
- **⌘N** opens the editor for a note or source. Agent proposals pass through the review queue and a check against the current file revision.
- **⌘K** opens search or the editor's source panel. The Idea Lab compares approaches and proposes a small experiment. The challenge workflow tests a conclusion against counterarguments.
- **Writing Coach** stores approved rules separately for Swedish and English. The English editing workflow has its own source-based checklist.
- **Settings** can pause association learning and import Markdown. BigBrain copies imported files and edits the copy in its own library.

## Local developer build

Run `bash build.sh "/path/to/BigBrain.app"` on Mac. The developer build can use an authenticated Codex CLI, QMD and Defuddle. Codex receives the question and selected excerpts when you use it. Background analysis has a separate setting. The Codex bridge registers skills in your local Codex folder and uses the library under `~/Documents/Codex/BigBrain Agent Data/Bibliotek` by default.

For isolated tests, run `python3 Tests/smoke.py '/path/to/BigBrain.app/Contents/Resources/bigbrain'` and the same command with `Tests/network_smoke.py`.

[Sandboxed Studio build](../Distribution/README.md)

## Methods and credits

- [Anthropic frontend design](https://github.com/anthropics/skills/tree/main/skills/frontend-design) and [canvas design](https://github.com/anthropics/skills/tree/main/skills/canvas-design) informed the composition, visual direction and typographic hierarchy.
- [X3 Design Skills](https://github.com/x3allamerican/design-skills) informed editorial design and identity. [Impeccable](https://github.com/pbakaus/impeccable) and [UI/UX Pro Max](https://github.com/nextlevelbuilder/ui-ux-pro-max-skill) informed visual and SwiftUI review.
- [Ponytail](https://github.com/DietrichGebert/ponytail), [i-have-adhd](https://github.com/hackersatyamrastogi/i-have-adhd) and [Humanizer](https://github.com/blader/humanizer) informed scoped code review, Idea Lab and the English editing checklist.
- [OWASP](https://github.com/OWASP/DevSecOpsGuideline/blob/master/current-version/2-Process/2-2-Develop/2-2-5-AI-Agent-and-MCP-Security.md), [Cloudflare](https://github.com/cloudflare/security-audit-skill) and [Trail of Bits](https://github.com/trailofbits/skills) informed agent trust boundary reviews.
- The bundled skills from [Kepano](https://github.com/kepano/obsidian-skills/tree/3ccff5338ea700537839b21900aa5358a0402c98) and [Superpowers](https://github.com/obra/superpowers/tree/22f0b463e7a5e579904dd6211a520321035526f7) retain their licenses.
