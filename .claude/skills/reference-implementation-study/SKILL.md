---
name: reference-implementation-study
description: Drive a topic from survey findings through reference implementation, comparative evaluation, sensitivity analysis, finite-precision realization, and a final engineering recommendation. Use after a deep-research-survey has produced a completed survey with method inventory, math derivations, and SOTA assessment. Applicable to any DSP, wireless, algorithm, or systems-engineering domain.
---

# Reference Implementation Study

## Overview

Take the output of a completed deep-research-survey and turn it into working reference code, reproducible comparative experiments, and an actionable engineering recommendation.

Prefer this workflow when the user wants to move from "what methods exist" to "which one wins under my constraints and why."

## Prerequisites

Before starting, verify that the following exist:

- A completed survey under `./surveys/` with method inventory and first-principles derivations.
- A clear problem domain (signal type, impairment model, target platform or application).

If either is missing, run `deep-research-survey` first or ask the user to supply the gap.

## Workflow

Run the work in this order (quality gates enforce phase readiness):

1. Frame the scenario: signal model, metrics, constraints, candidate methods.
2. Implement candidates with a uniform interface and shared utilities. **→ G1 gate**
3. Run a multi-seed baseline comparative study with statistical aggregation. **→ G2 gate**
4. Sweep key hyperparameters and environmental variables. **→ G3 gate**
5. Evaluate finite-precision or resource-constrained realizations when relevant. **→ G4 gate**
6. Consolidate into a written study with recommendation table and red-team critique.

## Phase Gates

Use these phases unless the user asks for a faster path.

### Phase 1: Scenario & Requirements

- Define the **signal model** in domain-general terms.
  - Desired signal (waveform, bandwidth, modulation, block structure).
  - Impairments (interference, distortion, drift, mismatch — whatever the algorithm targets).
  - Noise (type, level, statistics).
- Define **evaluation metrics** (at least two from: accuracy / distortion / convergence speed / latency / throughput / resource cost).
- Define **constraints** (wordlength, real-time budget, memory, power, area — whichever apply).
- Select **candidate methods** from the survey inventory (minimum 2, recommend 3–4).
- Write up the scenario in `docs/<topic>-implementation-study.md` before coding.

### Phase 2: Reference Implementation

- Implement each candidate as a **frozen dataclass** with a uniform call interface.
  - Typical patterns: `.filter(x)`, `.run(x)`, `.estimate(x)`, `.process(x)` — pick the verb that fits the domain.
  - Return `(output, telemetry_dict)` so callers can inspect internals without coupling to them.
  - Support a `.replay(x, state_history)` method when the algorithm has time-varying internal state.
- Extract shared helpers into `implementation/<topic>/utils.py`:
  - Quantisation helpers (with optional saturation via `integer_bits`).
  - Signal generators (tones, noise, modulated waveforms).
  - Metric functions (EVM, SNR, MSE, BER — whatever Phase 1 defined).
  - Named numerical-safety constants (`EPSILON_DIV`, etc.).
- Each implementation must be **pure**: deterministic given config + input, explicit random seeds, no hidden mutable state.
- Place source files under `implementation/<topic>/`.
- Add or extend tests under `tests/<topic>/` to cover utilities and basic correctness for each candidate.

**Gate → Phase 3:** Before proceeding, run the full test suite (`pytest tests/<topic>/`) and verify every candidate passes. If any candidate fails, fix or exclude it before starting the baseline comparison. Record the gate result in the study doc:

```markdown
### Phase 2 → 3 Gate
- Test command: `pytest tests/<topic>/ -v`
- Result: PASS / FAIL
- Candidates cleared: [list]
- Candidates excluded: [list, with reason]
```

### Phase 3: Baseline Comparative Study

- Run all candidates against the **same input and scenario config** across **N independent random seeds** (default N = 5, minimum 3).
- Compute every metric from Phase 1 for each candidate **per seed**.
- Aggregate across seeds: report **mean**, **standard deviation**, and **95 % confidence interval** for every metric. Use `scipy.stats.t.interval` or equivalent for CI computation.
- Present per-seed results in a long-form table; present aggregated statistics in the summary table.
- Produce three artifact types, all saved under `artifacts/<study-name>/baseline/`:
  - **Persistent data** (`.npz` or equivalent) — full numerical results for every seed, regenerable without rerunning.
  - **Summary** (`.json`) — config + per-method per-seed metrics + aggregated statistics (mean, std, CI), machine-readable.
  - **Interactive figure** (`.html` via Plotly or equivalent) — supports zoom, pan, hover. Show error bars (CI) on the primary comparison chart.
- Append results and interpretation to `docs/<topic>-implementation-study.md`.

### Phase 4: Sensitivity & Optimisation

- For each candidate, identify **2–4 key hyperparameters** (step size, block length, filter order, regularisation weight — domain dependent).
- Sweep each on a grid while holding others at baseline.
- Optionally sweep **environmental parameters** (SNR, interference level, drift rate, channel model).
- If a composite score is used, **document the weight rationale** inline.
- Produce sweep artifacts under `artifacts/`.
- Append sensitivity findings to the study doc.

### Phase 5: Finite-Precision / Resource-Constrained Realisation

**Gate:** Skip this phase if the study domain is purely floating-point, software-only, or the user says to skip.

- Map each candidate to **realisation structures** appropriate to the domain:
  - DSP / filter: direct-form, transposed, lattice, SOS cascade.
  - ML / inference: reduced precision (INT8, FP16), pruning, distillation.
  - Communications: look-up table, CORDIC, bit-serial.
  - Control: fixed-point state-space, delta-operator form.
- Sweep **wordlength** (or equivalent precision knob) with saturation-aware quantisation.
- Compare realisation robustness: which structure degrades most gracefully?
- Produce precision-study artifacts under `artifacts/`.
- Append realisation findings to the study doc.

### Phase 6: Report & Decision

- Ensure `docs/<topic>-implementation-study.md` covers:
  1. Problem statement and signal model.
  2. Candidate method descriptions with key equations.
  3. Baseline comparison results with figures (including CI error bars).
  4. Sensitivity analysis highlights.
  5. Realisation / precision results (if Phase 5 ran).
  6. **Recommendation table**: winner, runner-up, conditions where each alternative wins.
  7. **Red-team critique**: before finalising, write a dedicated subsection that challenges the top recommendation. Cover:
     - At least two realistic scenarios where the runner-up or another candidate would outperform the winner.
     - Assumptions in the evaluation that, if violated, would change the ranking.
     - Any metric where the winner is within the CI of another candidate (i.e., the margin is not statistically significant).
     - A brief verdict: does the recommendation survive the critique, and if so, with what caveats?
  8. Limitations and suggested follow-on work.
- Number all display equations.
- Update `docs/development-timeline.md` with milestone completion.
- Log the final delivery in `prompts/YYYY-MM-DD.md`.

## Artefact Rules

Apply to every phase that produces output:

- **Persistent data**: save underlying results so figures regenerate without rerunning compute.
- **Interactive behaviour**: support zoom, pan, hover unless embedded in a static document.
- **Reproducibility**: every experiment config stored in the JSON summary; all random seeds explicit.
- **Naming**: `artifacts/<study-name>/` with descriptive filenames; one subdirectory per study or sweep.
- **Versioning**: maintain a `artifacts/<study-name>/study-manifest.json` that tracks every study iteration. Update the manifest each time Phase 3, 4, or 5 produces new artifacts. Schema:

```json
{
  "study": "<study-name>",
  "iterations": [
    {
      "version": 1,
      "timestamp": "2026-03-17T14:30:00Z",
      "phase": 3,
      "description": "Baseline comparison, 5 seeds, 4 candidates",
      "config_hash": "<sha256 of the JSON config>",
      "artifacts": [
        "baseline/results.npz",
        "baseline/summary.json",
        "baseline/comparison.html"
      ],
      "metrics_snapshot": {
        "<method>": { "metric": { "mean": 0.0, "std": 0.0, "ci95": [0.0, 0.0] } }
      },
      "notes": ""
    }
  ]
}
```

When re-running a phase with changed parameters or candidates, increment `version`, preserve all prior entries, and note what changed in `description`. This enables regression comparison across study iterations without manual bookkeeping.

## Quality Gates

Automated checks that validate phase outputs before the next phase begins. Run via the gate validation script at `.claude/skills/reference-implementation-study/validate_gate.py`.

| Gate | Trigger | Checks | Blocks |
|------|---------|--------|--------|
| **G1: Implementation → Baseline** | End of Phase 2 | All candidates importable; `pytest tests/` passes; each candidate accepts a trivial input without error | Phase 3 |
| **G2: Baseline → Sensitivity** | End of Phase 3 | `artifacts/<study>/baseline/summary.json` exists and is valid JSON; every Phase 1 metric present for every candidate; `.npz` file loadable; manifest updated | Phase 4 |
| **G3: Sensitivity → Precision** | End of Phase 4 | Sweep artifacts exist under `artifacts/<study>/`; at least one sweep per candidate; manifest updated | Phase 5 |
| **G4: Precision → Report** | End of Phase 5 | Precision artifacts exist; wordlength sweep data loadable; manifest updated | Phase 6 |

Gate behaviour:
- **PASS**: proceed to next phase.
- **FAIL**: print failing checks, do not proceed. Fix issues and re-run the gate.
- **SKIP**: if the user explicitly requests skipping a phase, its outbound gate is also skipped.

Usage:

```bash
python .claude/skills/reference-implementation-study/validate_gate.py <study-name> <gate>
# e.g.: python .claude/skills/reference-implementation-study/validate_gate.py iq-imbalance G1
```

## Implementation Rules

- All configs as **frozen dataclasses** with typed fields and sensible defaults.
- All random seeds **explicit and stored** in the config.
- Shared helpers in `implementation/<topic>/utils.py`; domain-specific logic in dedicated modules.
- Named constants for numerical-safety floors (`EPSILON_DIV = 1e-12`, etc.) — no bare magic numbers.
- Input validation: reject clearly invalid parameters at construction time (`__post_init__`).
- Tests under `tests/<topic>/` for utilities, validation, and basic per-candidate correctness.

## Math Rules

Inherited from project-level CLAUDE.md:

- Build from first principles, show every step.
- Include definitions, assumptions, numbered equations, and intuition for major results.
- Keep chained equalities compact on adjacent lines.

## Skill Chaining

```
deep-research-survey  →  reference-implementation-study
       surveys/                implementation/<topic>/ + artifacts/ + docs/
```

The survey skill produces the method inventory and math. This skill consumes it and produces code, experiments, and a recommendation.

## Tightening a Vague Request

If the user only says "implement and compare the methods from the survey", rewrite internally as:

```text
Using the completed survey under ./surveys/, frame a canonical evaluation
scenario with explicit signal model, metrics, and constraints. Implement the
top 3–4 candidate methods as frozen-dataclass reference modules with a shared
utility layer. Run a baseline comparison, sweep key hyperparameters, and
(if applicable) evaluate finite-precision realisations. Consolidate into a
study document with numbered equations, interactive figures, and a
recommendation table naming the winner and the conditions under which
alternatives are preferred.
```

## Deliverables Checklist

At skill completion, the following should exist:

- [ ] `docs/<topic>-implementation-study.md` — full written study with equations, figures, CI error bars, red-team critique, and recommendation.
- [ ] `implementation/<topic>/<module>.py` — reference implementations for each candidate.
- [ ] `implementation/<topic>/utils.py` — shared utilities (extended if pre-existing).
- [ ] `tests/<topic>/test_<module>.py` — unit tests covering utilities + per-candidate basics.
- [ ] `artifacts/<study>/` — at least one subdirectory per phase (baseline, sweeps, precision).
  - Each contains `.json` summary (with mean/std/CI statistics), `.html` interactive figure, and optionally `.npz` raw data.
- [ ] `artifacts/<study>/study-manifest.json` — versioned iteration log for regression tracking.
- [ ] All quality gates passed (G1–G4, or G1–G2 if Phases 4–5 skipped).
- [ ] `docs/development-timeline.md` — updated with milestone entries.
- [ ] `prompts/YYYY-MM-DD.md` — conversation log entries for each working session.
