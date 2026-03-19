#!/usr/bin/env bash
# compose.sh — Assemble CLAUDE.md from base + optional sections + auto-generated Skills section.
#
# Usage:
#   bash compose.sh \
#     --base <path-to-base.md> \
#     --config <path-to-.claude-sync.yml> \
#     --sections-dir <path-to-sections/> \
#     --skills-dir <path-to-skills/> \
#     --output <path-to-CLAUDE.md>
#
# The base.md file must contain the marker <!-- INSERT_SECTIONS --> where
# optional sections will be inserted.  The Skills section is always appended
# at the end.

set -euo pipefail

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------
BASE=""
CONFIG=""
SECTIONS_DIR=""
SKILLS_DIR=""
OUTPUT=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --base)        BASE="$2";         shift 2 ;;
    --config)      CONFIG="$2";       shift 2 ;;
    --sections-dir) SECTIONS_DIR="$2"; shift 2 ;;
    --skills-dir)  SKILLS_DIR="$2";   shift 2 ;;
    --output)      OUTPUT="$2";       shift 2 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

for var in BASE CONFIG SECTIONS_DIR OUTPUT; do
  if [[ -z "${!var}" ]]; then
    echo "Error: --$(echo "$var" | tr '[:upper:]' '[:lower:]' | tr '_' '-') is required" >&2
    exit 1
  fi
done

# ---------------------------------------------------------------------------
# Parse .claude-sync.yml for section list
# ---------------------------------------------------------------------------
# Minimal YAML parser — extracts entries under claude_md.sections.
# Expects lines like "    - plan-workflow" after a "  sections:" key.
parse_sections() {
  local in_sections=0
  local sections=()
  while IFS= read -r line; do
    line="${line//$'\r'/}"
    # Detect "sections:" key (with optional leading whitespace)
    if [[ "$line" =~ ^[[:space:]]*sections: ]]; then
      # Handle inline empty list: "sections: []"
      if [[ "$line" =~ \[\] ]]; then
        echo ""
        return
      fi
      in_sections=1
      continue
    fi
    if [[ $in_sections -eq 1 ]]; then
      # List item: "  - name" or "    - name"
      if [[ "$line" =~ ^[[:space:]]*-[[:space:]]+(.*) ]]; then
        sections+=("${BASH_REMATCH[1]}")
      else
        # Non-list-item line ends the sections block
        break
      fi
    fi
  done < "$CONFIG"
  printf '%s\n' "${sections[@]}"
}

SECTION_NAMES="$(parse_sections)"

# ---------------------------------------------------------------------------
# Build the sections block
# ---------------------------------------------------------------------------
SECTIONS_BLOCK=""
if [[ -n "$SECTION_NAMES" ]]; then
  while IFS= read -r name; do
    [[ -z "$name" ]] && continue
    section_file="${SECTIONS_DIR}/${name}.md"
    if [[ ! -f "$section_file" ]]; then
      echo "Warning: section file not found: $section_file" >&2
      continue
    fi
    SECTIONS_BLOCK+="$(cat "$section_file")"
    SECTIONS_BLOCK+=$'\n'
  done <<< "$SECTION_NAMES"
fi

# ---------------------------------------------------------------------------
# Build the Skills section from skill directories
# ---------------------------------------------------------------------------
generate_skills_section() {
  local skills_path="$1"
  local section=""

  section+="## Skills"$'\n'
  section+=""$'\n'
  section+="A skill is a local instruction set stored in a \`SKILL.md\` file. Use a skill when the user names it directly or when the request clearly matches its purpose."$'\n'
  section+=""$'\n'
  section+="Prefer repo-local skills under \`.claude/skills/\` when they exist."$'\n'
  section+=""$'\n'
  section+="### Available Skills"$'\n'
  section+=""$'\n'

  # Iterate over skill directories and extract name + description from YAML front matter
  for skill_dir in "$skills_path"/*/; do
    [[ ! -d "$skill_dir" ]] && continue
    local skill_md="${skill_dir}SKILL.md"
    [[ ! -f "$skill_md" ]] && continue

    local skill_name
    skill_name="$(basename "$skill_dir")"

    # Extract description from YAML front matter (line starting with "description:")
    local description=""
    local in_frontmatter=0
    while IFS= read -r line; do
      # Strip Windows carriage return
      line="${line//$'\r'/}"
      if [[ "$line" == "---" ]]; then
        if [[ $in_frontmatter -eq 1 ]]; then
          break
        fi
        in_frontmatter=1
        continue
      fi
      if [[ $in_frontmatter -eq 1 ]] && [[ "$line" =~ ^description:[[:space:]]*(.*) ]]; then
        description="${BASH_REMATCH[1]}"
      fi
    done < "$skill_md"

    if [[ -z "$description" ]]; then
      description="(no description)"
    fi

    section+="- \`${skill_name}\`: ${description} File: \`.claude/skills/${skill_name}/SKILL.md\`"$'\n'
  done

  section+=""$'\n'
  section+="### Skill Usage Rules"$'\n'
  section+=""$'\n'
  section+="- Check \`.claude/skills/\` first for a matching repo-local skill."$'\n'
  section+="- Read only enough of the relevant \`SKILL.md\` to follow the workflow."$'\n'
  section+="- Resolve relative paths from the skill directory first."$'\n'
  section+="- Load only the specific referenced files needed for the task."$'\n'
  section+="- Reuse provided scripts, templates, and assets when available."$'\n'
  section+="- If multiple skills fit, use the smallest set that covers the request and state the order briefly."$'\n'
  section+="- If a skill cannot be used cleanly, say so briefly and continue with the best fallback."$'\n'
  section+="- Keep context tight by summarizing large references instead of loading everything."$'\n'

  echo "$section"
}

# Determine skills directory
if [[ -n "$SKILLS_DIR" ]]; then
  SKILLS_SECTION="$(generate_skills_section "$SKILLS_DIR")"
else
  SKILLS_SECTION=""
fi

# ---------------------------------------------------------------------------
# Assemble output
# ---------------------------------------------------------------------------
# Read base.md, replace the marker with sections, then append Skills section
{
  while IFS= read -r line; do
    line="${line//$'\r'/}"
    if [[ "$line" == "<!-- INSERT_SECTIONS -->" ]]; then
      if [[ -n "$SECTIONS_BLOCK" ]]; then
        printf '%s' "$SECTIONS_BLOCK"
      fi
    else
      printf '%s\n' "$line"
    fi
  done < "$BASE"

  # Append Skills section
  if [[ -n "$SKILLS_SECTION" ]]; then
    printf '\n%s\n' "$SKILLS_SECTION"
  fi
} > "$OUTPUT"

echo "Composed $OUTPUT successfully." >&2
