#!/usr/bin/env bash
# test_compose.sh — Tests for compose.sh (35 cases)
# Covers: argument parsing, YAML section parsing, section insertion,
#         skills section generation, and end-to-end composition.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
COMPOSE="$REPO_ROOT/compose.sh"
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

setup_tmp() {
  TMPDIR_TEST="$(mktemp -d)"
}

teardown_tmp() {
  rm -rf "$TMPDIR_TEST"
}

echo ""
echo "============================================================"
echo "  Component 1: compose.sh — CLAUDE.md Assembly Script"
echo "============================================================"
echo ""

# ===================================================================
# 1.1 Argument Parsing
# ===================================================================
echo "--- 1.1 Argument Parsing ---"

# 1.1.1 All required args provided
setup_tmp
out="$TMPDIR_TEST/out.md"
if bash "$COMPOSE" \
    --base "$FIXTURES/base-minimal.md" \
    --config "$FIXTURES/sync-default.yml" \
    --sections-dir "$FIXTURES" \
    --output "$out" 2>/dev/null && [[ -f "$out" ]]; then
  pass "1.1.1 All required args provided"
else
  fail "1.1.1 All required args provided"
fi
teardown_tmp

# 1.1.2 Missing --base
setup_tmp
rc=0
stderr=$(bash "$COMPOSE" \
    --config "$FIXTURES/sync-default.yml" \
    --sections-dir "$FIXTURES" \
    --output "$TMPDIR_TEST/out.md" 2>&1 1>/dev/null) || rc=$?
if [[ $rc -ne 0 ]] && echo "$stderr" | grep -qi "base"; then
  pass "1.1.2 Missing --base"
else
  fail "1.1.2 Missing --base" "rc=$rc stderr=$stderr"
fi
teardown_tmp

# 1.1.3 Missing --config
setup_tmp
rc=0
stderr=$(bash "$COMPOSE" \
    --base "$FIXTURES/base-minimal.md" \
    --sections-dir "$FIXTURES" \
    --output "$TMPDIR_TEST/out.md" 2>&1 1>/dev/null) || rc=$?
if [[ $rc -ne 0 ]] && echo "$stderr" | grep -qi "config"; then
  pass "1.1.3 Missing --config"
else
  fail "1.1.3 Missing --config" "rc=$rc stderr=$stderr"
fi
teardown_tmp

# 1.1.4 Missing --sections-dir
setup_tmp
rc=0
stderr=$(bash "$COMPOSE" \
    --base "$FIXTURES/base-minimal.md" \
    --config "$FIXTURES/sync-default.yml" \
    --output "$TMPDIR_TEST/out.md" 2>&1 1>/dev/null) || rc=$?
if [[ $rc -ne 0 ]] && echo "$stderr" | grep -qi "sections-dir"; then
  pass "1.1.4 Missing --sections-dir"
else
  fail "1.1.4 Missing --sections-dir" "rc=$rc stderr=$stderr"
fi
teardown_tmp

# 1.1.5 Missing --output
setup_tmp
rc=0
stderr=$(bash "$COMPOSE" \
    --base "$FIXTURES/base-minimal.md" \
    --config "$FIXTURES/sync-default.yml" \
    --sections-dir "$FIXTURES" 2>&1 1>/dev/null) || rc=$?
if [[ $rc -ne 0 ]] && echo "$stderr" | grep -qi "output"; then
  pass "1.1.5 Missing --output"
else
  fail "1.1.5 Missing --output" "rc=$rc stderr=$stderr"
fi
teardown_tmp

# 1.1.6 Unknown option
setup_tmp
rc=0
stderr=$(bash "$COMPOSE" --bogus foo 2>&1 1>/dev/null) || rc=$?
if [[ $rc -ne 0 ]] && echo "$stderr" | grep -qi "Unknown option"; then
  pass "1.1.6 Unknown option"
else
  fail "1.1.6 Unknown option" "rc=$rc stderr=$stderr"
fi
teardown_tmp

# 1.1.7 --skills-dir is optional
setup_tmp
out="$TMPDIR_TEST/out.md"
if bash "$COMPOSE" \
    --base "$FIXTURES/base-minimal.md" \
    --config "$FIXTURES/sync-default.yml" \
    --sections-dir "$FIXTURES" \
    --output "$out" 2>/dev/null; then
  content=$(cat "$out")
  if ! echo "$content" | grep -q "## Skills"; then
    pass "1.1.7 --skills-dir is optional (no Skills section)"
  else
    fail "1.1.7 --skills-dir is optional" "Skills section found when --skills-dir omitted"
  fi
else
  fail "1.1.7 --skills-dir is optional" "compose.sh failed"
fi
teardown_tmp

echo ""

# ===================================================================
# 1.2 YAML Section Parsing
# ===================================================================
echo "--- 1.2 YAML Section Parsing ---"

# 1.2.1 Single section
setup_tmp
cat > "$TMPDIR_TEST/config.yml" <<'YAML'
claude_md:
  sections:
    - plan-workflow
YAML
out="$TMPDIR_TEST/out.md"
bash "$COMPOSE" \
    --base "$FIXTURES/base-minimal.md" \
    --config "$TMPDIR_TEST/config.yml" \
    --sections-dir "$REPO_ROOT/claude-md/sections" \
    --output "$out" 2>/dev/null
if grep -q "Plan and Implementation Workflow" "$out"; then
  pass "1.2.1 Single section parsed"
else
  fail "1.2.1 Single section parsed"
fi
teardown_tmp

# 1.2.2 Multiple sections
setup_tmp
cat > "$TMPDIR_TEST/config.yml" <<'YAML'
claude_md:
  sections:
    - alpha
    - beta
YAML
out="$TMPDIR_TEST/out.md"
bash "$COMPOSE" \
    --base "$FIXTURES/base-minimal.md" \
    --config "$TMPDIR_TEST/config.yml" \
    --sections-dir "$FIXTURES" \
    --output "$out" 2>/dev/null
if grep -q "Alpha" "$out" && grep -q "Beta" "$out"; then
  pass "1.2.2 Multiple sections parsed"
else
  fail "1.2.2 Multiple sections parsed"
fi
teardown_tmp

# 1.2.3 Empty list (inline)
setup_tmp
cat > "$TMPDIR_TEST/config.yml" <<'YAML'
claude_md:
  sections: []
YAML
out="$TMPDIR_TEST/out.md"
bash "$COMPOSE" \
    --base "$FIXTURES/base-minimal.md" \
    --config "$TMPDIR_TEST/config.yml" \
    --sections-dir "$FIXTURES" \
    --output "$out" 2>/dev/null
if ! grep -q "Alpha\|Beta\|plan-workflow" "$out"; then
  pass "1.2.3 Empty list (inline) — no sections inserted"
else
  fail "1.2.3 Empty list (inline)"
fi
teardown_tmp

# 1.2.4 No sections key
setup_tmp
cat > "$TMPDIR_TEST/config.yml" <<'YAML'
skills: all
claude_md:
  base: true
YAML
out="$TMPDIR_TEST/out.md"
bash "$COMPOSE" \
    --base "$FIXTURES/base-minimal.md" \
    --config "$TMPDIR_TEST/config.yml" \
    --sections-dir "$FIXTURES" \
    --output "$out" 2>/dev/null
if ! grep -q "Alpha\|Beta\|plan-workflow" "$out"; then
  pass "1.2.4 No sections key — no sections inserted"
else
  fail "1.2.4 No sections key"
fi
teardown_tmp

# 1.2.5 Windows CRLF line endings
setup_tmp
out="$TMPDIR_TEST/out.md"
bash "$COMPOSE" \
    --base "$FIXTURES/base-minimal.md" \
    --config "$FIXTURES/sync-crlf.yml" \
    --sections-dir "$REPO_ROOT/claude-md/sections" \
    --output "$out" 2>/dev/null
if grep -q "Plan and Implementation Workflow" "$out"; then
  pass "1.2.5 CRLF line endings parsed correctly"
else
  fail "1.2.5 CRLF line endings parsed correctly"
fi
teardown_tmp

# 1.2.6 Sections followed by other YAML keys
setup_tmp
cat > "$TMPDIR_TEST/config.yml" <<'YAML'
claude_md:
  sections:
    - alpha
  other_key: value
YAML
out="$TMPDIR_TEST/out.md"
bash "$COMPOSE" \
    --base "$FIXTURES/base-minimal.md" \
    --config "$TMPDIR_TEST/config.yml" \
    --sections-dir "$FIXTURES" \
    --output "$out" 2>/dev/null
if grep -q "Alpha" "$out" && ! grep -q "other_key" "$out"; then
  pass "1.2.6 Sections followed by other YAML keys"
else
  fail "1.2.6 Sections followed by other YAML keys"
fi
teardown_tmp

# 1.2.7 Comment before list items
setup_tmp
cat > "$TMPDIR_TEST/config.yml" <<'YAML'
claude_md:
  sections:
  # this is a comment
    - plan-workflow
YAML
out="$TMPDIR_TEST/out.md"
bash "$COMPOSE" \
    --base "$FIXTURES/base-minimal.md" \
    --config "$TMPDIR_TEST/config.yml" \
    --sections-dir "$REPO_ROOT/claude-md/sections" \
    --output "$out" 2>/dev/null
if grep -q "Plan and Implementation Workflow" "$out"; then
  pass "1.2.7 Comment before list items — skipped correctly"
else
  fail "1.2.7 Comment before list items"
fi
teardown_tmp

# 1.2.8 Comment between list items
setup_tmp
cat > "$TMPDIR_TEST/config.yml" <<'YAML'
claude_md:
  sections:
    - alpha
    # a comment between items
    - beta
YAML
out="$TMPDIR_TEST/out.md"
bash "$COMPOSE" \
    --base "$FIXTURES/base-minimal.md" \
    --config "$TMPDIR_TEST/config.yml" \
    --sections-dir "$FIXTURES" \
    --output "$out" 2>/dev/null
if grep -q "Alpha" "$out" && grep -q "Beta" "$out"; then
  pass "1.2.8 Comment between list items — both sections included"
else
  fail "1.2.8 Comment between list items"
fi
teardown_tmp

# 1.2.9 Blank line within sections list
setup_tmp
cat > "$TMPDIR_TEST/config.yml" <<'YAML'
claude_md:
  sections:
    - alpha

    - beta
YAML
out="$TMPDIR_TEST/out.md"
bash "$COMPOSE" \
    --base "$FIXTURES/base-minimal.md" \
    --config "$TMPDIR_TEST/config.yml" \
    --sections-dir "$FIXTURES" \
    --output "$out" 2>/dev/null
if grep -q "Alpha" "$out" && grep -q "Beta" "$out"; then
  pass "1.2.9 Blank line within sections list — both sections included"
else
  fail "1.2.9 Blank line within sections list"
fi
teardown_tmp

echo ""

# ===================================================================
# 1.3 Section Insertion (Marker Replacement)
# ===================================================================
echo "--- 1.3 Section Insertion ---"

# 1.3.1 Marker present, one section
setup_tmp
cat > "$TMPDIR_TEST/config.yml" <<'YAML'
sections:
  - alpha
YAML
out="$TMPDIR_TEST/out.md"
bash "$COMPOSE" \
    --base "$FIXTURES/base-minimal.md" \
    --config "$TMPDIR_TEST/config.yml" \
    --sections-dir "$FIXTURES" \
    --output "$out" 2>/dev/null
if grep -q "Alpha Section" "$out" && ! grep -q "INSERT_SECTIONS" "$out"; then
  pass "1.3.1 Marker replaced with section content"
else
  fail "1.3.1 Marker replaced with section content"
fi
teardown_tmp

# 1.3.2 Marker present, no sections
setup_tmp
cat > "$TMPDIR_TEST/config.yml" <<'YAML'
sections: []
YAML
out="$TMPDIR_TEST/out.md"
bash "$COMPOSE" \
    --base "$FIXTURES/base-minimal.md" \
    --config "$TMPDIR_TEST/config.yml" \
    --sections-dir "$FIXTURES" \
    --output "$out" 2>/dev/null
if ! grep -q "INSERT_SECTIONS" "$out"; then
  pass "1.3.2 Marker removed with no sections"
else
  fail "1.3.2 Marker removed with no sections"
fi
teardown_tmp

# 1.3.3 No marker in base
setup_tmp
cat > "$TMPDIR_TEST/config.yml" <<'YAML'
sections:
  - alpha
YAML
out="$TMPDIR_TEST/out.md"
bash "$COMPOSE" \
    --base "$FIXTURES/base-no-marker.md" \
    --config "$TMPDIR_TEST/config.yml" \
    --sections-dir "$FIXTURES" \
    --output "$out" 2>/dev/null
content=$(cat "$out")
if echo "$content" | grep -q "Base Without Marker" && ! echo "$content" | grep -q "Alpha Section"; then
  pass "1.3.3 No marker — section silently dropped, base passes through"
else
  fail "1.3.3 No marker — section silently dropped"
fi
teardown_tmp

# 1.3.4 Section file missing
setup_tmp
cat > "$TMPDIR_TEST/config.yml" <<'YAML'
sections:
  - nonexistent-section
YAML
out="$TMPDIR_TEST/out.md"
stderr=$(bash "$COMPOSE" \
    --base "$FIXTURES/base-minimal.md" \
    --config "$TMPDIR_TEST/config.yml" \
    --sections-dir "$FIXTURES" \
    --output "$out" 2>&1 >/dev/null)
if [[ -f "$out" ]] && echo "$stderr" | grep -qi "Warning"; then
  pass "1.3.4 Missing section file — warning, continues"
else
  fail "1.3.4 Missing section file" "stderr=$stderr"
fi
teardown_tmp

# 1.3.5 Multiple sections ordering
setup_tmp
cat > "$TMPDIR_TEST/config.yml" <<'YAML'
sections:
  - alpha
  - beta
YAML
out="$TMPDIR_TEST/out.md"
bash "$COMPOSE" \
    --base "$FIXTURES/base-minimal.md" \
    --config "$TMPDIR_TEST/config.yml" \
    --sections-dir "$FIXTURES" \
    --output "$out" 2>/dev/null
alpha_line=$(grep -n "Alpha" "$out" | head -1 | cut -d: -f1)
beta_line=$(grep -n "Beta" "$out" | head -1 | cut -d: -f1)
if [[ -n "$alpha_line" && -n "$beta_line" && "$alpha_line" -lt "$beta_line" ]]; then
  pass "1.3.5 Multiple sections — alpha before beta"
else
  fail "1.3.5 Multiple sections ordering" "alpha=$alpha_line beta=$beta_line"
fi
teardown_tmp

# 1.3.6 Section with trailing newlines
setup_tmp
cat > "$TMPDIR_TEST/config.yml" <<'YAML'
sections:
  - trailing
YAML
mkdir -p "$TMPDIR_TEST/sections"
printf "## Trailing Section\n\nContent.\n\n\n\n" > "$TMPDIR_TEST/sections/trailing.md"
out="$TMPDIR_TEST/out.md"
bash "$COMPOSE" \
    --base "$FIXTURES/base-minimal.md" \
    --config "$TMPDIR_TEST/config.yml" \
    --sections-dir "$TMPDIR_TEST/sections" \
    --output "$out" 2>/dev/null
if grep -q "Trailing Section" "$out"; then
  pass "1.3.6 Section with trailing newlines handled"
else
  fail "1.3.6 Section with trailing newlines"
fi
teardown_tmp

echo ""

# ===================================================================
# 1.4 Skills Section Generation
# ===================================================================
echo "--- 1.4 Skills Section Generation ---"

# 1.4.1 Single skill directory
setup_tmp
mkdir -p "$TMPDIR_TEST/skills/my-skill"
cat > "$TMPDIR_TEST/skills/my-skill/SKILL.md" <<'MD'
---
name: my-skill
description: Test skill description
---
# My Skill
MD
out="$TMPDIR_TEST/out.md"
bash "$COMPOSE" \
    --base "$FIXTURES/base-minimal.md" \
    --config "$FIXTURES/sync-default.yml" \
    --sections-dir "$FIXTURES" \
    --skills-dir "$TMPDIR_TEST/skills" \
    --output "$out" 2>/dev/null
content=$(cat "$out")
if echo "$content" | grep -q "## Skills" && echo "$content" | grep -q "my-skill.*Test skill description"; then
  pass "1.4.1 Single skill directory"
else
  fail "1.4.1 Single skill directory"
fi
teardown_tmp

# 1.4.2 Multiple skill directories
setup_tmp
for s in skill-a skill-b skill-c; do
  mkdir -p "$TMPDIR_TEST/skills/$s"
  cat > "$TMPDIR_TEST/skills/$s/SKILL.md" <<MD
---
name: $s
description: Description for $s
---
# $s
MD
done
out="$TMPDIR_TEST/out.md"
bash "$COMPOSE" \
    --base "$FIXTURES/base-minimal.md" \
    --config "$FIXTURES/sync-default.yml" \
    --sections-dir "$FIXTURES" \
    --skills-dir "$TMPDIR_TEST/skills" \
    --output "$out" 2>/dev/null
content=$(cat "$out")
count=$(echo "$content" | grep -c "Description for skill-")
if [[ $count -eq 3 ]]; then
  pass "1.4.2 Multiple skill directories (3 listed)"
else
  fail "1.4.2 Multiple skill directories" "count=$count"
fi
teardown_tmp

# 1.4.3 Skill missing description
setup_tmp
out="$TMPDIR_TEST/out.md"
mkdir -p "$TMPDIR_TEST/skills"
cp -r "$FIXTURES/skill-no-desc" "$TMPDIR_TEST/skills/"
bash "$COMPOSE" \
    --base "$FIXTURES/base-minimal.md" \
    --config "$FIXTURES/sync-default.yml" \
    --sections-dir "$FIXTURES" \
    --skills-dir "$TMPDIR_TEST/skills" \
    --output "$out" 2>/dev/null
if grep -q "(no description)" "$out"; then
  pass "1.4.3 Skill missing description — falls back to (no description)"
else
  fail "1.4.3 Skill missing description"
fi
teardown_tmp

# 1.4.4 Skill directory without SKILL.md
setup_tmp
mkdir -p "$TMPDIR_TEST/skills/orphan"
mkdir -p "$TMPDIR_TEST/skills/valid-skill"
cat > "$TMPDIR_TEST/skills/valid-skill/SKILL.md" <<'MD'
---
name: valid-skill
description: Valid one
---
# Valid
MD
out="$TMPDIR_TEST/out.md"
bash "$COMPOSE" \
    --base "$FIXTURES/base-minimal.md" \
    --config "$FIXTURES/sync-default.yml" \
    --sections-dir "$FIXTURES" \
    --skills-dir "$TMPDIR_TEST/skills" \
    --output "$out" 2>/dev/null
if grep -q "valid-skill" "$out" && ! grep -q "orphan" "$out"; then
  pass "1.4.4 Skill directory without SKILL.md — silently skipped"
else
  fail "1.4.4 Skill directory without SKILL.md"
fi
teardown_tmp

# 1.4.5 SKILL.md with Windows CRLF
setup_tmp
mkdir -p "$TMPDIR_TEST/skills"
cp -r "$FIXTURES/skill-crlf" "$TMPDIR_TEST/skills/"
out="$TMPDIR_TEST/out.md"
bash "$COMPOSE" \
    --base "$FIXTURES/base-minimal.md" \
    --config "$FIXTURES/sync-default.yml" \
    --sections-dir "$FIXTURES" \
    --skills-dir "$TMPDIR_TEST/skills" \
    --output "$out" 2>/dev/null
if grep -q "A CRLF skill for testing" "$out"; then
  pass "1.4.5 SKILL.md with CRLF — description extracted"
else
  fail "1.4.5 SKILL.md with CRLF"
fi
teardown_tmp

# 1.4.6 --skills-dir omitted
setup_tmp
out="$TMPDIR_TEST/out.md"
bash "$COMPOSE" \
    --base "$FIXTURES/base-minimal.md" \
    --config "$FIXTURES/sync-default.yml" \
    --sections-dir "$FIXTURES" \
    --output "$out" 2>/dev/null
if ! grep -q "## Skills" "$out"; then
  pass "1.4.6 --skills-dir omitted — no Skills section"
else
  fail "1.4.6 --skills-dir omitted"
fi
teardown_tmp

# 1.4.7 Skills path references
setup_tmp
mkdir -p "$TMPDIR_TEST/skills/my-skill"
cat > "$TMPDIR_TEST/skills/my-skill/SKILL.md" <<'MD'
---
name: my-skill
description: Test
---
# My Skill
MD
out="$TMPDIR_TEST/out.md"
bash "$COMPOSE" \
    --base "$FIXTURES/base-minimal.md" \
    --config "$FIXTURES/sync-default.yml" \
    --sections-dir "$FIXTURES" \
    --skills-dir "$TMPDIR_TEST/skills" \
    --output "$out" 2>/dev/null
if grep -q ".claude/skills/my-skill/SKILL.md" "$out"; then
  pass "1.4.7 Skills path references consumer-side path"
else
  fail "1.4.7 Skills path references"
fi
teardown_tmp

# 1.4.8 Skill Usage Rules block
setup_tmp
mkdir -p "$TMPDIR_TEST/skills/dummy"
cat > "$TMPDIR_TEST/skills/dummy/SKILL.md" <<'MD'
---
name: dummy
description: Dummy
---
# Dummy
MD
out="$TMPDIR_TEST/out.md"
bash "$COMPOSE" \
    --base "$FIXTURES/base-minimal.md" \
    --config "$FIXTURES/sync-default.yml" \
    --sections-dir "$FIXTURES" \
    --skills-dir "$TMPDIR_TEST/skills" \
    --output "$out" 2>/dev/null
rules_count=0
for rule_text in \
    "Check " \
    "Read only enough" \
    "Resolve relative paths" \
    "Load only the specific" \
    "Reuse provided scripts" \
    "smallest set that covers" \
    "cannot be used cleanly" \
    "Keep context tight"; do
  if grep -qF "$rule_text" "$out"; then
    rules_count=$((rules_count + 1))
  fi
done
if [[ $rules_count -eq 8 ]]; then
  pass "1.4.8 All 8 Skill Usage Rules present"
else
  fail "1.4.8 Skill Usage Rules" "found $rules_count/8"
fi
teardown_tmp

echo ""

# ===================================================================
# 1.5 End-to-End Composition
# ===================================================================
echo "--- 1.5 End-to-End Composition ---"

# 1.5.1 Full golden-path
setup_tmp
out="$TMPDIR_TEST/out.md"
bash "$COMPOSE" \
    --base "$REPO_ROOT/claude-md/base.md" \
    --config "$FIXTURES/sync-default.yml" \
    --sections-dir "$REPO_ROOT/claude-md/sections" \
    --skills-dir "$REPO_ROOT/skills" \
    --output "$out" 2>/dev/null
content=$(cat "$out")
if echo "$content" | grep -q "Filter Design Project Guide" \
    && echo "$content" | grep -q "## Skills" \
    && echo "$content" | grep -q "deep-research-survey" \
    && echo "$content" | grep -q "reference-implementation-study" \
    && echo "$content" | grep -q "source-fetch"; then
  pass "1.5.1 Full golden-path composition"
else
  fail "1.5.1 Full golden-path composition"
fi
teardown_tmp

# 1.5.2 Base only, no sections, no skills
setup_tmp
out="$TMPDIR_TEST/out.md"
bash "$COMPOSE" \
    --base "$FIXTURES/base-minimal.md" \
    --config "$FIXTURES/sync-default.yml" \
    --sections-dir "$FIXTURES" \
    --output "$out" 2>/dev/null
content=$(cat "$out")
if echo "$content" | grep -q "# Minimal Base" \
    && echo "$content" | grep -q "## Footer" \
    && ! echo "$content" | grep -q "## Skills" \
    && ! echo "$content" | grep -q "INSERT_SECTIONS"; then
  pass "1.5.2 Base only — no sections, no skills"
else
  fail "1.5.2 Base only"
fi
teardown_tmp

# 1.5.3 Output file path with spaces
setup_tmp
mkdir -p "$TMPDIR_TEST/my dir"
out="$TMPDIR_TEST/my dir/CLAUDE.md"
bash "$COMPOSE" \
    --base "$FIXTURES/base-minimal.md" \
    --config "$FIXTURES/sync-default.yml" \
    --sections-dir "$FIXTURES" \
    --output "$out" 2>/dev/null
if [[ -f "$out" ]]; then
  pass "1.5.3 Output file path with spaces"
else
  fail "1.5.3 Output file path with spaces"
fi
teardown_tmp

# 1.5.4 Overwrite existing output
setup_tmp
out="$TMPDIR_TEST/out.md"
echo "OLD CONTENT" > "$out"
bash "$COMPOSE" \
    --base "$FIXTURES/base-minimal.md" \
    --config "$FIXTURES/sync-default.yml" \
    --sections-dir "$FIXTURES" \
    --output "$out" 2>/dev/null
if ! grep -q "OLD CONTENT" "$out"; then
  pass "1.5.4 Overwrite existing output"
else
  fail "1.5.4 Overwrite existing output"
fi
teardown_tmp

# 1.5.5 Success message
setup_tmp
out="$TMPDIR_TEST/out.md"
stderr=$(bash "$COMPOSE" \
    --base "$FIXTURES/base-minimal.md" \
    --config "$FIXTURES/sync-default.yml" \
    --sections-dir "$FIXTURES" \
    --output "$out" 2>&1 >/dev/null)
if echo "$stderr" | grep -qi "Composed.*successfully"; then
  pass "1.5.5 Success message on stderr"
else
  fail "1.5.5 Success message" "stderr=$stderr"
fi
teardown_tmp

echo ""
echo "============================================================"
echo "  compose.sh: $PASS_COUNT passed, $FAIL_COUNT failed (of $TOTAL)"
echo "============================================================"
echo ""

exit $FAIL_COUNT
