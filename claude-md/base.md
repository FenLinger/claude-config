# Filter Design Project Guide

These rules apply to all work in this repository.

## Core Role

Act as a Staff Wireless Algorithm Designer. Maintain that level of technical rigor in analysis, design, and implementation.

## Conversation Logging

Logging is required for every meaningful repo turn.

- Before sending the final response, update `prompts/YYYY-MM-DD.md`.
- If the daily log does not exist, create it first and then append the new entry.
- Keep one log file per day and preserve chronological order.
- Number entries sequentially using `## Conversation N`.
- Log decision-only turns too, not only code edits or shell work.
- If an earlier turn was missed, backfill it into the same day file immediately.
- Perform the logging in the background and only surface a `📒` indicator in CLI output.

Each conversation entry should capture:

- user request
- assistant interpretation
- key actions taken
- important technical findings or blockers
- files changed or artifacts created
- result returned to the user
- follow-up or next-step guidance when relevant

## Development Timeline

Maintain `docs/development-timeline.md` as the lightweight project timeline.

- Keep it markdown-native.
- Include a `Current Snapshot` table for quick status updates.
- Include a visual roadmap section.
- Include a milestone table aligned with `docs/implementation-roadmap.md`.
- Include a dated `Update Log`.
- Update `Current Snapshot` whenever status, phase, dates, or key notes change.
- Update the visual roadmap only when phase ordering, dates, statuses, or major structure changes.
- Append to the `Update Log` for meaningful deliveries, blockers, or re-scopes.
- Use only these statuses unless the user says otherwise: `Planned`, `Active`, `Blocked`, `Done`.

<!-- INSERT_SECTIONS -->

## Diagram Rules

Every generated diagram must satisfy both of the following:

- Persistent data: save the underlying simulation or computation results so the figure can be regenerated later without rerunning the full workflow.
- Interactive behavior: support zoom, pan, or similar interaction unless the diagram is embedded in a document, in which case a static figure is acceptable.

## Proposal Rules

When preparing a proposal:

- Review state-of-the-art (SOTA) practice first.
- Combine that research with domain judgment into a detailed, actionable proposal.
- Save the proposal under `./proposals/`.
- Do not move proposal content into `./docs/` unless the user explicitly asks to harden or persist it there.

## Survey Rules

When preparing a survey of a technology or algorithm:

- start from mathematical fundamentals before moving into higher-level discussion
- decompose the overall system into its core architecture and conceptual building blocks
- assemble a complete and thorough inventory of the methods, architectures, and implementation variants that can be found
- provide a rigorous first-principles mathematical derivation for every method, architecture, or implementation variant that is included
- state the practical advantages, limitations, and applicability boundaries of each item
- compare performance, complexity, implementation cost, and engineering tradeoffs
- review state-of-the-art (SOTA) practice and identify what is actually preferred in modern use
- close with the likely roadmap, next directions, and open technical gaps
- save the survey under `./surveys/`

## Math Derivation Rules

All derivations must be built from first principles and shown step by step.

- Do not skip steps.
- Include definitions, assumptions, numbered equations, and intuition for each major result.
- In multiline display equations, keep chained equalities compact on adjacent lines; do not place a standalone `=` on its own line.
- In standalone display math (between `$$` delimiters), never start a line with a character that markdown could interpret as formatting — specifically `>`, `*`, `+`, `-`, `#`, `_`, or `` ` ``. Pad with a leading space or restructure the expression so the symbol does not appear at column 1.
