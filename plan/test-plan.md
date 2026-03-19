# Test Plan: claude-config — Full Functionality Coverage

## Context

`claude-config` is a configuration hub that distributes skills and composed CLAUDE.md files to consumer repos via a GitHub Actions sync workflow. It has no test infrastructure today. This plan defines a comprehensive test suite covering every functional component, with special emphasis on cross-repo sync scenarios (the primary way this repo is consumed).

The test suite will be implemented as:
- **Shell-based tests** (`tests/test_compose.sh`) for `compose.sh` — the core assembly script
- **Python tests** (`tests/test_validate_gate.py`) for `validate_gate.py` — the quality gate validator
- **Structural/lint tests** (`tests/test_structure.sh`) for file integrity, YAML front matter, and cross-references
- **Workflow simulation tests** (`tests/test_sync_workflow.sh`) for the end-to-end sync pipeline as experienced by a consumer repo

All tests use only bash, Python stdlib, and git — no external test frameworks required.

---

## Component 1: `compose.sh` — CLAUDE.md Assembly Script

**File under test:** `compose.sh`
**Test file:** `tests/test_compose.sh`

Each test creates a temp directory with fixture files, runs `compose.sh`, and asserts on stdout/stderr/exit-code/output-file content.

### 1.1 Argument Parsing

| # | Case | Setup | Expected |
|---|------|-------|----------|
| 1.1.1 | All required args provided | Valid `--base`, `--config`, `--sections-dir`, `--output` | Exit 0, output file created |
| 1.1.2 | Missing `--base` | Omit `--base` | Exit 1, stderr contains "base" |
| 1.1.3 | Missing `--config` | Omit `--config` | Exit 1, stderr contains "config" |
| 1.1.4 | Missing `--sections-dir` | Omit `--sections-dir` | Exit 1, stderr contains "sections-dir" |
| 1.1.5 | Missing `--output` | Omit `--output` | Exit 1, stderr contains "output" |
| 1.1.6 | Unknown option | `--bogus foo` | Exit 1, stderr contains "Unknown option" |
| 1.1.7 | `--skills-dir` is optional | Omit `--skills-dir`, provide rest | Exit 0, no skills section in output |

### 1.2 YAML Section Parsing (`parse_sections`)

| # | Case | `.claude-sync.yml` content | Expected sections |
|---|------|---------------------------|-------------------|
| 1.2.1 | Single section | `sections:\n    - plan-workflow` | `["plan-workflow"]` |
| 1.2.2 | Multiple sections | `sections:\n    - plan-workflow\n    - another` | `["plan-workflow", "another"]` |
| 1.2.3 | Empty list (inline) | `sections: []` | `[]` (no sections inserted) |
| 1.2.4 | No sections key | `skills: all\nclaude_md:\n  base: true` | `[]` (no sections inserted) |
| 1.2.5 | Windows CRLF line endings | Same as 1.2.1 but `\r\n` | Parses correctly, strips CR |
| 1.2.6 | Sections followed by other YAML keys | `sections:\n    - plan-workflow\nother_key: value` | `["plan-workflow"]` only, stops at non-list line |

### 1.3 Section Insertion (Marker Replacement)

| # | Case | Setup | Expected |
|---|------|-------|----------|
| 1.3.1 | Marker present, one section | base.md with `<!-- INSERT_SECTIONS -->`, config lists `plan-workflow` | Section content replaces marker position |
| 1.3.2 | Marker present, no sections | base.md with marker, config has `sections: []` | Marker line removed, no extra blank lines |
| 1.3.3 | No marker in base | base.md without marker, config lists a section | Section content NOT inserted (silently dropped — verify base content passes through unchanged) |
| 1.3.4 | Section file missing | Config lists `nonexistent-section`, file doesn't exist | Warning on stderr, continues without crashing, output contains base content |
| 1.3.5 | Multiple sections ordering | Config lists `[alpha, beta]`, both exist | alpha content appears before beta in output |
| 1.3.6 | Section with trailing newlines | Section file has trailing `\n\n\n` | Single newline between sections (no blank line accumulation) |

### 1.4 Skills Section Generation

| # | Case | Setup | Expected |
|---|------|-------|----------|
| 1.4.1 | Single skill directory | `skills/my-skill/SKILL.md` with valid front matter | Output contains `## Skills`, `` - `my-skill`: <description> `` |
| 1.4.2 | Multiple skill directories | 3 skill dirs with SKILL.md | All 3 listed under `### Available Skills` |
| 1.4.3 | Skill missing `description` in front matter | SKILL.md has `---\nname: foo\n---` | Falls back to `(no description)` |
| 1.4.4 | Skill directory without SKILL.md | `skills/orphan/` dir exists, no SKILL.md inside | Silently skipped, not listed |
| 1.4.5 | SKILL.md with Windows CRLF | Front matter uses `\r\n` | Description extracted correctly |
| 1.4.6 | `--skills-dir` omitted | No skills flag | No `## Skills` section appended |
| 1.4.7 | Skills path references | Each skill listed | File path shows `.claude/skills/<name>/SKILL.md` (consumer-side path) |
| 1.4.8 | Skill Usage Rules block | Any valid skills dir | Output contains all 8 usage rules from `generate_skills_section()` |

### 1.5 End-to-End Composition

| # | Case | Setup | Expected |
|---|------|-------|----------|
| 1.5.1 | Full golden-path | Real `base.md` + `plan-workflow` section + all 3 skills | Output matches the CLAUDE.md currently checked into this repo |
| 1.5.2 | Base only, no sections, no skills | Minimal base, empty sections, no `--skills-dir` | Output = base content verbatim (minus marker line) |
| 1.5.3 | Output file path with spaces | `--output "/tmp/my dir/CLAUDE.md"` | File created at quoted path |
| 1.5.4 | Overwrite existing output | Output file already exists | Overwrites without error |
| 1.5.5 | Success message | Any valid run | stderr contains "Composed ... successfully" |

---

## Component 2: `validate_gate.py` — Quality Gate Validator

**File under test:** `skills/reference-implementation-study/validate_gate.py`
**Test file:** `tests/test_validate_gate.py`

Tests create temporary directory trees mimicking a consumer repo's `implementation/`, `artifacts/`, and `tests/` structure, then run the validator. The `REPO_ROOT` resolution needs mocking/patching since the script computes it from its own `__file__` path.

### 2.1 CLI Interface

| # | Case | Argv | Expected |
|---|------|------|----------|
| 2.1.1 | No arguments | `[]` | Exit 2, usage message |
| 2.1.2 | One argument only | `["study-name"]` | Exit 2, usage message |
| 2.1.3 | Invalid gate name | `["study-name", "G5"]` | Exit 2, usage message |
| 2.1.4 | Case insensitive gate | `["study-name", "g1"]` | Accepted (uppercased internally) |
| 2.1.5 | Valid invocation | `["study-name", "G1"]` | Runs G1 checks (exit depends on fixtures) |

### 2.2 Gate G1 — Implementation → Baseline

| # | Case | Fixture state | Expected |
|---|------|--------------|----------|
| 2.2.1 | All passing | `implementation/` with `utils.py` + 2 candidate `.py` files + importable + `tests/` + pytest passes | Exit 0, all `[+] PASS` |
| 2.2.2 | Missing `implementation/` dir | No dir | Exit 1, FAIL on "implementation/ directory exists" |
| 2.2.3 | Missing `utils.py` | Dir exists but no `utils.py` | Exit 1, FAIL on utils check |
| 2.2.4 | Only 1 candidate module | `implementation/` has `utils.py` + 1 candidate | Exit 1, FAIL on "At least 2 candidate modules" |
| 2.2.5 | Candidate import fails | One `.py` file has `raise ImportError` | Exit 1, FAIL on that module's import check |
| 2.2.6 | No `tests/` directory | Everything else valid | Exit 1, FAIL on "tests/ directory exists" |
| 2.2.7 | pytest fails | Valid structure but a failing test | Exit 1, FAIL on "pytest tests/ passes", includes pytest output tail |
| 2.2.8 | `__init__.py` and `__pycache__` excluded | Both present in `implementation/` | Not counted as candidate modules |

### 2.3 Gate G2 — Baseline → Sensitivity

| # | Case | Fixture state | Expected |
|---|------|--------------|----------|
| 2.3.1 | All passing | `artifacts/<study>/baseline/summary.json` (valid, ≥2 methods, has mean/std) + `.npz` + `study-manifest.json` with phase 3 entry | Exit 0 |
| 2.3.2 | Missing `summary.json` | No file | Exit 1, FAIL on JSON validity |
| 2.3.3 | Invalid JSON in summary | `summary.json` contains `{broken` | Exit 1, FAIL on JSON parse |
| 2.3.4 | Fewer than 2 methods | `summary.json` has 1 method entry | Exit 1, FAIL on method count |
| 2.3.5 | No mean/std statistics | Methods present but no aggregation keywords | Exit 1, FAIL on stats check |
| 2.3.6 | No `.npz` files | Valid JSON but no `.npz` | Exit 1, FAIL on npz count |
| 2.3.7 | Corrupt `.npz` | File exists but invalid content | Exit 1, FAIL on npz loadability |
| 2.3.8 | Manifest missing phase 3 entry | `study-manifest.json` has iterations but none with `"phase": 3` | Exit 1, FAIL |
| 2.3.9 | Manifest file missing entirely | No `study-manifest.json` | Exit 1, FAIL on manifest validity |

### 2.4 Gate G3 — Sensitivity → Precision

| # | Case | Fixture state | Expected |
|---|------|--------------|----------|
| 2.4.1 | All passing | `artifacts/<study>/` has a sweep subdir (not `baseline`/`precision`) with `.json`, plus manifest with phase 4 | Exit 0 |
| 2.4.2 | No sweep directories | Only `baseline/` exists | Exit 1, FAIL on sweep dir count |
| 2.4.3 | Sweep dir without JSON | Sweep subdir exists but empty | Exit 1, FAIL on JSON in sweep dir |
| 2.4.4 | `baseline` and `precision` excluded | Both present but no other dirs | Exit 1 — they're filtered out |
| 2.4.5 | Manifest missing phase 4 | Manifest exists but no phase 4 entry | Exit 1 |

### 2.5 Gate G4 — Precision → Report

| # | Case | Fixture state | Expected |
|---|------|--------------|----------|
| 2.5.1 | All passing | `artifacts/<study>/precision/` with ≥1 loadable `.npz` + manifest with phase 5 | Exit 0 |
| 2.5.2 | No `precision/` directory | Missing | Exit 1 |
| 2.5.3 | `precision/` exists but no `.npz` | Empty dir | Exit 1 |
| 2.5.4 | Corrupt `.npz` in precision | Bad file | Exit 1 |
| 2.5.5 | Manifest missing phase 5 | Valid precision artifacts but no phase 5 in manifest | Exit 1 |

### 2.6 Output Format

| # | Case | Expected |
|---|------|----------|
| 2.6.1 | Pass output format | Contains `=====`, `Gate G1`, `PASS`, check count `(N/N checks)` |
| 2.6.2 | Fail output format | Contains `FAIL`, individual `[-] FAIL:` lines, count `(N passed, M failed)` |
| 2.6.3 | Mixed results | Some pass, some fail: both `[+]` and `[-]` markers present |

---

## Component 3: Structural Integrity Tests

**Test file:** `tests/test_structure.sh`

These tests validate the repo itself — file existence, cross-references, and schema compliance. Important because consumer repos depend on these files existing at exact paths.

### 3.1 Required Files Exist

| # | Case | Check |
|---|------|-------|
| 3.1.1 | `compose.sh` | Exists, is executable |
| 3.1.2 | `claude-md/base.md` | Exists, contains `<!-- INSERT_SECTIONS -->` marker |
| 3.1.3 | `defaults/.claude-sync.yml` | Exists, is valid YAML-like |
| 3.1.4 | `.github/workflows/sync-claude-config.yml` | Exists |
| 3.1.5 | `README.md` | Exists |

### 3.2 Skill Directory Structure

| # | Case | Check |
|---|------|-------|
| 3.2.1 | Every dir under `skills/` has a `SKILL.md` | Iterate dirs, assert SKILL.md present |
| 3.2.2 | Every `SKILL.md` has YAML front matter | Starts with `---`, has closing `---` |
| 3.2.3 | Every `SKILL.md` has `name:` field | Grep within front matter |
| 3.2.4 | Every `SKILL.md` has `description:` field | Grep within front matter |
| 3.2.5 | `name:` matches directory name | `name:` value == parent dir basename |
| 3.2.6 | `deep-research-survey` templates exist | `templates/agent-brief.md` and `templates/preflight-checklist.md` present |
| 3.2.7 | `reference-implementation-study` validator exists | `validate_gate.py` present and is valid Python (compiles) |
| 3.2.8 | `source-fetch` has no dangling references | SKILL.md doesn't reference files that don't exist |

### 3.3 Workflow File Validity

| # | Case | Check |
|---|------|-------|
| 3.3.1 | Workflow references correct repo | Contains `FenLinger/claude-config` |
| 3.3.2 | Workflow calls `compose.sh` correctly | Contains `bash _claude-config/compose.sh` with all required flags |
| 3.3.3 | Workflow skills sync path matches | `cp -r _claude-config/skills/ .claude/skills/` |
| 3.3.4 | Auto-merge conditional is correct | `inputs.auto_merge == 'true'` AND PR number check |

### 3.4 Section File Integrity

| # | Case | Check |
|---|------|-------|
| 3.4.1 | Every file in `claude-md/sections/` is `.md` | No non-markdown files |
| 3.4.2 | Section files are non-empty | Each file has content |
| 3.4.3 | Default config references valid sections | Every section in `defaults/.claude-sync.yml` (when uncommented) exists in `claude-md/sections/` |

---

## Component 4: Cross-Repo Sync Simulation

**Test file:** `tests/test_sync_workflow.sh`

These tests simulate the full sync lifecycle as experienced by a consumer repo. They create temporary git repos, run the sync steps locally (replicating the workflow), and validate the results. This is the most important test group for "triggered from other repo" coverage.

### 4.1 Consumer Bootstrap (`gh claude-init` equivalent)

| # | Case | Setup | Expected |
|---|------|-------|----------|
| 4.1.1 | Init into empty repo | Fresh `git init` repo | `.github/workflows/sync-claude-config.yml` and `.claude-sync.yml` created at correct paths |
| 4.1.2 | Init into repo with existing `.github/` | Repo has other workflows | New workflow added, existing workflows untouched |
| 4.1.3 | Default config content | After init | `.claude-sync.yml` matches `defaults/.claude-sync.yml` byte-for-byte |

### 4.2 Sync — Skill Distribution

| # | Case | Consumer state before sync | Expected after sync |
|---|------|--------------------------|---------------------|
| 4.2.1 | Fresh sync (no prior `.claude/skills/`) | No `.claude/` dir | `.claude/skills/` created with all 3 skill dirs |
| 4.2.2 | Update sync (stale skills exist) | `.claude/skills/` has old content | Old content replaced completely with current skills |
| 4.2.3 | Sync preserves other `.claude/` content | `.claude/settings.json` exists | Settings file untouched, only `skills/` replaced |
| 4.2.4 | All skill files present after sync | Post-sync | Every file from `skills/` tree is present under `.claude/skills/` |
| 4.2.5 | Skill subdirectory structure preserved | Post-sync | `templates/`, `agents/`, `validate_gate.py` all at correct relative paths |
| 4.2.6 | Permissions preserved | Post-sync | `validate_gate.py` retains file content integrity |

### 4.3 Sync — CLAUDE.md Composition (Consumer Side)

| # | Case | Consumer `.claude-sync.yml` | Expected CLAUDE.md |
|---|------|----------------------------|-------------------|
| 4.3.1 | Default config (no sections) | `sections: []` | Base content + Skills section, no optional sections |
| 4.3.2 | One section enabled | `sections:\n  - plan-workflow` | Base + plan-workflow content inserted at marker + Skills |
| 4.3.3 | Section ordering in CLAUDE.md | `sections:\n  - plan-workflow` | plan-workflow appears between Development Timeline and Diagram Rules |
| 4.3.4 | Skills section always at end | Any config | `## Skills` is the last major section |
| 4.3.5 | Composed CLAUDE.md is self-consistent | Any config | No dangling markers (`<!-- INSERT_SECTIONS -->` replaced), no empty sections |
| 4.3.6 | All 3 skills listed | Default config | `deep-research-survey`, `reference-implementation-study`, `source-fetch` all present with descriptions |

### 4.4 Sync — Diff Detection & PR Behavior

| # | Case | Setup | Expected |
|---|------|-------|----------|
| 4.4.1 | First sync produces changes | Fresh consumer with no CLAUDE.md or skills | `git diff` shows new files: CLAUDE.md + `.claude/skills/**` |
| 4.4.2 | Second identical sync produces no diff | Run sync twice without changing claude-config | Second run: `git diff` empty — no spurious changes |
| 4.4.3 | Upstream skill change propagates | Modify a SKILL.md in claude-config between syncs | Diff shows the change in `.claude/skills/` |
| 4.4.4 | Upstream section change propagates | Modify `plan-workflow.md` between syncs | CLAUDE.md diff reflects the section change |
| 4.4.5 | New skill added upstream | Add `skills/new-skill/SKILL.md` to claude-config | Consumer gets new dir + CLAUDE.md Skills list updated |
| 4.4.6 | Skill removed upstream | Remove a skill dir from claude-config | Consumer's `.claude/skills/` no longer has it (full replacement via `rm -rf` + `cp -r`) |

### 4.5 Sync — Consumer Config Variations

| # | Case | `.claude-sync.yml` | Expected |
|---|------|---------------------|----------|
| 4.5.1 | Default config from `defaults/` | Byte-for-byte copy of `defaults/.claude-sync.yml` | Sync succeeds, produces base + skills, no sections |
| 4.5.2 | Config with uncommented section | `sections:\n  - plan-workflow` | Section injected correctly |
| 4.5.3 | Config with nonexistent section | `sections:\n  - does-not-exist` | Warning on stderr, CLAUDE.md still composed (missing section skipped) |
| 4.5.4 | Config with CRLF line endings | Windows-style line endings | Parses correctly |
| 4.5.5 | Minimal config (sections key absent) | `skills: all\nclaude_md:\n  base: true` | Sync succeeds, no sections inserted |

### 4.6 Sync — Idempotency & Edge Cases

| # | Case | Setup | Expected |
|---|------|-------|----------|
| 4.6.1 | Triple sync idempotent | Sync 3 times in succession | Only first sync produces changes; second and third are no-ops |
| 4.6.2 | Consumer CLAUDE.md has local edits | User manually edited CLAUDE.md before sync | Overwritten by compose — this is expected (sync is authoritative) |
| 4.6.3 | Consumer has local files in `.claude/skills/` | Extra file `custom-skill/SKILL.md` in consumer's skills dir | Deleted by `rm -rf .claude/skills/` — only canonical skills remain |
| 4.6.4 | `_claude-config` cleanup | After sync | No `_claude-config/` directory remains |

---

## Component 5: `validate_gate.py` in Consumer Context

**Test file:** `tests/test_gate_consumer.py`

These tests validate that `validate_gate.py` works correctly when located at its consumer-repo path (`.claude/skills/reference-implementation-study/validate_gate.py`), not its source-repo path. This is the "triggered from other repo" angle for the validator.

### 5.1 REPO_ROOT Resolution

| # | Case | File location | Expected REPO_ROOT |
|---|------|--------------|-------------------|
| 5.1.1 | Source repo path | `skills/reference-implementation-study/validate_gate.py` | 3 parents up = repo root |
| 5.1.2 | Consumer repo path | `.claude/skills/reference-implementation-study/validate_gate.py` | 3 parents up... but this resolves to `.claude/` level, NOT the consumer repo root |
| 5.1.3 | **Depth mismatch bug** | Consumer path is 4 levels deep (`.claude/skills/<skill>/validate_gate.py`) vs source path 3 levels (`skills/<skill>/validate_gate.py`) | **This is a potential bug**: `parents[3]` resolves differently in source vs consumer. Test must verify and document. |

### 5.2 Consumer-Side Gate Execution

| # | Case | Setup | Expected |
|---|------|-------|----------|
| 5.2.1 | G1 from consumer path | Full consumer repo structure with `.claude/skills/...` and `implementation/` at consumer root | Either passes (if REPO_ROOT resolves correctly) or fails with path error (if bug from 5.1.3) |
| 5.2.2 | G2 from consumer path | Consumer repo with `artifacts/<study>/baseline/` | Same resolution test |
| 5.2.3 | Import path setup | Consumer runs `python .claude/skills/reference-implementation-study/validate_gate.py study G1` | `sys.path` manipulation finds `implementation/` at consumer root |

---

## Test Execution & Verification

### Runner Script

`tests/run_all.sh` — top-level runner that:
1. Runs `tests/test_compose.sh` (compose.sh unit tests)
2. Runs `tests/test_structure.sh` (structural integrity)
3. Runs `python -m pytest tests/test_validate_gate.py -v` (gate validator unit tests)
4. Runs `python -m pytest tests/test_gate_consumer.py -v` (gate validator consumer-context tests)
5. Runs `tests/test_sync_workflow.sh` (full cross-repo sync simulation)
6. Reports pass/fail counts and exits non-zero if any test failed

### Test Fixtures

`tests/fixtures/` directory containing:
- `base-minimal.md` — minimal base with marker only
- `base-no-marker.md` — base without `<!-- INSERT_SECTIONS -->` marker
- `section-alpha.md` / `section-beta.md` — dummy sections for ordering tests
- `skill-valid/SKILL.md` — valid skill with proper front matter
- `skill-no-desc/SKILL.md` — skill missing `description:` field
- `skill-crlf/SKILL.md` — skill with Windows line endings
- `sync-default.yml` — copy of `defaults/.claude-sync.yml`
- `sync-one-section.yml` — config with one section enabled
- `sync-bad-section.yml` — config referencing nonexistent section
- `sync-no-sections-key.yml` — config without sections key
- `sync-crlf.yml` — config with CRLF endings
- `gate/` — subdirectory trees for each gate's pass/fail scenarios

### File Summary

| File | Component | Cases |
|------|-----------|-------|
| `tests/test_compose.sh` | compose.sh | 28 cases (1.1–1.5) |
| `tests/test_validate_gate.py` | validate_gate.py | 28 cases (2.1–2.6) |
| `tests/test_structure.sh` | Structural integrity | 14 cases (3.1–3.4) |
| `tests/test_sync_workflow.sh` | Cross-repo sync | 25 cases (4.1–4.6) |
| `tests/test_gate_consumer.py` | Gate in consumer context | 6 cases (5.1–5.2) |
| **Total** | | **101 cases** |

### Critical Finding: `validate_gate.py` REPO_ROOT Bug

Test case 5.1.3 identifies a likely path resolution bug. In the source repo, the script lives at depth 3 (`skills/<skill>/validate_gate.py`), so `parents[3]` correctly reaches the repo root. But after sync, it lives at depth 4 (`.claude/skills/<skill>/validate_gate.py`), so `parents[3]` would resolve to `.claude/` — not the consumer repo root. This should be confirmed and fixed.
