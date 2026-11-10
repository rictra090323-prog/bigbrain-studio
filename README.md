# BigBrain Studio 2.3

Lokal anteckningsapp för Mac. Paketet innehåller källkod, syntetiska testfiler, funktionslista, produktplan och instruktioner för att hämta den officiella Python-runtime som behövs för att bygga lokalt.

## Öppna i Xcode

1. Packa upp zip-filen.
2. Hämta Python-arkivet enligt [Dependencies/README.md](Dependencies/README.md). Lägg filen i `Dependencies/` innan du bygger.
3. Öppna `BigBrain.xcodeproj`, välj **BigBrain Studio** och **My Mac** och kör med **⌘R**.
4. Prova **⌘N**, skriv ett par rader och spara med **⌘↩**. Anteckningen öppnas i biblioteket och kan även hittas i Atlas. **Transkribera → Välj ljudfil** kan provas med testfilen i `Tests/Fixtures/`.

Använd en Mac med Apple-chip, macOS 26 eller senare och Xcode med macOS 26 SDK eller nyare. Projektet använder lokal ad hoc-signering och ett eget app-ID, `local.bigbrain.studio.xcode`, som ger Xcode-bygget ett separat bibliotek.

Det här paketet är avsett för lokalt bygge. Xcode kör en byggfas som verifierar det hämtade Python-arkivets kontrollsumma, packar upp och signerar hjälpprocessen lokalt och bäddar in den i appen. Det ersätter det tidigare flödet som kopierade Python från en redan byggd preview. Om den skickade previewen stoppas när den öppnas, använd `BigBrain.xcodeproj` härifrån. En app för vanlig distribution behöver Developer ID-signering och attestering hos Apple. [Apple om Developer ID](https://developer.apple.com/developer-id/)

Projektfilen, schemat och byggfasen har kontrollerats separat. Terminalbygget har provats. Körning via Xcode behöver verifieras på en Mac med fullständigt Xcode.

## Prova Atlas och skrivläget

Skriv en sökfras under **Atlas** för att få upp en dropdown med träffar direkt under sökfältet. Klicka på en träff för att förhandsvisa anteckningen, eller tryck Retur eller **Sök** för att öppna Bibliotekets träffar. Till höger visas upp till tio senast öppnade anteckningar i det aktuella biblioteket. Innan du har öppnat någon visas ett urval ur orben. Välj **Tillbaka till listan** för att återvända.

Välj **Öppna anteckningen** i Atlas eller klicka på en träff i Biblioteket. **Skriv i helskärm** (⇧⌘F) öppnar samma redigerare över hela skärmen. **Avsluta skrivläge** återställer arbetsytan med samma anteckning. Format, spara och sökning efter samband finns i skrivläget.

Öppna en anteckning i Bibliotek och klicka i texten. I **Start** finns tre rubriknivåer, citat, fetstil, kursiv, punktlistor, numrerade listor och checklistor. Sätt markören i en checklisterad och använd knappen med en bock eller **⇧⌘↩**. Tryck **⌘F** för att söka i anteckningen och **⌘S** för att spara. Utkast lagras lokalt under arbetet.

I **Exportera** kan du välja **PDF**, **Word** eller **Markdown**. Exporten utgår från den öppna texten, inklusive osparade ändringar. PDF sidbryts till A4 och Word skapar en redigerbar `.docx`. Båda återger formaten som stöds av den formaterade skrivytan. Markdown bevarar den fullständiga källtexten.

Öppna fliken **Visa** och välj **Visa samband** efter att du markerat text eller placerat markören i ett stycke. Studio söker lokalt och visar ett utdrag och gemensamma sökord. **Koppla i Atlas** sparar anteckningen och länken tillsammans. **Ångra koppling** återställer anteckningen till texten precis före kopplingen. Exakta källutdrag och revisioner kontrolleras innan en koppling sparas.

## Prova iPhone-flödet

1. Välj schemat **BigBrain Capture** i samma Xcode-projekt och en iPhone som kör iOS 17 eller senare. För en fysisk telefon väljer du ditt utvecklarteam under **Signing & Capabilities**. Ändra app-ID om ditt team redan använder det. iPhone-målet använder Swift och behöver inget Python-arkiv.
2. Skriv en minnesanteckning och tryck **Spara på enheten**. På iOS 26 med stöd för lokal transkribering kan du också välja **Spela in röstanteckning**, stoppa inspelningen och granska texten före sparandet. Talmodellen kan behöva hämtas första gången.
3. Dela provanteckningen till din Mac via AirDrop. I **BigBrain Studio** väljer du **Arkiv → Importera från iPhone** och öppnar filen med ändelsen `.bbcapture`. För ett prov enbart på Mac, använd `Tests/Fixtures/Provanteckning.bbcapture`.
4. Importera samma fil igen och kontrollera att den befintliga anteckningen öppnas. Ändra texten på Mac och upprepa importen för att kontrollera att ändringen bevaras.

Mac-importen har provats i den signerade previewen. Swift-koden för fångst och kö har byggts med Macens SDK. Den nya inspelningen, språkstödet och överföringen behöver provas på fysisk iPhone. Överföringen i piloten sker via AirDrop och manuell import. [Apple om AirDrop](https://support.apple.com/guide/iphone/iphcd8b9f0af/ios)

## Källkod

| Fil | Ansvar |
| --- | --- |
| `Sources/BigBrain.swift` | SwiftUI, bibliotek, sök, import, editor och granskningskö. |
| `Sources/Atlas.swift` och `Sources/network.py` | Atlasvy, explicita länkar och samband som lärs när noder öppnas tillsammans. |
| `Sources/Distribution.swift` | Lokal hjälpprocess och Apple Intelligence. |
| `Sources/StudioExport.swift` | Export till PDF, Word och Markdown. |
| `Sources/SpeechTranscription.swift` | Lokal transkribering av vald fil eller mikrofoninspelning. |
| `Mobile/CaptureQueue.swift` och `Mobile/BigBrainCaptureApp.swift` | Textfångst, lokal kö och manuell filexport för iPhone. |
| `Sources/brain.py` och `Sources/word_import.py` | Markdown-bibliotek, SQLite/FTS, ändringsförslag och Word-konvertering. |

## Bygg och testa i Terminal

Fristående Studio-bygge efter att du har hämtat Python-arkivet enligt instruktionerna ovan:

```sh
./Distribution/build-store-preview.sh \
  "$PWD/Dependencies/python-3.12.16-arm64.tar.gz" \
  "$PWD/BigBrain Studio Build.app"
```

Utvecklarbygget används för de automatiska bryggtesterna. Det har även stöd för valfri Codex-integration.

```sh
./build.sh "$PWD/BigBrain Agent Test.app"
bridge="$PWD/BigBrain Agent Test.app/Contents/Resources/bigbrain"
for test in smoke network_smoke word_smoke vault_isolation_smoke; do
  python3 -B "Tests/$test.py" "$bridge"
done
python3 -B Tests/related_notes_eval.py "$bridge"
```

Prova Mac-editorns Markdown-konvertering och det lokala kopplingsflödet:

```sh
editor_test="$(mktemp -d)"
swiftc -swift-version 5 -parse-as-library -module-cache-path "$editor_test/modules" \
  Sources/StudioMarkdown.swift Tests/StudioTextSmoke.swift -o "$editor_test/studio"
"$editor_test/studio"
python3 -B Tests/studio_editor_smoke.py "$bridge"
```

För att bygga ett köprov och låta Mac-bryggan läsa filen som Swift faktiskt skrev:

```sh
capture_test="$(mktemp -d)"
swiftc -parse-as-library -module-cache-path "$capture_test/modules" \
  Mobile/CaptureQueue.swift Tests/CaptureQueueSmoke.swift -o "$capture_test/queue"
"$capture_test/queue" "$capture_test/prov.bbcapture"
python3 -B Tests/phone_capture_smoke.py "$bridge" "$capture_test/prov.bbcapture"
```

`Tests/LocalLinkEval.swift` kan byggas med `BIGBRAIN_EVAL_APP` och `Tests/Fixtures/trials.json` som appresurs. `Tests/ContextualCandidateEval.swift` använder `Tests/Fixtures/fixture.json` som appresurs. Båda använder syntetiskt material.

- [Funktioner och nästa steg](Funktioner%20och%20n%C3%A4sta%20steg.md)
- [Full produktplan och lärdomar](Docs/Produktplan.md)
- [Byggprofil och distribution](Distribution/README.md)
- [Bakgrund och källprojekt](Docs/README-k%C3%A4llprojekt.md)
