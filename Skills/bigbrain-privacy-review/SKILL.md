---
name: bigbrain-privacy-review
description: Review BigBrain data flows for Word import, notes and derived memory, deletion, external model routing, and provider connections.
---

# Granska integriteten i BigBrain

Följ en anteckning från vald fil eller inmatning till lagring, index, modell, export och radering. Lista för varje steg syfte, uppgifter, plats, mottagare, åtkomst och lagringstid. Kartlägg cache, återställning, loggar och kopplingar separat.

- Verifiera det lokala standardflödet offline med syntetiska uppgifter. Kontrollera att begränsningen gäller även vid omförsök, modellfel och importerade länkar.
- Testa radering i original, index och härledda poster var för sig. Skilj funktionell radering från gallring av historik, säkerhetskopior och redan utlämnade uppgifter.
- För extern AI, testa att användaren ser mottagare och urval före överföring, att privata poster blockeras och att återkallad åtkomst fungerar. Kontrollera att ett misslyckat anrop stannar hos vald leverantör.
- Dokumentera vad som har testats, öppna risker och ansvar för nya flöden. Gör en separat GDPR-bedömning för faktisk behandling. Vid sannolik hög risk behöver konsekvensbedömningen göras före behandling.

[IMY om inbyggt dataskydd](https://www.imy.se/verksamhet/dataskydd/det-har-galler-enligt-gdpr/inbyggt-dataskydd-och-dataskydd-som-standard/) · [GDPR, artiklarna 25 och 35](https://eur-lex.europa.eu/legal-content/EN-SV/TXT/?uri=CELEX%3A32016R0679)
