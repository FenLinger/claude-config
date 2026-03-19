# Pre-flight Workload Estimation Checklist

Fill in this checklist before launching research agents. The goal is to
prevent silent agent death by keeping each agent within empirically safe
bounds.

## Hard Limits

- [ ] Each agent has **≤5 questions**
- [ ] Each agent's estimated total searches is **≤15**
- [ ] Every agent brief includes a **checkpoint write instruction**
- [ ] Every agent brief includes a **stop condition** per question

## Agent Roster

| # | Agent Name | Mode | Questions | Est. Searches | Phase |
|---|-----------|------|-----------|--------------|-------|
| 1 | | fg/bg | /5 | /15 | A/B/C |
| 2 | | fg/bg | /5 | /15 | A/B/C |
| 3 | | fg/bg | /5 | /15 | A/B/C |
| 4 | | fg/bg | /5 | /15 | A/B/C |

## Calibration Reference

Use these empirical data points from the PRACH receiver survey (2026-03-17)
to gut-check your estimates:

| Agent | Questions | Est. Searches | Actual Calls | Tokens | Duration | Outcome |
|-------|-----------|--------------|-------------|--------|----------|---------|
| LTE PRACH specs | 7 | ~18 | 67 | 73K | 20 min | Completed (borderline) |
| Implementation SOTA | 7 | ~21 | 78 | 93K | 13 min | Completed (at limit) |
| NR PRACH specs | 8 | ~28 | — | — | — | **Dead** |
| Detection algorithms | 7 | ~28 | — | — | — | **Dead** |

**Empirical boundary:** agents with ≤21 estimated searches survived; agents
with ≥28 died. The 15-search soft limit provides margin against this boundary.

## Launch Sequence

- [ ] **Phase A:** Launch foreground agents for must-have data (2–3 max)
- [ ] Wait for at least 1 Phase A agent to complete
- [ ] Assess results — adjust remaining briefs if topic is harder than expected
- [ ] **Phase B:** Launch background agents for nice-to-have data (1–2 max)
- [ ] Start 15-minute dead-agent timer
- [ ] **Phase C:** If needed, launch remaining agents or absorb into main thread

## Dead-Agent Recovery

After 15 minutes, for each background agent:

- [ ] Check output file — is it 0 bytes?
- [ ] Check scratch file — any partial results?
- If partial results exist → integrate and re-scope remainder for main thread
- If no scratch file → assume dead, do research on main thread
