# BigBrain Studio

BigBrain Studio is a local-first macOS writing and personal knowledge app. Capture an idea in a rich-text editor, cite an exact version of a source from your Markdown library, and explore connections in a three-dimensional knowledge graph.

## What you can do

- **Write and capture in the same editor.** Use headings, lists, checklists, tables and links from the first draft. Save to your library or keep a source in the inbox. Export the open draft to PDF, Word or Markdown.
- **Explore your library with Atlas.** Rotate a sphere or brain-shaped graph, find documents by text, and inspect explicit document links and suggestions. Other workspaces use a muted, frosted view of the graph as a backdrop.
- **Cite a source and verify it later.** Search local notes alongside the editor, insert an exact excerpt, and reopen the frozen source version. The app records changes to saved notes and reviewed proposals.
- **Choose your model.** Use Apple Intelligence in Studio, the optional Codex workflow in Agent, or an OpenAI-compatible model server with an optional API key.
- **Build reusable skills.** Enable skill learning to periodically review recent, distinct research workflows. Review proposed skills before they become searchable in the active library.
- **Import existing work.** Bring in Markdown folders, Word files or notes captured by the separate iPhone pilot.

## Run on your Mac

You need Apple silicon and macOS 26 or later for the full Studio experience. The terminal build uses Swift and the macOS 26 SDK or later. Use full Xcode to run the Xcode project or the iPhone target.

```sh
git clone https://github.com/rictra090323-prog/bigbrain-studio.git
cd bigbrain-studio
bash build.sh "$PWD/BigBrain Agent.app"
open "$PWD/BigBrain Agent.app"
```

For the sandboxed Studio build, download the pinned [Python runtime](Dependencies/README.md), open `BigBrain.xcodeproj`, choose **BigBrain Studio** and **My Mac**, then press **⌘R**. The build checks the runtime checksum and signs the helper locally. You can also build Studio in Terminal.

```sh
bash Distribution/build-store-preview.sh \
  "$PWD/Dependencies/python-3.12.16-arm64.tar.gz" \
  "$PWD/BigBrain Studio.app"
```

Press **⌘N** to open the editor for a new note. Press **⌘S** or **⌘↩** to save it. **⌘K** opens the source panel while you write. The app currently uses Swedish labels in parts of the interface.

## Bring your own model

Open **Settings (Inställningar) → Model provider**, enter a base URL and model ID, and save. The **Test saved provider** button sends a short test message. For ordinary agent actions BigBrain sends your question and the relevant excerpts selected for that task to the configured endpoint. The optional key stays in macOS Keychain. HTTPS is required off localhost.

| Provider | Base URL | Model ID |
| --- | --- | --- |
| Hugging Face Inference Providers | `https://router.huggingface.co/v1` | An available chat model ID, with a Hugging Face token |
| OpenClaw | `http://127.0.0.1:18789/v1` | `openclaw/default` or `openclaw/<agentId>`, with the gateway's authentication if configured |
| Local server | Your local `/v1` base URL | An ID exposed by your server |

OpenClaw must have its [Chat Completions endpoint](https://docs.openclaw.ai/gateway/openai-http-api) enabled. Requests run as the selected gateway agent. Hugging Face explains [model routing and token setup](https://huggingface.co/docs/inference-providers/index). This integration uses text chat completions.

### Skill learning

Turn on **Learn skills from recent workflows** in the model panel. After three distinct completed research tasks, BigBrain can review short records with the selected model while the app is open. If it identifies a reusable procedure, it drafts a `SKILL.md` in the review queue. Approval adds the skill to the active library. The workflow records, proposals and generated skills stay out of the source repository. When the selected model uses an external endpoint, that endpoint receives the review input. Hermes Agent's [background skill review](https://hermes-agent.nousresearch.com/docs/user-guide/features/skills) inspired this workflow.

## iPhone capture pilot

Select the **BigBrain Capture** scheme on iOS 17 or later. A physical device also needs your development team in Xcode. Save a note, share the `.bbcapture` file by AirDrop and use **File (Arkiv) → Import from iPhone** on the Mac. On supported iOS 26 devices, you can also try recording and transcribing a voice note. Use `Tests/Fixtures/Provanteckning.bbcapture` to test the Mac import without an iPhone. Importing the same capture again retains edits made on the Mac.

## Verify changes

```sh
bash build.sh "$PWD/BigBrain Agent Test.app"
bridge="$PWD/BigBrain Agent Test.app/Contents/Resources/bigbrain"
for test in smoke network_smoke word_smoke vault_isolation_smoke studio_sources_smoke library_smoke studio_editor_smoke skill_learning_smoke; do
  python3 -B "Tests/$test.py" "$bridge"
done
python3 -B Tests/phone_capture_smoke.py "$bridge" Tests/Fixtures/Provanteckning.bbcapture
```

The Swift app lives in `Sources/`. The Python bridge handles the Markdown library, SQLite search, proposals and frozen citations. The iPhone pilot lives in `Mobile/`. Use a test branch for changes and open a pull request into `main`.
