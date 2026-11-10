---
name: backtest-audit
description: Audit backtest validity and paper-trading assumptions, including look-ahead, costs, strategy selection and test-period contamination. Use when asked to assess whether a quantitative result holds.
---

# Audit a backtest

Identify the exact run, data snapshot, strategy revision, configuration and intended decision. Read applicable research from BigBrain and use existing diagnostic commands where possible.

1. Trace data availability at each decision, signal time, order time and modeled fill. If possible, compare pre-cutoff signals with a run on data truncated at the cutoff.
2. Verify the traded universe as of each date, missing data, adjustments and survivorship. Reconcile trade samples against raw inputs.
3. Check spread, fees, slippage, latency and liquidity assumptions against the actual instrument and execution path. Report sensitivity to plausible costs.
4. Separate fitting, model selection and untouched evaluation. List tried variants and identify any decisions informed by reported test results. Report results by period, sample sizes and uncertainty alongside aggregates.
5. Separate implementation correctness, empirical evidence and readiness for paper testing. Classify each item as verified, failed, or unchecked. Cite run artifacts and actual verification output.

Keep audit findings separate from live settings and orders. Cite [Bailey et al. on backtest overfitting](https://papers.ssrn.com/sol3/papers.cfm?abstract_id=2308659) when relevant.
