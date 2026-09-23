## Your task

Run each step in order. Stop and report if any step fails.

### 1. Verify commit format
```bash
git log --oneline develop..HEAD
```
Confirm all commits match `#{ticket_number} {2-8 word description}` (e.g., `#501 Add endpoint for client rules`). Flag any that don't.

### 2. Lint and test
```bash
cd "$(git rev-parse --show-toplevel)/angular-client" && npx prettier --check "src/**/*.{ts,html,scss}" && npx ng lint
```
If there are frontend changes. Skip if the diff only touches `scylla-server/`.

**Why the absolute cd:** the Bash tool persists cwd across calls, so a bare `cd angular-client` errors on the second run when you're already inside. Resolving from `git rev-parse --show-toplevel` makes it idempotent regardless of where the prior command left you.

### 3. Conflict check
```bash
git fetch origin develop
git merge --no-commit --no-ff origin/develop || true
git merge --abort 2>/dev/null || true
```
Note: "Already up to date" returns a non-zero exit code but is not a failure. Only stop if there are actual merge conflicts in the output.

### 4. Write PR body

Use `.github/pull_request_template.md` as the base. Fill in sections from the diff, following the **PR writing rules** below, and write it to the body file.

### 5. Clean working tree

Restore any untracked or modified files that were changed as a side effect of earlier steps (e.g. package-lock.json from npm install during lint). The working tree must be clean before `gh pr create` — it aborts on uncommitted changes.

```bash
git checkout -- . 2>/dev/null || true
```

### 6. Push and open PR

Extract the ticket number from the branch name (e.g., `174-mqtt-screen-mobile-view` → `#174`).

Always use `--head` with the branch name — gh cli can't always detect the remote branch without it.

```bash
git push -u origin $(git branch --show-current)
gh pr create --draft --base develop --head $(git branch --show-current) --title "#{ticket_number} brief title" --body-file "/tmp/$(git branch --show-current)-pr-body.md" --assignee @me
```

Report the PR URL when done.
