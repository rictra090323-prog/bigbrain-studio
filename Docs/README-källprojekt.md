# BigBrain Studio

BigBrain är ett lokalt kunskapsbibliotek för Mac. Atlasen visar källor, anteckningar och skills i tre djupplan. Solida linjer är dokumentlänkar. Streckade linjer är samband som förstärks när du öppnar två olika noder inom tio minuter. Äldre observationer avtar med en halveringstid på 30 dagar. En sökning aktiverar matchande noder och sprider en avtagande signal högst två steg. Anteckningarnas Markdown är bibliotekets innehåll. Vikter och index ligger i en separat lokal databas.

## Använd appen

- **Atlas** öppnar det tredimensionella nätet. Dra för att rotera, klicka på en nod och läs dess närmaste kopplingar. Inspektorns lista ger ett alternativ med tangentbord och VoiceOver.
- **⌘N** skapar en anteckning eller en källa. Anteckningar kan redigeras i biblioteket. Agentförslag går via granskning och en kontroll av den aktuella filrevisionen.
- **⌘K** öppnar bibliotekssökningen. **Idélabb** jämför olika vägar och föreslår ett litet test. **Motläs** prövar en slutsats mot starkare motargument.
- **Skrivcoach** sparar godkända redaktionsregler separat för svenska och engelska. Den engelska redigeringen har en egen källförankrad checklista.
- **Inställningar** kan pausa sambandsinlärning och importera Markdown. Ursprungliga filer kopieras. BigBrain använder den egna kopian för framtida ändringar.

## Lokalt utvecklarbygge

Kör `./build.sh /sökväg/till/BigBrain.app` på Mac. Det lokala bygget kan använda en inloggad Codex CLI, QMD och Defuddle. När du kör Codex får modellen frågan och utvalda utdrag. Bakgrundsanalysen är en egen inställning. Codex-bryggan registrerar skills i din lokala Codex-mapp och behåller eget bibliotek i `~/Documents/Codex/BigBrain Agent Data/Bibliotek`.

Kör `python3 Tests/smoke.py '/sökväg/till/BigBrain.app/Contents/Resources/bigbrain'` och motsvarande med `Tests/network_smoke.py` för isolerade tester.

## Fristående distributionsprofil

[Bygga App Store-preview](../Distribution/README.md)

## Inkorporerade metoder

- [Anthropic frontend design](https://github.com/anthropics/skills/tree/main/skills/frontend-design) och [canvas design](https://github.com/anthropics/skills/tree/main/skills/canvas-design) för en sammanhållen visuell idé, komposition och typografisk hierarki.
- [X3 Design Skills](https://github.com/x3allamerican/design-skills) som katalog för redaktionell form och identitet, [Impeccable](https://github.com/pbakaus/impeccable) för visuell kritik och [UI/UX Pro Max](https://github.com/nextlevelbuilder/ui-ux-pro-max-skill) för en SwiftUI-anpassad granskning.
- [Ponytail](https://github.com/DietrichGebert/ponytail) för avgränsad kodgranskning, [i-have-adhd](https://github.com/hackersatyamrastogi/i-have-adhd) för Idélabb och [Humanizer](https://github.com/blader/humanizer) för den engelska redigeringschecklistan.
- [OWASP](https://github.com/OWASP/DevSecOpsGuideline/blob/master/current-version/2-Process/2-2-Develop/2-2-5-AI-Agent-and-MCP-Security.md), [Cloudflare](https://github.com/cloudflare/security-audit-skill) och [Trail of Bits](https://github.com/trailofbits/skills) för granskning av agentgränser.
- Originalskills från [Kepano](https://github.com/kepano/obsidian-skills/tree/3ccff5338ea700537839b21900aa5358a0402c98) och [Superpowers](https://github.com/obra/superpowers/tree/22f0b463e7a5e579904dd6211a520321035526f7) innehåller sina licenser.
