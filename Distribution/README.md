# BigBrain Studio Preview

The preview targets Apple silicon and macOS 26 or later. It uses a separate library in its macOS app container and bundles Python for search, file handling and graph calculations. Apple Intelligence is the default when the on-device model is available. Atlas, Markdown import, editing and search also work without a model. A custom model endpoint is optional.

## Reproduce the local build

Download the [pinned Python runtime](../Dependencies/README.md). The build verifies the archive checksum before extracting it.

```sh
bash Distribution/build-store-preview.sh /absolute/path/runtime.tar.gz '/absolute/path/BigBrain Studio Preview.app'
```

The preview uses App Sandbox. macOS file pickers grant access to the folders you select for import and the files you choose to export. Imported files are copied into the app container. The Python helper inherits the sandbox. The app has outbound network access for the optional custom model connection.

## Before distribution

Choose a final bundle ID and use Apple Developer Program membership and Mac App Store signing. Validate the signed build in App Store Connect. Test onboarding, import and model features on a clean Mac. Prepare the store description, screenshots, support link, privacy policy and App Privacy disclosure. The preview build uses a local test signature.

- [App Store Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)
- [App Sandbox](https://developer.apple.com/documentation/xcode/configuring-the-macos-app-sandbox)
- [Foundation Models](https://developer.apple.com/documentation/foundationmodels/generating-content-and-performing-tasks-with-foundation-models)

## Atlas brain model

Atlas uses [Innerscenes Brain](https://www.innerscene.com/tools/library/3d-parts/brain-10d8f88f), a CC0 model with sculpted folds. BigBrain stores a local mesh and uses it to position the graph's nodes on the brain.

To repack the original GLB, run `python3 Distribution/pack-atlas-brain.py brain.glb Sources/AtlasBrain.mesh`.
