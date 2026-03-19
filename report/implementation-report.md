# Implementation Report: claude-config Test Suite

**Date:** 2026-03-19
**Plan:** `plan/test-plan.md`
**Status:** Complete — all 123 tests passing

---

## Summary

Implemented the full test suite specified in `plan/test-plan.md`, covering all 5 components of the `claude-config` repository. The suite verifies every functional path from individual script arguments through end-to-end cross-repo sync simulation.

### Test Count Reconciliation

The plan specified 101 cases. The implementation delivers 123 due to expanded coverage in two areas:

| Component | Plan | Implemented | Delta | Reason |
|-----------|------|-------------|-------|--------|
| 1. compose.sh | 28 | 32 | +4 | Plan counted 28 unique scenarios; implementation added 4 sub-assertions within existing cases that register as separate pass/fail |
| 2. validate_gate.py | 28 | 35 | +7 | Additional sub-checks on output format; more granular gate assertion points |
| 3. Structural integrity | 14 | 20 | +6 | Expanded checks (e.g., YAML front matter closing delimiter, name field, description field each counted separately) |
| 4. Cross-repo sync | 25 | 30 | +5 | Config variation tests promoted from implicit to explicit assertions |
| 5. Consumer context | 6 | 6 | 0 | Exact match |
| **Total** | **101** | **123** | **+22** | |

---

## Files Created

### Test Infrastructure

| File | Purpose | Cases |
|------|---------|-------|
| `tests/run_all.sh` | Top-level runner, aggregates results | — |
| `tests/test_compose.sh` | compose.sh unit tests | 32 |
| `tests/test_validate_gate.py` | validate_gate.py unit tests | 35 |
| `tests/test_structure.sh` | Repo structural integrity | 20 |
| `tests/test_sync_workflow.sh` | Cross-repo sync simulation | 30 |
| `tests/test_gate_consumer.py` | Gate validator in consumer context | 6 |

### Test Fixtures

| File | Purpose |
|------|---------|
| `tests/fixtures/base-minimal.md` | Minimal base with INSERT_SECTIONS marker |
| `tests/fixtures/base-no-marker.md` | Base without marker (section-drop test) |
| `tests/fixtures/alpha.md` | Dummy section for ordering tests |
| `tests/fixtures/beta.md` | Dummy section for ordering tests |
| `tests/fixtures/skill-valid/SKILL.md` | Valid skill with proper YAML front matter |
| `tests/fixtures/skill-no-desc/SKILL.md` | Skill missing `description:` field |
| `tests/fixtures/skill-crlf/SKILL.md` | Skill with Windows CRLF line endings |
| `tests/fixtures/skill-orphan/` | Empty dir (no SKILL.md — skip test) |
| `tests/fixtures/sync-default.yml` | Default consumer config |
| `tests/fixtures/sync-one-section.yml` | Config with `plan-workflow` enabled |
| `tests/fixtures/sync-bad-section.yml` | Config referencing nonexistent section |
| `tests/fixtures/sync-no-sections-key.yml` | Config without `sections:` key |
| `tests/fixtures/sync-crlf.yml` | Config with CRLF line endings |

---

## Implementation Decisions

### 1. No External Test Frameworks

Per plan, tests use only bash, Python stdlib (`unittest`), and git. No pytest plugins, no Docker, no CI-specific tooling.

### 2. REPO_ROOT Patching Strategy

The `validate_gate.py` script resolves `REPO_ROOT` at module load time via `Path(__file__).resolve().parents[3]`. To test gate functions against temp directories:

- Load the module with `importlib.util`
- Execute the module code (which sets `REPO_ROOT` to the real path)
- **Override** `mod.REPO_ROOT = tmpdir` after `exec_module`
- Gate functions read `REPO_ROOT` at call time (Python global lookup), so they see the patched value

A critical lesson: patching before `exec_module` is ineffective because the module-level `REPO_ROOT = ...` line overwrites the patch.

### 3. sys.modules Cache Cleanup

Gate G1 tests import user-provided modules via `importlib.import_module("implementation.method_a")`. Python's module cache persists across test methods, so a module imported in one test would mask a broken module in the next. The fix: `tearDown` clears all `sys.modules` entries starting with `"implementation"`.

### 4. Windows Compatibility

Three platform-specific issues addressed:

1. **CRLF line endings**: compose.sh already handles this with `line="${line//$'\r'/}"`. Tests verify this works for both configs and SKILL.md files.
2. **Encoding**: Python's `Path.read_text()` defaults to the system locale (GBK on some Windows systems). Fixed by specifying `encoding="utf-8"` explicitly in consumer context tests.
3. **Path compilation**: `python -c "import py_compile; py_compile.compile('...')"` with Windows paths fails due to backslash escaping. Fixed by using `python -m py_compile "$path"` instead.

### 5. Sync Simulation Approach

Rather than mocking GitHub Actions, `test_sync_workflow.sh` replicates the workflow steps directly:

1. `cp -r` claude-config into `_claude-config/` (simulates `actions/checkout`)
2. `rm -rf .claude/skills/ && cp -r` (simulates skills sync step)
3. `bash compose.sh` with all flags (simulates compose step)
4. `rm -rf _claude-config` (simulates cleanup step)

This tests the actual scripts and file operations, not mocked versions.

---

## Critical Finding: REPO_ROOT Depth Mismatch

As predicted by the test plan (case 5.1.3), `validate_gate.py` uses `parents[3]` which assumes the **consumer** path depth (`.claude/skills/<skill>/validate_gate.py` = 4 levels). From the **source** repo path (`skills/<skill>/validate_gate.py` = 3 levels), `parents[3]` resolves one level too high.

**Impact:** The script cannot be run directly from the source repo (claude-config). It only works correctly after sync to a consumer repo. The comment in the code (`# .claude/skills/<skill>/ → repo root`) confirms this is by design, but it's worth documenting.

**Recommendation:** No fix needed if running from source is not a use case. If dual-path support is ever needed, replace:
```python
REPO_ROOT = Path(__file__).resolve().parents[3]
```
with:
```python
_p = Path(__file__).resolve()
REPO_ROOT = _p.parents[3] if ".claude" in _p.parts else _p.parents[2]
```

---

## Dependencies

- bash (any modern version)
- Python 3.10+ (for `match` statement compatibility in future; stdlib only)
- git (for diff detection and idempotency tests)
- pytest (available via `pip install pytest`; used only as test runner, no plugins)
- numpy (optional; only needed if G2/G4 `.npz` tests use real numpy arrays — fallback creates minimal valid `.npz` via `zipfile`)
