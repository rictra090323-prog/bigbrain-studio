# BigBrain Studio Preview

Previewen är byggd för Apple Silicon och macOS 26 eller senare. Den har ett eget lokalt bibliotek i macOS appcontainer och en medföljande Python-runtime för sökning, filhantering och nätets beräkningar. Modellfunktioner använder Apple Intelligence på enheten när systemmodellen är tillgänglig. Atlas, Markdown-import, redigering och sökning fungerar också utan modellen.

## Reproducerbart lokalt bygge

Hämta [Astrals Python 3.12.16 för Apple Silicon](https://github.com/astral-sh/python-build-standalone/releases/download/20261026/cpython-3.12.16%2B20261026-aarch64-apple-darwin-install_only_stripped.tar.gz). Byggskriptet verifierar arkivets SHA-256 före uppackning.

```bash
./Distribution/build-store-preview.sh /absolut/sökväg/runtime.tar.gz '/absolut/sökväg/BigBrain Studio Preview.app'
```

Previewen använder App Sandbox. Systemets filväljare ger åtkomst till mappar som väljs för import och filer som väljs för export. Appen kopierar filer till sin container. Beräkningshjälparen har ärvd sandbox. Byggprofilen innehåller ingen nätverksrättighet och använder lokala texter och den lokala systemmodellen.

## Före distribution

Använd ett slutligt bundle-ID, medlemskap i Apple Developer Program och Mac App Store-signering i distributionsflödet. Validera den signerade distributionsartefakten i App Store Connect och prova onboarding, filimport och modellfunktioner på en ren Mac. Förbered också butikstext, skärmbilder, supportlänk, integritetspolicy och App Privacy-uppgifter. Den här profilen ger en lokalt testsignerad preview.

- [Apples granskningsregler](https://developer.apple.com/app-store/review/guidelines/)
- [App Sandbox](https://developer.apple.com/documentation/xcode/configuring-the-macos-app-sandbox)
- [Foundation Models](https://developer.apple.com/documentation/foundationmodels/generating-content-and-performing-tasks-with-foundation-models)
## Hjärnmodellen i Atlas

Hjärnvyn använder [Innerscenes Brain](https://www.innerscene.com/tools/library/3d-parts/brain-10d8f88f), en CC0-modell med skulpterade hjärnveck. Den lokala resursen innehåller modellens geometri och normaler. Kopplingar följer ytan och lyser upp närliggande veck.

För att packa om originalets GLB, kör `python3 Distribution/pack-atlas-brain.py brain.glb Sources/AtlasBrain.mesh`.
