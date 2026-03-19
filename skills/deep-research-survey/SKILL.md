---
name: deep-research-survey
description: Turn a topic into a rigorous deep-research request and delivery workflow. Use when the user asks for a deep research survey, literature review, technical landscape, state-of-the-art review, or thorough investigation of a subject and expects first-principles explanation, broad method coverage, tradeoff analysis, current practice, references, or a reusable prompt.
---

# Deep Research Survey

## Overview

Translate broad research requests into a concrete research brief and then execute them with phased control, evidence discipline, and a consistent final deliverable.

Prefer this workflow when the user wants depth, completeness, source-backed claims, broad method coverage, or a reusable prompt for future research.

## Workflow

Run the work in this order:

1. Scope the subject and the output contract.
2. Build or confirm an outline before deep expansion when the topic is large.
3. Collect evidence by section rather than collecting undifferentiated links.
4. Score source quality and prioritize primary sources.
5. Synthesize section drafts from the evidence.
6. Merge findings conservatively: preserve unique supported findings instead of averaging them away.
7. Produce a final report that clearly separates sourced facts, inferred conclusions, and recommendations.

## Phase Gates

Use these phases unless the user asks for a faster path:

### Phase 1: Scope

- Pin down the subject.
- Infer or ask for the target audience and desired depth only if that changes the result materially.
- Fix the output shape before researching: survey, proposal, implementation plan, comparison, or executive brief.
- If the topic is too broad, narrow it by domain, layer, time horizon, geography, or implementation target.

### Phase 2: Outline

- Build a section outline before deep research when the subject is broad or high-stakes.
- Make the outline explicit enough that each section has a research question.
- Classify each research question as **must-have** (blocks section writing) or **nice-to-have** (enriches but does not block). This classification drives agent mode selection in Phase 3.
- If the user is collaborative and the topic is large, offer the outline for confirmation before expanding it.

### Phase 3: Evidence Collection

- Collect evidence against the outline, not against the topic in the abstract.
- Track evidence at section level using the ledger below.
- Prefer standards, official documentation, primary papers, and direct vendor material before secondary summaries.
- For fast-moving fields (wireless standards, FPGA/EDA toolchains, ML frameworks, silicon processes), check publication dates and enforce a recency threshold: flag any source older than the most recent major revision of the relevant standard or release cycle, and note the staleness explicitly in the evidence ledger.

#### Agent Sizing and Launch Protocol

When using background agents for parallel evidence collection, follow these rules to prevent silent agent death (agents that exhaust their context window terminate without notification or partial results).

**Pre-flight workload estimation.** Before launching any agent, estimate:
- Questions per agent: **≤5** (hard limit)
- Searches per question: ~2–3 (estimate)
- Total searches per agent: **≤15** (soft limit)
- If estimated searches exceed 15, split the agent or move the excess to main thread.

**Calibration reference.** Empirical data from the PRACH receiver survey (2026-03-17):

| Agent | Questions | Est. searches | Actual tool calls | Tokens | Duration | Outcome |
|-------|-----------|--------------|-------------------|--------|----------|---------|
| LTE PRACH specs | 7 | ~18 | 67 | 73K | 20 min | Completed (borderline) |
| Implementation SOTA | 7 | ~21 | 78 | 93K | 13 min | Completed (at limit) |
| NR PRACH specs | 8 | ~28 | — | — | — | **Dead** |
| Detection algorithms | 7 | ~28 | — | — | — | **Dead** |

Agents with ≤21 estimated searches survived. Agents with ≥28 died. The 15-search soft limit provides margin against the empirical ~21-search danger zone.

**Checkpoint writes.** Instruct every agent to write intermediate results to `survey/_scratch/<agent-name>.md` after completing each question. Template instruction to include in the agent prompt:
> "After answering each question, append your findings to `survey/_scratch/<agent-name>.md` using the Write tool. This ensures partial results survive if you run out of context."

**Staggered launch.** Do not launch all agents simultaneously.
- Phase A: Launch 2–3 agents for the most critical (must-have) evidence. Use **foreground** mode for data that blocks synthesis.
- Phase B: After at least 1 agent completes, assess results. Adjust remaining briefs if the topic is harder than expected.
- Phase C: Launch remaining agents as **background** for nice-to-have evidence.

**15-minute dead-agent check.** After 15 minutes, check each background agent:
- If output file is 0 bytes and no task notification arrived, check the scratch file for partial results.
- If scratch file has content, integrate partial results and re-scope remaining questions for main thread.
- If no scratch file either, assume the agent is dead. Do not wait further; do the research on main thread.

**Foreground vs background classification.**
- **Foreground (blocking):** Data that blocks writing a section (e.g., parameter tables, normative spec values). You need the result before proceeding.
- **Background:** Supplementary evidence that enriches but does not block (e.g., additional paper references, vendor implementation details). Synthesis can proceed without it.

**Synthesis always on main thread.** Never delegate section writing or evidence integration to agents. Agents collect raw evidence only. The main thread owns the outline, writes all sections, and maintains source attribution.

**Narrow agent briefs.** Each agent gets:
- A numbered list of ≤5 specific questions
- Each question has a concrete expected output format (e.g., "a table with columns X, Y, Z")
- A stop condition (e.g., "if you cannot find this in 3 searches, note the gap and move on")
- The checkpoint write instruction above

**Brief quality example.**

_Bad_ (scope too broad, no stop condition, no checkpoint):
> "Research 5G NR PRACH specifications and receiver design. Find all format parameters, ZC generation, PRACH occasions, restricted sets, 2-step RACH, FR1 vs FR2, short sequence specifics, and NR parameters."

_Good_ (narrow scope, concrete output format, stop condition, checkpoint):
> "Find the NR short preamble format parameters (A1–C2). Deliver a table with columns: Format, Symbols, N\_CP, N\_u, CP(μs), GT(μs), max range. Write to `survey/_scratch/nr-short-formats.md`. If you cannot find numeric values in 3 searches, note which formats are missing and stop."

**Templates.** Use the reusable templates in `.claude/skills/deep-research-survey/templates/`:
- `agent-brief.md` — fill-in template for constructing narrow agent briefs
- `preflight-checklist.md` — pre-flight workload estimation and launch checklist

#### Full-Text Acquisition (optional)

Use this sub-step to acquire full-text papers and books for high-value sources that are not freely available. The skill works without it — skip entirely if downloads are not needed or not available.

**Stage 1 — Discover and assess first.**
- Use web search, public databases (Google Scholar, IEEE Xplore, arXiv, standards bodies, vendor docs), and open-access repositories to build the initial evidence ledger as normal.
- Apply the source quality rubric to all discovered sources. Identify which are Tier 1-2 and mark in the ledger which sections have gaps that require full-text access to resolve (e.g., a key derivation behind a paywall, a reference implementation in a book chapter, a standard's normative annex).

**Stage 2 — Acquire publicly available full texts first.**
- Before touching the download budget, check whether each Tier 1-2 source is already freely available: open-access journals, arXiv/preprint servers, author homepages, standards body public drafts, publisher free-access programs, or institutional repositories.
- Use web search or direct URL fetch to retrieve these. Record them in the evidence ledger like any other source — no download budget spent.

**Stage 3 — Build a download shortlist for remaining paywalled sources.**
- From the Tier 1-2 sources that still lack full-text access after Stage 2, select only those where: (a) the abstract/publicly available content is insufficient, AND (b) the full text would materially strengthen the section's evidence.
- Rank the shortlist by impact: sources that fill high-confidence-gap or must-have-primary-source sections first, nice-to-have depth second.
- Cap the shortlist against the daily budget (~50 downloads). Allocate ~35-40 for the main evidence pass, reserve ~10-15 as holdback for gaps discovered during Phase 4 synthesis.

**Stage 4 — Download paywalled sources.**
- Use the `source-fetch` skill to search and download from Anna's Archive.
- If `source-fetch` is not available, use curl + Anna's Archive JSON API directly (see `.claude/skills/source-fetch/SKILL.md` for the full workflow).
- Record in the evidence ledger: `[Author, Title, Year] (local: download/<filename>)` in the Best sources column.
- If a download fails or the source is not found, note in the Gaps column and fall back to abstract-level citation.
- Track budget with a running one-liner after the ledger table: `Downloads: N/~50 used, holdback: H remaining`.

### Phase 4: Synthesis

- Write section drafts from the evidence ledger.
- Distinguish standard practice from state of the art and from your own engineering judgment.
- Preserve supported outlier findings if they add real signal.
- For large or high-stakes surveys, consider a UNION merge: generate two or more independent complete drafts in parallel, then merge them by keeping all unique supported findings from every draft and consolidating duplicates. This combats information dropout from single-pass generation.
- Optionally, after synthesis is complete, spawn a separate verification pass (or agent) to check factual accuracy and logical consistency of the merged draft against the evidence ledger. This catches errors the primary synthesis misses.

### Phase 5: Final Report

- Enforce the requested output format.
- Keep claims traceable to sources.
- End with explicit recommendations, open gaps, and next steps.

## Build the Research Brief

Use this structure when formulating the task for yourself or rewriting the user's request:

```text
Do a deep research survey on [subject].

Requirements:
- Start from first principles
- Explain the system architecture or conceptual decomposition
- Cover the major methods, variants, and competing approaches
- Derive the key mathematics step by step when math matters
- Compare performance, complexity, implementation cost, and tradeoffs
- Distinguish standard practice from current SOTA
- End with open problems, future directions, and recommended next steps

Output format:
- Executive summary
- Detailed technical sections
- Comparison tables
- References with links

Constraints:
- Audience: [engineer / researcher / executive / beginner]
- Depth: [high-level / graduate-level / implementation-level]
- Focus: [theory / practical design / code / hardware / standards]
- Exclude: [topics to skip]
- Source preference: [papers / standards / official docs / vendor docs]
- Output contract: [survey / proposal / implementation plan / report / reusable prompt]
```

## Execution Rules

Apply these defaults unless the user overrides them:

- Start with definitions, assumptions, and scope boundaries.
- Organize from fundamentals to architecture to method inventory to tradeoffs to current practice to roadmap.
- Treat omission risk as a quality problem when the user asks for a deep survey.
- Prefer primary sources for technical claims.
- Browse and cite sources when the topic is current, standards-driven, high-stakes, niche, or the user asks for verification.
- Say explicitly when a conclusion is an inference rather than a directly sourced statement.
- If the subject is broad, narrow it by application domain, time horizon, or implementation layer instead of staying vague.
- If the subject is large, outline first and research second.
- When multiple drafts or evidence clusters disagree, preserve supported unique findings and resolve conflicts explicitly.

### Source Attribution Discipline

- Every factual claim must cite a specific source immediately. Do not make unsourced assertions about performance, specifications, or external design choices.
- Distinguish clearly between three categories: **sourced facts** (cited), **engineering judgment** (your own analysis, labeled as such), and **inferences** (logical conclusions drawn from evidence, labeled as such).
- When no source can be found for a relevant claim, say "no source found" or "not confirmed in available references" rather than omitting the point or fabricating a citation.
- Do not use vague attributions ("studies show", "it is widely known", "research suggests"). Name the source or qualify the statement as judgment.

## Source Quality Rubric

Use this ranking by default:

1. Primary standards, official documentation, original papers, source repositories, first-party product docs
2. High-quality vendor or institutional technical papers
3. Careful secondary reviews
4. Marketing summaries, blog posts, and unsourced commentary

Downgrade a source if it is stale, derivative, promotional, or missing traceable evidence.

Papers and books obtained via `source-fetch` are typically Tier 1 or Tier 2. Classify on content, not on the fact that they were downloaded.

## Evidence Ledger

Track evidence in a compact section-wise ledger when the task is nontrivial:

| Section | Question | Key findings | Best sources | Confidence | Gaps |
| --- | --- | --- | --- | --- | --- |
| [section] | [what must be answered] | [facts or comparisons] | [links or citations] | [high/medium/low] | [what is still missing] |

For locally downloaded sources, use `[Author, Title, Year] (local: download/<filename>)` in the Best sources column so the full text is traceable during synthesis.

Use the ledger to prevent source drift and unsupported section writing.

## Default Output Structure

Use this structure unless the user asks for something else:

1. Executive summary
2. Scope and problem definition
3. Mathematical or conceptual fundamentals
4. System architecture and decomposition
5. Complete method and variant inventory
6. Derivations or governing equations for the important methods
7. Performance, complexity, and cost tradeoffs
8. State of the art and what is actually used in practice
9. Design guidance or decision framework
10. Open problems and future roadmap
11. References

## Report Contract

Unless the user says otherwise:

- begin with a short executive summary
- make section titles concrete and decision-useful
- include comparison tables where they reduce ambiguity
- cite sources inline or at section end
- separate facts, inferences, and recommendations
- call out uncertainty or missing evidence explicitly
- avoid broad claims that are not traceable to sources

## Response Modes

Choose one and state it briefly when useful:

- Survey mode: broad, comparative, source-backed coverage
- Proposal mode: recommend a plan for one target problem
- Implementation mode: convert the research into code, experiments, or design steps
- Prompt mode: produce a reusable prompt the user can paste later
- Report mode: produce a publication-style or client-style final deliverable with stricter formatting and evidence discipline

## Tightening a Vague Request

If the user only says "do deep research on X", rewrite it internally as:

```text
Produce a rigorous research survey on X. Start from first principles, build an outline, research each section against explicit questions, track the evidence by section, compare the main approaches on performance and implementation tradeoffs, summarize what is state of the art versus what is actually used in practice, and end with references, open gaps, and recommended next steps.
```

## Deliverables

When the user asks for a reusable prompt, return:

- a short prompt for quick use
- a full prompt for maximum rigor
- optional knobs for audience, depth, focus, and source preferences
- an optional report contract covering format, citations, and evidence expectations

When the user asks for a full deep-research deliverable, default to:

1. brief scope statement
2. outline
3. evidence-led section synthesis
4. final report
