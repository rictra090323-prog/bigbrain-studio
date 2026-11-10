---
name: small-change-review
description: Review a code change for unnecessary scope and identify the smallest implementation that preserves the required behavior.
---

# Small change review

Begin with the behavior the user needs and trace its normal entry points. Check whether existing interfaces and data paths can deliver it. Flag newly introduced dependencies, abstractions, persistence or permissions only when removing them leaves the intended behavior intact.

Identify behavior that must survive the smaller implementation, including existing data and failure handling. Verify the normal path and the concrete regression the proposed change could cause. Give an actionable finding with a file and a tighter change, or report what was checked.

Inspired by [Ponytail](https://github.com/DietrichGebert/ponytail).
