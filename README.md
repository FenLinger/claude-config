# claude-config

Central source of truth for Claude Code configuration (skills and CLAUDE.md)
across all FenLinger repos.

## How it works

Each consumer repo has a `.claude-sync.yml` and a GitHub Actions workflow that
pulls from this repo on a weekly cron or manual trigger. The workflow copies
skills, composes CLAUDE.md from shared sections + per-repo customizations, and
opens a PR.

See [User Guide](docs/user-guide.md) for full details.

## Quick start

### First-time setup (once per machine)

```bash
gh auth login

gh alias set claude-init '!bash -c '"'"'
  mkdir -p .github/workflows
  gh api repos/FenLinger/claude-config/contents/.github/workflows/sync-claude-config.yml \
    --jq ".content" | base64 -d > .github/workflows/sync-claude-config.yml
  gh api repos/FenLinger/claude-config/contents/defaults/.claude-sync.yml \
    --jq ".content" | base64 -d > .claude-sync.yml
  echo "Done. Edit .claude-sync.yml if needed, then commit and push."
'"'"''

gh alias set claude-sync 'workflow run sync-claude-config.yml'

gh alias set claude-sync-now 'workflow run sync-claude-config.yml -f auto_merge=true'
```

### Onboard a new repo

```bash
cd my-new-repo
gh claude-init           # fetches workflow + default config
# edit .claude-sync.yml if needed
git add .github/workflows/sync-claude-config.yml .claude-sync.yml
git commit -m "chore: add Claude config sync"
git push
gh claude-sync           # trigger first sync
```

### Sync after updating claude-config

```bash
cd my-repo
gh claude-sync           # PR for review
# or
gh claude-sync-now       # PR + auto-merge
```

## Repository structure

```
claude-config/
├── skills/                          # canonical skill files
│   ├── deep-research-survey/
│   ├── reference-implementation-study/
│   └── source-fetch/
├── claude-md/
│   ├── base.md                      # shared CLAUDE.md sections
│   └── sections/                    # optional per-repo sections
│       └── plan-workflow.md
├── defaults/
│   └── .claude-sync.yml             # starter config for gh claude-init
├── .github/
│   └── workflows/
│       └── sync-claude-config.yml   # canonical workflow (copied to consumers)
├── compose.sh                       # assembles base + sections → CLAUDE.md
└── README.md
```
