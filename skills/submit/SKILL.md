---
name: submit
description: >
  Automate the full git workflow: create branch, commit, push, and create PR/MR.
  Supports both single repo and `repo` tool managed multi-repo projects.
  Use this skill whenever the user says "submit", "commit and push", "create PR",
  "submit PR", "push and create MR", "提交代码", "提交", or any phrase that
  implies finishing work by committing, pushing, and opening a pull/merge request.
  Also trigger when the user wants to go through the complete submit flow after
  making code changes, even if they don't explicitly say "submit".
  For repo-managed projects, this skill handles multi-repo changes as a batch.
---

# Submit: Automated Commit, Push, and PR/MR Workflow

This skill automates going from "dirty working tree" to "PR/MR link" with
minimal friction. It supports two modes:

- **Single repo** — standard git workflow
- **Repo tool** — multi-repo projects managed by Google's `repo` tool

The mode is auto-detected at the start.

---

## Step 0: Detect mode

```bash
# Check if we're in a repo-managed project
[ -d .repo ] && echo "REPO_MODE" || echo "SINGLE_MODE"
```

- If `.repo/` exists → use the **Repo Mode** flow below
- Otherwise → use the **Single Repo** flow

---

## Single Repo Flow

### Step 1: Understand the changes

Run these in parallel:

```bash
git status
git diff
git diff --staged
git log --oneline -5
```

Analyze the diff. If there are no changes, tell the user and stop.

### Step 2: Generate commit message and branch name

Based on the diff content:

- **Branch name**: infer from the change scope. Use format `fix/<short>` or
  `feat/<short>`. If already on a non-main branch with uncommitted changes,
  ask whether to use the current branch or create a new one.
- **Commit message**: conventional commits style, concise, focused on "why".

Present the proposed branch name and commit message to the user for
confirmation before proceeding.

### Step 3: Create branch, stage, and commit

```bash
git checkout -b <branch-name>
git add <specific-files>
git commit -m "$(cat <<'EOF'
<commit message>

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>
EOF
)"
```

### Step 4: Push

```bash
git push -u origin <branch-name>
```

### Step 5: Create PR/MR → go to **Create PR/MR** section

---

## Repo Mode Flow

For projects managed by `repo` (Google's multi-repo tool). The `.repo/`
directory is present at the workspace root.

### Step 1: Discover changed repos

```bash
# List all projects with uncommitted changes
repo status
```

Also run for detail:

```bash
# Get diff summary per project
repo diff
```

Parse the output to build a list of changed projects. Each project has:
- project path (relative to workspace root)
- changed files
- diff content

If no projects have changes, tell the user and stop.

### Step 2: Plan the submission

Present the user with:

1. **List of changed repos** — show each project path and a summary of changes
2. **Proposed branch name** — one shared branch name for all repos (e.g.
   `feat/add-foo-support`). Infer from the overall change scope.
3. **Proposed commit message** — one message used across all repos, or
   per-repo messages if the changes are unrelated.
4. **Ask**: use the same branch name for all repos, or different ones?

Use AskUserQuestion to confirm the plan before proceeding.

### Step 3: Batch commit across repos

For each changed project, run:

```bash
# Enter the project directory
cd <project-path>

# Create branch (skip if already on it)
git checkout -b <branch-name>

# Stage changed files (be specific)
git add <specific-files>

# Commit with the agreed message
git commit -m "$(cat <<'EOF'
<commit message>

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>
EOF
)"
```

Process repos sequentially since each requires a `cd`. Report progress
after each repo (e.g. "✓ project-a committed").

### Step 4: Push all repos

```bash
# Push all projects at once
repo push --branch <branch-name> --dest origin
```

If `repo push` is not available or fails, fall back to pushing each repo
individually:

```bash
cd <project-path> && git push -u origin <branch-name>
```

### Step 5: Create PRs/MRs for each repo

For each pushed repo, follow the **Create PR/MR** section below.

Collect all PR/MR links and present them as a summary table.

---

## Create PR/MR

Detect the platform from the remote URL.

### GitHub (`github.com`)

```bash
gh pr create --title "<title>" --body "$(cat <<'EOF'
## Summary
<1-3 bullet points>

## Test plan
<checklist>

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

Return the PR URL from output.

### GitLab (any other Git remote)

1. After `git push`, capture the remote output — GitLab prints an MR creation URL.
2. If found, return it directly.
3. If not, try `glab mr create` if `glab` is available.
4. Last resort: construct the URL:
   `<remote-web-url>/-/merge_requests/new?merge_request[source_branch]=<branch-name>`

---

## Step 6: Summary

Tell the user:
- The branch name
- The commit hash(es)
- The PR/MR link(s)

For repo mode, present a table:

```
| Repo | Commit | PR/MR |
|------|--------|-------|
| project-a | abc1234 | http://... |
| project-b | def5678 | http://... |
```

Keep it concise.

---

## Edge cases

- **Already on a feature branch**: ask whether to commit here or create a new one.
- **Multiple remotes**: use `origin` by default; ask if unsure.
- **Push fails** (remote branch exists): suggest `--force-with-lease` only after
  explaining the risk.
- **Amend**: if user says "amend" or "追加", use `git commit --amend` +
  `git push --force-with-lease`. Warn about history rewrite.
- **No changes**: stop and tell the user.
- **Mixed concerns**: suggest splitting into multiple commits if clearly separable.
- **Repo mode partial push**: if push fails for some repos, report which
  succeeded and which failed. Don't abort the whole batch.
