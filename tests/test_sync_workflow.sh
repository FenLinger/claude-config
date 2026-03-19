#!/usr/bin/env bash
# test_sync_workflow.sh — Cross-repo sync simulation tests (25 cases)
# Simulates the full sync lifecycle as experienced by a consumer repo.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
FIXTURES="$SCRIPT_DIR/fixtures"

PASS_COUNT=0
FAIL_COUNT=0
TOTAL=0

pass() {
  PASS_COUNT=$((PASS_COUNT + 1))
  TOTAL=$((TOTAL + 1))
  echo "  [+] PASS: $1"
}

fail() {
  FAIL_COUNT=$((FAIL_COUNT + 1))
  TOTAL=$((TOTAL + 1))
  echo "  [-] FAIL: $1"
  if [[ -n "${2:-}" ]]; then
    echo "           $2"
  fi
}

# Simulate the sync workflow steps as the GitHub Action would do them.
# $1 = consumer repo dir, $2 = claude-config source dir (defaults to REPO_ROOT)
run_sync() {
  local consumer="$1"
  local source="${2:-$REPO_ROOT}"

  # Step 1: Clone claude-config into _claude-config (simulate checkout)
  rm -rf "$consumer/_claude-config"
  cp -r "$source" "$consumer/_claude-config"
  # Remove .git from the copy to avoid nested git issues
  rm -rf "$consumer/_claude-config/.git"
  rm -rf "$consumer/_claude-config/tests"
  rm -rf "$consumer/_claude-config/plan"

  # Step 2: Sync skills
  rm -rf "$consumer/.claude/skills/"
  mkdir -p "$consumer/.claude/"
  cp -r "$consumer/_claude-config/skills/" "$consumer/.claude/skills/"

  # Step 3: Compose CLAUDE.md
  bash "$consumer/_claude-config/compose.sh" \
    --base "$consumer/_claude-config/claude-md/base.md" \
    --config "$consumer/.claude-sync.yml" \
    --sections-dir "$consumer/_claude-config/claude-md/sections/" \
    --skills-dir "$consumer/_claude-config/skills/" \
    --output "$consumer/CLAUDE.md" 2>/dev/null

  # Step 4: Clean up
  rm -rf "$consumer/_claude-config"
}

# Create a minimal consumer repo
setup_consumer() {
  local dir="$1"
  local config="${2:-$REPO_ROOT/defaults/.claude-sync.yml}"
  mkdir -p "$dir"
  cd "$dir" && git init --quiet 2>/dev/null
  cp "$config" "$dir/.claude-sync.yml"
  cd "$SCRIPT_DIR"
}

echo ""
echo "============================================================"
echo "  Component 4: Cross-Repo Sync Simulation"
echo "============================================================"
echo ""

# ===================================================================
# 4.1 Consumer Bootstrap
# ===================================================================
echo "--- 4.1 Consumer Bootstrap ---"

# 4.1.1 Init into empty repo
TMPDIR_TEST="$(mktemp -d)"
setup_consumer "$TMPDIR_TEST/consumer"
cp "$REPO_ROOT/.github/workflows/sync-claude-config.yml" "$TMPDIR_TEST/consumer/.github/workflows/" 2>/dev/null || {
  mkdir -p "$TMPDIR_TEST/consumer/.github/workflows"
  cp "$REPO_ROOT/.github/workflows/sync-claude-config.yml" "$TMPDIR_TEST/consumer/.github/workflows/"
}
if [[ -f "$TMPDIR_TEST/consumer/.github/workflows/sync-claude-config.yml" ]] \
    && [[ -f "$TMPDIR_TEST/consumer/.claude-sync.yml" ]]; then
  pass "4.1.1 Init into empty repo — workflow + config created"
else
  fail "4.1.1 Init into empty repo"
fi
rm -rf "$TMPDIR_TEST"

# 4.1.2 Init into repo with existing .github/
TMPDIR_TEST="$(mktemp -d)"
mkdir -p "$TMPDIR_TEST/consumer/.github/workflows"
echo "name: existing" > "$TMPDIR_TEST/consumer/.github/workflows/ci.yml"
setup_consumer "$TMPDIR_TEST/consumer"
cp "$REPO_ROOT/.github/workflows/sync-claude-config.yml" "$TMPDIR_TEST/consumer/.github/workflows/"
if [[ -f "$TMPDIR_TEST/consumer/.github/workflows/ci.yml" ]] \
    && [[ -f "$TMPDIR_TEST/consumer/.github/workflows/sync-claude-config.yml" ]]; then
  pass "4.1.2 Init with existing .github/ — both workflows present"
else
  fail "4.1.2 Init with existing .github/"
fi
rm -rf "$TMPDIR_TEST"

# 4.1.3 Default config content
TMPDIR_TEST="$(mktemp -d)"
setup_consumer "$TMPDIR_TEST/consumer"
if diff -q "$TMPDIR_TEST/consumer/.claude-sync.yml" "$REPO_ROOT/defaults/.claude-sync.yml" >/dev/null 2>&1; then
  pass "4.1.3 Default config matches defaults/.claude-sync.yml"
else
  fail "4.1.3 Default config content"
fi
rm -rf "$TMPDIR_TEST"

echo ""

# ===================================================================
# 4.2 Sync — Skill Distribution
# ===================================================================
echo "--- 4.2 Skill Distribution ---"

# 4.2.1 Fresh sync (no prior .claude/skills/)
TMPDIR_TEST="$(mktemp -d)"
setup_consumer "$TMPDIR_TEST/consumer"
run_sync "$TMPDIR_TEST/consumer"
skill_count=$(ls -d "$TMPDIR_TEST/consumer/.claude/skills"/*/ 2>/dev/null | wc -l)
if [[ $skill_count -eq 3 ]]; then
  pass "4.2.1 Fresh sync — 3 skill dirs created"
else
  fail "4.2.1 Fresh sync" "skill_count=$skill_count"
fi
rm -rf "$TMPDIR_TEST"

# 4.2.2 Update sync (stale skills exist)
TMPDIR_TEST="$(mktemp -d)"
setup_consumer "$TMPDIR_TEST/consumer"
mkdir -p "$TMPDIR_TEST/consumer/.claude/skills/old-skill"
echo "stale" > "$TMPDIR_TEST/consumer/.claude/skills/old-skill/SKILL.md"
run_sync "$TMPDIR_TEST/consumer"
if [[ ! -d "$TMPDIR_TEST/consumer/.claude/skills/old-skill" ]]; then
  pass "4.2.2 Update sync — stale skill removed"
else
  fail "4.2.2 Update sync — stale skill should be removed"
fi
rm -rf "$TMPDIR_TEST"

# 4.2.3 Sync preserves other .claude/ content
TMPDIR_TEST="$(mktemp -d)"
setup_consumer "$TMPDIR_TEST/consumer"
mkdir -p "$TMPDIR_TEST/consumer/.claude"
echo '{"theme":"dark"}' > "$TMPDIR_TEST/consumer/.claude/settings.json"
run_sync "$TMPDIR_TEST/consumer"
if [[ -f "$TMPDIR_TEST/consumer/.claude/settings.json" ]]; then
  pass "4.2.3 Sync preserves .claude/settings.json"
else
  fail "4.2.3 Sync preserves other .claude/ content"
fi
rm -rf "$TMPDIR_TEST"

# 4.2.4 All skill files present after sync
TMPDIR_TEST="$(mktemp -d)"
setup_consumer "$TMPDIR_TEST/consumer"
run_sync "$TMPDIR_TEST/consumer"
all_present=true
for skill in deep-research-survey reference-implementation-study source-fetch; do
  if [[ ! -f "$TMPDIR_TEST/consumer/.claude/skills/$skill/SKILL.md" ]]; then
    all_present=false
  fi
done
if $all_present; then
  pass "4.2.4 All skill SKILL.md files present after sync"
else
  fail "4.2.4 All skill files present"
fi
rm -rf "$TMPDIR_TEST"

# 4.2.5 Skill subdirectory structure preserved
TMPDIR_TEST="$(mktemp -d)"
setup_consumer "$TMPDIR_TEST/consumer"
run_sync "$TMPDIR_TEST/consumer"
if [[ -f "$TMPDIR_TEST/consumer/.claude/skills/deep-research-survey/templates/agent-brief.md" ]] \
    && [[ -f "$TMPDIR_TEST/consumer/.claude/skills/deep-research-survey/templates/preflight-checklist.md" ]] \
    && [[ -f "$TMPDIR_TEST/consumer/.claude/skills/reference-implementation-study/validate_gate.py" ]]; then
  pass "4.2.5 Subdirectory structure preserved (templates/, validate_gate.py)"
else
  fail "4.2.5 Subdirectory structure"
fi
rm -rf "$TMPDIR_TEST"

# 4.2.6 Permissions preserved (file content integrity)
TMPDIR_TEST="$(mktemp -d)"
setup_consumer "$TMPDIR_TEST/consumer"
run_sync "$TMPDIR_TEST/consumer"
if diff -q "$REPO_ROOT/skills/reference-implementation-study/validate_gate.py" \
    "$TMPDIR_TEST/consumer/.claude/skills/reference-implementation-study/validate_gate.py" >/dev/null 2>&1; then
  pass "4.2.6 validate_gate.py content integrity after sync"
else
  fail "4.2.6 File content integrity"
fi
rm -rf "$TMPDIR_TEST"

echo ""

# ===================================================================
# 4.3 Sync — CLAUDE.md Composition (Consumer Side)
# ===================================================================
echo "--- 4.3 CLAUDE.md Composition ---"

# 4.3.1 Default config (no sections)
TMPDIR_TEST="$(mktemp -d)"
setup_consumer "$TMPDIR_TEST/consumer"
run_sync "$TMPDIR_TEST/consumer"
content=$(cat "$TMPDIR_TEST/consumer/CLAUDE.md")
if echo "$content" | grep -q "Filter Design Project Guide" \
    && echo "$content" | grep -q "## Skills" \
    && ! echo "$content" | grep -q "Plan and Implementation Workflow"; then
  pass "4.3.1 Default config — base + skills, no sections"
else
  fail "4.3.1 Default config composition"
fi
rm -rf "$TMPDIR_TEST"

# 4.3.2 One section enabled
TMPDIR_TEST="$(mktemp -d)"
setup_consumer "$TMPDIR_TEST/consumer" "$FIXTURES/sync-one-section.yml"
run_sync "$TMPDIR_TEST/consumer"
content=$(cat "$TMPDIR_TEST/consumer/CLAUDE.md")
if echo "$content" | grep -q "Plan and Implementation Workflow"; then
  pass "4.3.2 One section enabled — plan-workflow inserted"
else
  fail "4.3.2 One section enabled"
fi
rm -rf "$TMPDIR_TEST"

# 4.3.3 Section ordering in CLAUDE.md
TMPDIR_TEST="$(mktemp -d)"
setup_consumer "$TMPDIR_TEST/consumer" "$FIXTURES/sync-one-section.yml"
run_sync "$TMPDIR_TEST/consumer"
plan_line=$(grep -n "Plan and Implementation" "$TMPDIR_TEST/consumer/CLAUDE.md" | head -1 | cut -d: -f1)
timeline_line=$(grep -n "Development Timeline" "$TMPDIR_TEST/consumer/CLAUDE.md" | head -1 | cut -d: -f1)
diagram_line=$(grep -n "Diagram Rules" "$TMPDIR_TEST/consumer/CLAUDE.md" | head -1 | cut -d: -f1)
if [[ -n "$plan_line" && -n "$timeline_line" && -n "$diagram_line" ]] \
    && [[ "$timeline_line" -lt "$plan_line" ]] \
    && [[ "$plan_line" -lt "$diagram_line" ]]; then
  pass "4.3.3 Section ordering — plan-workflow between Timeline and Diagrams"
else
  fail "4.3.3 Section ordering" "timeline=$timeline_line plan=$plan_line diagram=$diagram_line"
fi
rm -rf "$TMPDIR_TEST"

# 4.3.4 Skills section always at end
TMPDIR_TEST="$(mktemp -d)"
setup_consumer "$TMPDIR_TEST/consumer" "$FIXTURES/sync-one-section.yml"
run_sync "$TMPDIR_TEST/consumer"
skills_line=$(grep -n "^## Skills" "$TMPDIR_TEST/consumer/CLAUDE.md" | tail -1 | cut -d: -f1)
total_lines=$(wc -l < "$TMPDIR_TEST/consumer/CLAUDE.md")
# Skills should be in the last 40% of the file
threshold=$((total_lines * 60 / 100))
if [[ -n "$skills_line" && "$skills_line" -gt "$threshold" ]]; then
  pass "4.3.4 Skills section at end of CLAUDE.md"
else
  fail "4.3.4 Skills section position" "skills_line=$skills_line total=$total_lines threshold=$threshold"
fi
rm -rf "$TMPDIR_TEST"

# 4.3.5 Composed CLAUDE.md is self-consistent
TMPDIR_TEST="$(mktemp -d)"
setup_consumer "$TMPDIR_TEST/consumer"
run_sync "$TMPDIR_TEST/consumer"
content=$(cat "$TMPDIR_TEST/consumer/CLAUDE.md")
if ! echo "$content" | grep -q "<!-- INSERT_SECTIONS -->"; then
  pass "4.3.5 No dangling INSERT_SECTIONS marker"
else
  fail "4.3.5 Dangling marker found in composed CLAUDE.md"
fi
rm -rf "$TMPDIR_TEST"

# 4.3.6 All 3 skills listed
TMPDIR_TEST="$(mktemp -d)"
setup_consumer "$TMPDIR_TEST/consumer"
run_sync "$TMPDIR_TEST/consumer"
content=$(cat "$TMPDIR_TEST/consumer/CLAUDE.md")
if echo "$content" | grep -q "deep-research-survey" \
    && echo "$content" | grep -q "reference-implementation-study" \
    && echo "$content" | grep -q "source-fetch"; then
  pass "4.3.6 All 3 skills listed in CLAUDE.md"
else
  fail "4.3.6 All 3 skills listed"
fi
rm -rf "$TMPDIR_TEST"

echo ""

# ===================================================================
# 4.4 Sync — Diff Detection & PR Behavior
# ===================================================================
echo "--- 4.4 Diff Detection ---"

# 4.4.1 First sync produces changes
TMPDIR_TEST="$(mktemp -d)"
setup_consumer "$TMPDIR_TEST/consumer"
cd "$TMPDIR_TEST/consumer"
git add -A && git commit -m "init" --quiet 2>/dev/null
run_sync "$TMPDIR_TEST/consumer"
cd "$TMPDIR_TEST/consumer"
diff_output=$(git status --porcelain)
cd "$SCRIPT_DIR"
if [[ -n "$diff_output" ]]; then
  pass "4.4.1 First sync produces changes"
else
  fail "4.4.1 First sync produces changes"
fi
rm -rf "$TMPDIR_TEST"

# 4.4.2 Second identical sync produces no diff
TMPDIR_TEST="$(mktemp -d)"
setup_consumer "$TMPDIR_TEST/consumer"
run_sync "$TMPDIR_TEST/consumer"
cd "$TMPDIR_TEST/consumer"
git add -A && git commit -m "first sync" --quiet 2>/dev/null
cd "$SCRIPT_DIR"
run_sync "$TMPDIR_TEST/consumer"
cd "$TMPDIR_TEST/consumer"
diff_output=$(git diff HEAD)
cd "$SCRIPT_DIR"
if [[ -z "$diff_output" ]]; then
  pass "4.4.2 Second sync — no spurious changes"
else
  fail "4.4.2 Second sync idempotent" "diff not empty"
fi
rm -rf "$TMPDIR_TEST"

# 4.4.3 Upstream skill change propagates
TMPDIR_TEST="$(mktemp -d)"
setup_consumer "$TMPDIR_TEST/consumer"
# First sync
run_sync "$TMPDIR_TEST/consumer"
cd "$TMPDIR_TEST/consumer"
git add -A && git commit -m "first sync" --quiet 2>/dev/null
cd "$SCRIPT_DIR"
# Modify a skill in a temp copy of claude-config
cp -r "$REPO_ROOT" "$TMPDIR_TEST/modified-config"
echo "# Modified" >> "$TMPDIR_TEST/modified-config/skills/source-fetch/SKILL.md"
# Second sync from modified source
run_sync "$TMPDIR_TEST/consumer" "$TMPDIR_TEST/modified-config"
cd "$TMPDIR_TEST/consumer"
diff_output=$(git diff HEAD)
cd "$SCRIPT_DIR"
if echo "$diff_output" | grep -q "Modified"; then
  pass "4.4.3 Upstream skill change propagates"
else
  fail "4.4.3 Upstream skill change"
fi
rm -rf "$TMPDIR_TEST"

# 4.4.4 Upstream section change propagates
TMPDIR_TEST="$(mktemp -d)"
setup_consumer "$TMPDIR_TEST/consumer" "$FIXTURES/sync-one-section.yml"
run_sync "$TMPDIR_TEST/consumer"
cd "$TMPDIR_TEST/consumer"
git add -A && git commit -m "first sync" --quiet 2>/dev/null
cd "$SCRIPT_DIR"
# Modify the section
cp -r "$REPO_ROOT" "$TMPDIR_TEST/modified-config"
echo "- Modified rule added" >> "$TMPDIR_TEST/modified-config/claude-md/sections/plan-workflow.md"
run_sync "$TMPDIR_TEST/consumer" "$TMPDIR_TEST/modified-config"
cd "$TMPDIR_TEST/consumer"
diff_output=$(git diff HEAD)
cd "$SCRIPT_DIR"
if echo "$diff_output" | grep -q "Modified rule"; then
  pass "4.4.4 Upstream section change propagates"
else
  fail "4.4.4 Upstream section change"
fi
rm -rf "$TMPDIR_TEST"

# 4.4.5 New skill added upstream
TMPDIR_TEST="$(mktemp -d)"
setup_consumer "$TMPDIR_TEST/consumer"
run_sync "$TMPDIR_TEST/consumer"
cd "$TMPDIR_TEST/consumer"
git add -A && git commit -m "first sync" --quiet 2>/dev/null
cd "$SCRIPT_DIR"
# Add new skill
cp -r "$REPO_ROOT" "$TMPDIR_TEST/modified-config"
mkdir -p "$TMPDIR_TEST/modified-config/skills/new-skill"
cat > "$TMPDIR_TEST/modified-config/skills/new-skill/SKILL.md" <<'MD'
---
name: new-skill
description: A brand new skill
---
# New Skill
MD
run_sync "$TMPDIR_TEST/consumer" "$TMPDIR_TEST/modified-config"
if [[ -f "$TMPDIR_TEST/consumer/.claude/skills/new-skill/SKILL.md" ]] \
    && grep -q "new-skill" "$TMPDIR_TEST/consumer/CLAUDE.md"; then
  pass "4.4.5 New skill added upstream — appears in consumer"
else
  fail "4.4.5 New skill added upstream"
fi
rm -rf "$TMPDIR_TEST"

# 4.4.6 Skill removed upstream
TMPDIR_TEST="$(mktemp -d)"
setup_consumer "$TMPDIR_TEST/consumer"
run_sync "$TMPDIR_TEST/consumer"
cd "$TMPDIR_TEST/consumer"
git add -A && git commit -m "first sync" --quiet 2>/dev/null
cd "$SCRIPT_DIR"
# Remove source-fetch skill
cp -r "$REPO_ROOT" "$TMPDIR_TEST/modified-config"
rm -rf "$TMPDIR_TEST/modified-config/skills/source-fetch"
run_sync "$TMPDIR_TEST/consumer" "$TMPDIR_TEST/modified-config"
if [[ ! -d "$TMPDIR_TEST/consumer/.claude/skills/source-fetch" ]]; then
  pass "4.4.6 Skill removed upstream — removed from consumer"
else
  fail "4.4.6 Skill removed upstream"
fi
rm -rf "$TMPDIR_TEST"

echo ""

# ===================================================================
# 4.5 Sync — Consumer Config Variations
# ===================================================================
echo "--- 4.5 Config Variations ---"

# 4.5.1 Default config from defaults/
TMPDIR_TEST="$(mktemp -d)"
setup_consumer "$TMPDIR_TEST/consumer"
run_sync "$TMPDIR_TEST/consumer"
if [[ -f "$TMPDIR_TEST/consumer/CLAUDE.md" ]] && grep -q "## Skills" "$TMPDIR_TEST/consumer/CLAUDE.md"; then
  pass "4.5.1 Default config sync succeeds"
else
  fail "4.5.1 Default config sync"
fi
rm -rf "$TMPDIR_TEST"

# 4.5.2 Config with uncommented section
TMPDIR_TEST="$(mktemp -d)"
setup_consumer "$TMPDIR_TEST/consumer" "$FIXTURES/sync-one-section.yml"
run_sync "$TMPDIR_TEST/consumer"
if grep -q "Plan and Implementation Workflow" "$TMPDIR_TEST/consumer/CLAUDE.md"; then
  pass "4.5.2 Config with section enabled"
else
  fail "4.5.2 Config with section enabled"
fi
rm -rf "$TMPDIR_TEST"

# 4.5.3 Config with nonexistent section
TMPDIR_TEST="$(mktemp -d)"
setup_consumer "$TMPDIR_TEST/consumer" "$FIXTURES/sync-bad-section.yml"
stderr=$(run_sync "$TMPDIR_TEST/consumer" 2>&1 >/dev/null) || true
if [[ -f "$TMPDIR_TEST/consumer/CLAUDE.md" ]]; then
  pass "4.5.3 Nonexistent section — CLAUDE.md still composed"
else
  fail "4.5.3 Nonexistent section"
fi
rm -rf "$TMPDIR_TEST"

# 4.5.4 Config with CRLF line endings
TMPDIR_TEST="$(mktemp -d)"
setup_consumer "$TMPDIR_TEST/consumer" "$FIXTURES/sync-crlf.yml"
run_sync "$TMPDIR_TEST/consumer"
if grep -q "Plan and Implementation Workflow" "$TMPDIR_TEST/consumer/CLAUDE.md"; then
  pass "4.5.4 CRLF config parsed correctly"
else
  fail "4.5.4 CRLF config"
fi
rm -rf "$TMPDIR_TEST"

# 4.5.5 Minimal config (sections key absent)
TMPDIR_TEST="$(mktemp -d)"
setup_consumer "$TMPDIR_TEST/consumer" "$FIXTURES/sync-no-sections-key.yml"
run_sync "$TMPDIR_TEST/consumer"
if [[ -f "$TMPDIR_TEST/consumer/CLAUDE.md" ]] && ! grep -q "Plan and Implementation" "$TMPDIR_TEST/consumer/CLAUDE.md"; then
  pass "4.5.5 Minimal config — no sections inserted"
else
  fail "4.5.5 Minimal config"
fi
rm -rf "$TMPDIR_TEST"

echo ""

# ===================================================================
# 4.6 Sync — Idempotency & Edge Cases
# ===================================================================
echo "--- 4.6 Idempotency & Edge Cases ---"

# 4.6.1 Triple sync idempotent
TMPDIR_TEST="$(mktemp -d)"
setup_consumer "$TMPDIR_TEST/consumer"
run_sync "$TMPDIR_TEST/consumer"
cd "$TMPDIR_TEST/consumer"
git add -A && git commit -m "first" --quiet 2>/dev/null
cd "$SCRIPT_DIR"
run_sync "$TMPDIR_TEST/consumer"
cd "$TMPDIR_TEST/consumer"
diff2=$(git diff HEAD)
cd "$SCRIPT_DIR"
run_sync "$TMPDIR_TEST/consumer"
cd "$TMPDIR_TEST/consumer"
diff3=$(git diff HEAD)
cd "$SCRIPT_DIR"
if [[ -z "$diff2" && -z "$diff3" ]]; then
  pass "4.6.1 Triple sync idempotent"
else
  fail "4.6.1 Triple sync idempotent"
fi
rm -rf "$TMPDIR_TEST"

# 4.6.2 Consumer CLAUDE.md has local edits — overwritten
TMPDIR_TEST="$(mktemp -d)"
setup_consumer "$TMPDIR_TEST/consumer"
run_sync "$TMPDIR_TEST/consumer"
echo "LOCAL EDIT" >> "$TMPDIR_TEST/consumer/CLAUDE.md"
run_sync "$TMPDIR_TEST/consumer"
if ! grep -q "LOCAL EDIT" "$TMPDIR_TEST/consumer/CLAUDE.md"; then
  pass "4.6.2 Local CLAUDE.md edits overwritten by sync"
else
  fail "4.6.2 Local edits should be overwritten"
fi
rm -rf "$TMPDIR_TEST"

# 4.6.3 Consumer has local files in .claude/skills/ — deleted
TMPDIR_TEST="$(mktemp -d)"
setup_consumer "$TMPDIR_TEST/consumer"
run_sync "$TMPDIR_TEST/consumer"
mkdir -p "$TMPDIR_TEST/consumer/.claude/skills/custom-skill"
echo "custom" > "$TMPDIR_TEST/consumer/.claude/skills/custom-skill/SKILL.md"
run_sync "$TMPDIR_TEST/consumer"
if [[ ! -d "$TMPDIR_TEST/consumer/.claude/skills/custom-skill" ]]; then
  pass "4.6.3 Custom skill removed — only canonical skills remain"
else
  fail "4.6.3 Custom skill should be removed"
fi
rm -rf "$TMPDIR_TEST"

# 4.6.4 _claude-config cleanup
TMPDIR_TEST="$(mktemp -d)"
setup_consumer "$TMPDIR_TEST/consumer"
run_sync "$TMPDIR_TEST/consumer"
if [[ ! -d "$TMPDIR_TEST/consumer/_claude-config" ]]; then
  pass "4.6.4 _claude-config cleaned up after sync"
else
  fail "4.6.4 _claude-config cleanup"
fi
rm -rf "$TMPDIR_TEST"

echo ""
echo "============================================================"
echo "  Sync Workflow: $PASS_COUNT passed, $FAIL_COUNT failed (of $TOTAL)"
echo "============================================================"
echo ""

exit $FAIL_COUNT
