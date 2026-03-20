# Claude Config — User Guide

## Quick Workflow

```
                  ┌──────────────────┐
                  │  claude-config    │  ← single source of truth
                  │  (GitHub repo)    │
                  └────────┬─────────┘
                           │ pull (read-only)
              ┌────────────┼────────────┐
              ▼            ▼            ▼
        ┌──────────┐ ┌──────────┐ ┌──────────┐
        │ repo-A   │ │ repo-B   │ │ repo-C   │  ← consumer repos
        │ cron/cli │ │ cron/cli │ │ cron/cli │
        └──────────┘ └──────────┘ └──────────┘
```

**Edit skills or CLAUDE.md** → push to `claude-config` → run `gh claude-sync` in each repo you care about → review & merge the PR.

That's it.

---

## One-Time Setup (per machine)

### 1. Install and authenticate GitHub CLI

```bash
# Windows
winget install --id GitHub.cli

# macOS
brew install gh

# Then authenticate
gh auth login
```

### 2. Set up aliases

```bash
gh alias set claude-init '!bash -c '"'"'
  mkdir -p .github/workflows
  gh api repos/FenLinger/claude-config/contents/.github/workflows/sync-claude-config.yml \
    --jq ".content" | base64 -d > .github/workflows/sync-claude-config.yml
  gh api repos/FenLinger/claude-config/contents/defaults/.claude-sync.yml \
    --jq ".content" | base64 -d > .claude-sync.yml
  REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null)
  if [ -n "$REPO" ]; then
    gh api "repos/$REPO/actions/permissions/workflow" \
      --method PUT \
      -f default_workflow_permissions=write \
      -F can_approve_pull_request_reviews=true 2>/dev/null \
      && echo "Enabled Actions PR creation permission." \
      || echo "Warning: could not set Actions PR permission (need admin access)."
  fi
  echo "Done. Edit .claude-sync.yml if needed, then commit and push."
'"'"''

gh alias set claude-sync 'workflow run sync-claude-config.yml'

gh alias set claude-sync-now 'workflow run sync-claude-config.yml -f auto_merge=true'
```

---

## CLI Reference

| Command | Purpose | What happens |
|---------|---------|--------------|
| `gh claude-init` | Bootstrap a repo for sync | Fetches workflow + default config from `claude-config`, writes to current repo, enables Actions PR creation permission |
| `gh claude-sync` | Trigger sync (PR for review) | Runs the sync workflow → opens a PR with updated skills + CLAUDE.md |
| `gh claude-sync-now` | Trigger sync (auto-merge) | Same as above, but immediately merges the PR |

### Targeting a specific repo from anywhere

```bash
gh claude-sync -R FenLinger/prach-receiver
gh claude-sync-now -R FenLinger/filter-design
```

---

## How to: Onboard a New Repo

```bash
cd my-new-repo
gh claude-init
# Edit .claude-sync.yml to add custom sections (see below)
git add .github/workflows/sync-claude-config.yml .claude-sync.yml
git commit -m "chore: add Claude config sync"
git push
gh claude-sync       # trigger the first sync
```

The workflow is now registered. It will also run automatically every Monday at
6 AM UTC.

---

## How to: Update a Skill

1. Edit the skill file in `claude-config/skills/<name>/`.
2. Commit and push to `claude-config/main`.
3. In each consumer repo you want updated now:

```bash
gh claude-sync       # PR for review
# or
gh claude-sync-now   # auto-merge
```

Other repos pick it up on their weekly cron.

---

## How to: Update Shared CLAUDE.md Rules

1. Edit `claude-config/claude-md/base.md`.
2. Push to `claude-config/main`.
3. Run `gh claude-sync` in consumer repos.

---

## How to: Add a New CLAUDE.md Section

1. Create `claude-config/claude-md/sections/<name>.md` with the section content
   (include the `## Heading`).
2. Push to `claude-config/main`.
3. In the target repo, edit `.claude-sync.yml` and add the section name:

```yaml
claude_md:
  base: true
  sections:
    - plan-workflow
    - my-new-section     # ← added
```

4. Commit the `.claude-sync.yml` change.
5. Run `gh claude-sync`.

---

## How to: Remove a Repo from Sync

Delete `.github/workflows/sync-claude-config.yml` from the repo, or disable the
workflow in the GitHub Actions settings. Nothing else to change anywhere.

---

## `.claude-sync.yml` Specification

This file lives at the root of each consumer repo and declares what the repo
receives from `claude-config`.

### Schema

```yaml
# Which skills to sync. Currently only "all" is supported.
skills: all

# CLAUDE.md composition
claude_md:
  # Include the shared base sections (Core Role, Logging, Timeline,
  # Diagram Rules, Proposal Rules, Survey Rules, Math Rules)
  base: true

  # Optional sections to insert after Development Timeline,
  # before Diagram Rules. Each name maps to a file in
  # claude-config/claude-md/sections/<name>.md
  sections:
    - plan-workflow
    # - another-section
```

### Available sections

| Section name | File | Contents |
|-------------|------|----------|
| `plan-workflow` | `claude-md/sections/plan-workflow.md` | Plan and Implementation Workflow (planning rules + implementation rules) |

To add new sections, create a `.md` file in `claude-config/claude-md/sections/`
and reference its filename (without `.md`) in the `sections` list.

### Skills field

Currently only `all` is supported — all skills in `claude-config/skills/` are
copied to `.claude/skills/` in the consumer repo. Future versions may support
selective skill sync.

---

## `compose.sh` Specification

The composition script assembles `CLAUDE.md` from parts.

### Usage

```bash
bash compose.sh \
  --base <path-to-base.md> \
  --config <path-to-.claude-sync.yml> \
  --sections-dir <path-to-sections-directory/> \
  --skills-dir <path-to-skills-directory/> \
  --output <path-to-output-CLAUDE.md>
```

### Behavior

1. Reads `base.md` line by line.
2. When it encounters `<!-- INSERT_SECTIONS -->`, inserts the content of each
   section file listed in `.claude-sync.yml` (in order).
3. After the base content, appends an auto-generated **Skills** section:
   - Reads each subdirectory under `skills/`.
   - Extracts the `description:` field from the YAML front matter of each
     `SKILL.md`.
   - Generates the `## Skills`, `### Available Skills`, and
     `### Skill Usage Rules` blocks.
4. Writes the assembled output to the specified file.

### YAML front matter requirement

Each `SKILL.md` must have YAML front matter with at least a `description` field:

```yaml
---
name: my-skill
description: One-line description of what the skill does.
---
```

The description is used in the auto-generated `### Available Skills` list.

---

## Sync Workflow Specification

**File:** `.github/workflows/sync-claude-config.yml` (in each consumer repo)

### Triggers

| Trigger | Condition | Behavior |
|---------|-----------|----------|
| `schedule` | Every Monday 6:00 AM UTC | Creates PR (no auto-merge) |
| `workflow_dispatch` | Manual (CLI or Actions tab) | Creates PR; optionally auto-merges if `auto_merge=true` |

### Inputs

| Input | Type | Default | Description |
|-------|------|---------|-------------|
| `auto_merge` | choice (`true`/`false`) | `false` | When `true`, the workflow merges the PR immediately after creation |

### Steps

1. **Checkout consumer repo** — standard `actions/checkout@v4`.
2. **Checkout claude-config** — reads `FenLinger/claude-config` into
   `_claude-config/` (read-only, no token needed for public repos).
3. **Sync skills** — deletes `.claude/skills/` and copies from
   `_claude-config/skills/`.
4. **Compose CLAUDE.md** — runs `compose.sh` with the consumer repo's
   `.claude-sync.yml`.
5. **Clean up** — removes `_claude-config/` temp directory.
6. **Create sync PR** — uses `peter-evans/create-pull-request@v6` to open a
   PR on branch `sync/claude-config`. If no files changed, no PR is created.
7. **Auto-merge PR** — conditional step. Runs only when `auto_merge == 'true'`
   AND a PR was created. Uses `gh pr merge` with the workflow's `GITHUB_TOKEN`.

### PR details

| Field | Value |
|-------|-------|
| Branch | `sync/claude-config` |
| Title | `chore: sync Claude config` |
| Commit message | `chore: sync Claude config from claude-config` |
| Auto-delete branch | Yes (`delete-branch: true`) |

### Authentication

- **Public `claude-config`:** No token needed. The workflow fetches it
  anonymously.
- **Private `claude-config`:** Add a read-only PAT as a repo secret named
  `CLAUDE_CONFIG_TOKEN` and reference it in the checkout step:
  ```yaml
  token: ${{ secrets.CLAUDE_CONFIG_TOKEN }}
  ```

---

## Architecture

### Central repo (`FenLinger/claude-config`)

```
claude-config/
├── skills/                          # canonical skill files
│   ├── deep-research-survey/
│   │   ├── SKILL.md
│   │   ├── agents/openai.yaml
│   │   └── templates/
│   │       ├── agent-brief.md
│   │       └── preflight-checklist.md
│   ├── reference-implementation-study/
│   │   ├── SKILL.md
│   │   └── validate_gate.py
│   └── source-fetch/
│       └── SKILL.md
├── claude-md/
│   ├── base.md                      # shared CLAUDE.md sections
│   └── sections/
│       └── plan-workflow.md         # optional section
├── defaults/
│   └── .claude-sync.yml             # starter config for gh claude-init
├── .github/
│   └── workflows/
│       └── sync-claude-config.yml   # canonical workflow template
├── docs/
│   └── user-guide.md               # this file
├── compose.sh
└── README.md
```

The central repo is **passive** — it has no outbound workflows. It does not
know which repos consume it.

### Consumer repo (any `FenLinger/*` repo)

```
<repo>/
├── .claude-sync.yml                 # what this repo wants
├── .github/
│   └── workflows/
│       └── sync-claude-config.yml   # sync workflow
├── .claude/
│   └── skills/                      # populated by sync
└── CLAUDE.md                        # composed by sync
```

### Self-registration model

Consumer repos register themselves by adding the workflow file. No central
list, no dispatch, no cross-repo write tokens. Adding or removing a repo
from sync never requires editing `claude-config`.
