---
name: bigbrain-local-ai-evaluation
description: Evaluate BigBrain's on-device tagging, candidate retrieval, and note linking with and without Apple Intelligence.
---

# Utvärdera BigBrains lokala AI

Bygg ett litet facit med fiktiva anteckningar och källstycken. Inkludera korta anteckningar, liknande projektnamn, otydliga fall och svenska, engelska samt blandat språk. Facit får ha flera godtagbara svar och ett uttryckligt osäkert fall.

- Jämför textbaserad sökning och enkla regler med samma kandidatlista plus den lokala modellen. Rapportera om rätt kandidat fanns i listan separat från om modellen valde rätt och angav rätt källstycke.
- Registrera modell, systemversion, språk, tillgänglighet och svarstid. Skilj körfel från modellens avstående. Om ett fristående prov inte kan nå modellservicen, kör samma syntetiska material i en signerad Mac-testapp och redovisa miljöerna separat.
- Mät modellens råa val och resultatet efter validering separat. Kontrollera valt ID, behörighet och att utdraget finns i källan. Kontrollera sedan att utdraget stödjer just kopplingen. Ett ordagrant utdrag om fel projekt kan fortfarande ge en felkoppling. Bestäm hur felkopplingar vägs mot missade förslag innan du öppnar resultatet.
- Spara exempelfall, utfall och begränsningar i BigBrains projektanteckning. Behåll jämförelsefallet för nästa modell- eller systemversion.

[Apple om lokal modell och tillgänglighet](https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel)
