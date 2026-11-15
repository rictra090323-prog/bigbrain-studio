---
name: bigbrain-privacy-review
description: Review BigBrain data flows for Word import, notes and derived memory, deletion, external model routing, and provider connections.
---

# Review privacy in BigBrain

Trace one note from file selection or user input through storage, indexing, model inference, export and deletion. For each step record purpose, data, location, recipients, access and retention. Map caches, recovery, logs and derived associations separately.

- Verify the default local workflow offline with synthetic data. Check retries, model failures and imported links.
- Test deletion in the original file, index and derived records separately. Record how history, backups and previously transmitted data are retained or removed.
- For an external model, check what the user sees about the recipient and excerpts before transfer. Test how private items and revoked access are handled. An unsuccessful request should stay with the selected provider.
- Record what was tested, outstanding risks and ownership for new flows. Carry out a separate GDPR assessment for actual processing. A data protection impact assessment is required before processing likely to result in high risk.

[Swedish Authority for Privacy Protection on data protection by design](https://www.imy.se/verksamhet/dataskydd/det-har-galler-enligt-gdpr/inbyggt-dataskydd-och-dataskydd-som-standard/) · [GDPR Articles 25 and 35](https://eur-lex.europa.eu/legal-content/EN/TXT/?uri=CELEX%3A32016R0679)
