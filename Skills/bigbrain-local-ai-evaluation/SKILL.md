---
name: bigbrain-local-ai-evaluation
description: Evaluate BigBrain's on-device tagging, candidate retrieval, and note linking with and without Apple Intelligence.
---

# Evaluate BigBrain's on-device AI

Build a small labelled set of fictional notes and source passages. Include short notes, similar project names, ambiguous cases, and Swedish, English and mixed-language examples. Allow multiple acceptable answers and include an explicit abstention case.

- Compare text search and simple rules with the same candidate list augmented by the on-device model. Report candidate recall separately from whether the model chose the right candidate and cited the right passage.
- Record model, OS version, language, availability and latency. Separate runtime failures from model abstentions. If a standalone harness cannot reach the model service, run the same fixtures in a signed Mac test app and report the environments separately.
- Measure raw model choices and post-validation results separately. Validate the target ID, access and exact excerpt. Then check whether that excerpt supports this link. An exact quote from the wrong project can still produce a false match. Decide how to weigh false links against missed suggestions before inspecting results.
- Save cases, outcomes and limitations in the project note. Retain the comparison set for the next model or OS version.

[Apple on on-device model availability](https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel)
