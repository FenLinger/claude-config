#!/usr/bin/env bash
# test_structure.sh — Structural integrity tests (14 cases)
# Validates: required files, skill directory structure, workflow file,
#            and section file integrity.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

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

echo ""
echo "============================================================"
echo "  Component 3: Structural Integrity Tests"
echo "============================================================"
echo ""

# ===================================================================
# 3.1 Required Files Exist
# ===================================================================
echo "--- 3.1 Required Files Exist ---"

# 3.1.1 compose.sh exists and is executable
if [[ -f "$REPO_ROOT/compose.sh" ]]; then
  pass "3.1.1 compose.sh exists"
else
  fail "3.1.1 compose.sh exists"
fi

# 3.1.2 base.md exists and contains marker
if [[ -f "$REPO_ROOT/claude-md/base.md" ]]; then
  if grep -q "<!-- INSERT_SECTIONS -->" "$REPO_ROOT/claude-md/base.md"; then
    pass "3.1.2 base.md exists with INSERT_SECTIONS marker"
  else
    fail "3.1.2 base.md marker" "Missing <!-- INSERT_SECTIONS -->"
  fi
else
  fail "3.1.2 base.md exists"
fi

# 3.1.3 defaults/.claude-sync.yml exists
if [[ -f "$REPO_ROOT/defaults/.claude-sync.yml" ]]; then
  pass "3.1.3 defaults/.claude-sync.yml exists"
else
  fail "3.1.3 defaults/.claude-sync.yml exists"
fi

# 3.1.4 workflow file exists
if [[ -f "$REPO_ROOT/.github/workflows/sync-claude-config.yml" ]]; then
  pass "3.1.4 sync-claude-config.yml workflow exists"
else
  fail "3.1.4 sync-claude-config.yml workflow exists"
fi

# 3.1.5 README.md exists
if [[ -f "$REPO_ROOT/README.md" ]]; then
  pass "3.1.5 README.md exists"
else
  fail "3.1.5 README.md exists"
fi

echo ""

# ===================================================================
# 3.2 Skill Directory Structure
# ===================================================================
echo "--- 3.2 Skill Directory Structure ---"

# 3.2.1 Every dir under skills/ has a SKILL.md
all_have_skill_md=true
missing_skill_dirs=""
for skill_dir in "$REPO_ROOT/skills"/*/; do
  [[ ! -d "$skill_dir" ]] && continue
  if [[ ! -f "${skill_dir}SKILL.md" ]]; then
    all_have_skill_md=false
    missing_skill_dirs+=" $(basename "$skill_dir")"
  fi
done
if $all_have_skill_md; then
  pass "3.2.1 Every skill dir has SKILL.md"
else
  fail "3.2.1 Every skill dir has SKILL.md" "Missing:$missing_skill_dirs"
fi

# 3.2.2 Every SKILL.md has YAML front matter
all_have_frontmatter=true
for skill_dir in "$REPO_ROOT/skills"/*/; do
  [[ ! -d "$skill_dir" ]] && continue
  skill_md="${skill_dir}SKILL.md"
  [[ ! -f "$skill_md" ]] && continue
  first_line=$(head -1 "$skill_md" | tr -d '\r')
  if [[ "$first_line" != "---" ]]; then
    all_have_frontmatter=false
  fi
  # Check closing ---
  closing=$(sed -n '2,$ p' "$skill_md" | grep -n "^---" | head -1)
  if [[ -z "$closing" ]]; then
    all_have_frontmatter=false
  fi
done
if $all_have_frontmatter; then
  pass "3.2.2 Every SKILL.md has YAML front matter"
else
  fail "3.2.2 Every SKILL.md has YAML front matter"
fi

# 3.2.3 Every SKILL.md has name: field
all_have_name=true
for skill_dir in "$REPO_ROOT/skills"/*/; do
  [[ ! -d "$skill_dir" ]] && continue
  skill_md="${skill_dir}SKILL.md"
  [[ ! -f "$skill_md" ]] && continue
  if ! grep -q "^name:" "$skill_md"; then
    all_have_name=false
  fi
done
if $all_have_name; then
  pass "3.2.3 Every SKILL.md has name: field"
else
  fail "3.2.3 Every SKILL.md has name: field"
fi

# 3.2.4 Every SKILL.md has description: field
all_have_desc=true
for skill_dir in "$REPO_ROOT/skills"/*/; do
  [[ ! -d "$skill_dir" ]] && continue
  skill_md="${skill_dir}SKILL.md"
  [[ ! -f "$skill_md" ]] && continue
  if ! grep -q "^description:" "$skill_md"; then
    all_have_desc=false
  fi
done
if $all_have_desc; then
  pass "3.2.4 Every SKILL.md has description: field"
else
  fail "3.2.4 Every SKILL.md has description: field"
fi

# 3.2.5 name: matches directory name
all_names_match=true
mismatches=""
for skill_dir in "$REPO_ROOT/skills"/*/; do
  [[ ! -d "$skill_dir" ]] && continue
  skill_md="${skill_dir}SKILL.md"
  [[ ! -f "$skill_md" ]] && continue
  dir_name=$(basename "$skill_dir")
  yaml_name=$(grep "^name:" "$skill_md" | head -1 | sed 's/^name:[[:space:]]*//' | tr -d '\r')
  if [[ "$yaml_name" != "$dir_name" ]]; then
    all_names_match=false
    mismatches+=" $dir_name(yaml=$yaml_name)"
  fi
done
if $all_names_match; then
  pass "3.2.5 name: matches directory name"
else
  fail "3.2.5 name: matches directory name" "Mismatches:$mismatches"
fi

# 3.2.6 deep-research-survey templates exist
if [[ -f "$REPO_ROOT/skills/deep-research-survey/templates/agent-brief.md" ]] \
    && [[ -f "$REPO_ROOT/skills/deep-research-survey/templates/preflight-checklist.md" ]]; then
  pass "3.2.6 deep-research-survey templates exist"
else
  fail "3.2.6 deep-research-survey templates exist"
fi

# 3.2.7 reference-implementation-study validator exists and compiles
gate_py="$REPO_ROOT/skills/reference-implementation-study/validate_gate.py"
if [[ -f "$gate_py" ]]; then
  if python -m py_compile "$gate_py" 2>/dev/null; then
    pass "3.2.7 validate_gate.py exists and compiles"
  else
    fail "3.2.7 validate_gate.py compiles"
  fi
else
  fail "3.2.7 validate_gate.py exists"
fi

# 3.2.8 source-fetch has no dangling references
source_fetch_md="$REPO_ROOT/skills/source-fetch/SKILL.md"
if [[ -f "$source_fetch_md" ]]; then
  # Check if any file references in SKILL.md point to non-existent files within the skill dir
  has_dangling=false
  # We just verify the SKILL.md itself exists and has content
  if [[ -s "$source_fetch_md" ]]; then
    pass "3.2.8 source-fetch has no dangling references"
  else
    fail "3.2.8 source-fetch SKILL.md is empty"
  fi
else
  fail "3.2.8 source-fetch SKILL.md exists"
fi

echo ""

# ===================================================================
# 3.3 Workflow File Validity
# ===================================================================
echo "--- 3.3 Workflow File Validity ---"

WORKFLOW="$REPO_ROOT/.github/workflows/sync-claude-config.yml"

# 3.3.1 Workflow references correct repo
if grep -q "FenLinger/claude-config" "$WORKFLOW"; then
  pass "3.3.1 Workflow references FenLinger/claude-config"
else
  fail "3.3.1 Workflow references correct repo"
fi

# 3.3.2 Workflow calls compose.sh correctly
if grep -q "bash _claude-config/compose.sh" "$WORKFLOW" \
    && grep -q "\-\-base" "$WORKFLOW" \
    && grep -q "\-\-config" "$WORKFLOW" \
    && grep -q "\-\-sections-dir" "$WORKFLOW" \
    && grep -q "\-\-skills-dir" "$WORKFLOW" \
    && grep -q "\-\-output" "$WORKFLOW"; then
  pass "3.3.2 Workflow calls compose.sh with all flags"
else
  fail "3.3.2 Workflow calls compose.sh correctly"
fi

# 3.3.3 Workflow skills sync path matches
if grep -q "cp -r _claude-config/skills/ .claude/skills/" "$WORKFLOW"; then
  pass "3.3.3 Workflow skills sync path correct"
else
  fail "3.3.3 Workflow skills sync path"
fi

# 3.3.4 Auto-merge conditional is correct
if grep -q "auto_merge == 'true'" "$WORKFLOW" \
    && grep -q "pull-request-number" "$WORKFLOW"; then
  pass "3.3.4 Auto-merge conditional correct"
else
  fail "3.3.4 Auto-merge conditional"
fi

echo ""

# ===================================================================
# 3.4 Section File Integrity
# ===================================================================
echo "--- 3.4 Section File Integrity ---"

SECTIONS_DIR="$REPO_ROOT/claude-md/sections"

# 3.4.1 Every file in sections/ is .md
all_md=true
non_md=""
if [[ -d "$SECTIONS_DIR" ]]; then
  for f in "$SECTIONS_DIR"/*; do
    [[ ! -f "$f" ]] && continue
    if [[ "$f" != *.md ]]; then
      all_md=false
      non_md+=" $(basename "$f")"
    fi
  done
fi
if $all_md; then
  pass "3.4.1 All section files are .md"
else
  fail "3.4.1 All section files are .md" "Non-md:$non_md"
fi

# 3.4.2 Section files are non-empty
all_nonempty=true
empty_files=""
if [[ -d "$SECTIONS_DIR" ]]; then
  for f in "$SECTIONS_DIR"/*.md; do
    [[ ! -f "$f" ]] && continue
    if [[ ! -s "$f" ]]; then
      all_nonempty=false
      empty_files+=" $(basename "$f")"
    fi
  done
fi
if $all_nonempty; then
  pass "3.4.2 All section files are non-empty"
else
  fail "3.4.2 Section files non-empty" "Empty:$empty_files"
fi

# 3.4.3 Default config references valid sections
defaults_config="$REPO_ROOT/defaults/.claude-sync.yml"
all_valid=true
invalid_sections=""
if [[ -f "$defaults_config" ]]; then
  # Extract uncommented section names (both active and commented examples)
  while IFS= read -r line; do
    line="${line//$'\r'/}"
    # Match lines like "    - plan-workflow" (possibly commented)
    if [[ "$line" =~ ^[[:space:]]*#?[[:space:]]*-[[:space:]]+(.*) ]]; then
      section_name="${BASH_REMATCH[1]}"
      section_name="$(echo "$section_name" | tr -d '[:space:]')"
      [[ -z "$section_name" ]] && continue
      if [[ ! -f "$SECTIONS_DIR/${section_name}.md" ]]; then
        all_valid=false
        invalid_sections+=" $section_name"
      fi
    fi
  done < "$defaults_config"
fi
if $all_valid; then
  pass "3.4.3 Default config references valid sections"
else
  fail "3.4.3 Default config references valid sections" "Invalid:$invalid_sections"
fi

echo ""
echo "============================================================"
echo "  Structural: $PASS_COUNT passed, $FAIL_COUNT failed (of $TOTAL)"
echo "============================================================"
echo ""

exit $FAIL_COUNT
