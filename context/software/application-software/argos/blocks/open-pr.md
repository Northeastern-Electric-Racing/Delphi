## Your task

Run each step in order. Stop and report if any step fails.

### 1. Verify commit format
```bash
git log --oneline develop..HEAD
```
Flag any commit that doesn't match the commit message format.

### 2. Lint
Skip if the diff only touches `scylla-server/`.
```bash
cd "$(git rev-parse --show-toplevel)/angular-client" && npx prettier --check "src/**/*.{ts,html,scss}" && npx ng lint
```

### 3. Conflict check
```bash
git fetch origin develop
git merge --no-commit --no-ff origin/develop || true
git merge --abort 2>/dev/null || true
```
Stop only on actual merge conflicts ("Already up to date" is fine).

### 4. Write PR body

Use `.github/pull_request_template.md` as the base. Fill in sections from the diff, following the **PR writing rules** below, and write it to the body file.

### 5. Check working tree

If `git status --porcelain` shows changes, stop and ask the user what to do with them. `gh pr create` aborts on uncommitted changes.

### 6. Push and open PR

The ticket number is the branch name's leading number (`174-mqtt-screen-mobile-view` → `#174`).

```bash
git push -u origin $(git branch --show-current)
gh pr create --draft --base develop --head $(git branch --show-current) --title "#{ticket_number} brief title" --body-file "/tmp/$(git branch --show-current)-pr-body.md" --assignee @me
```

Report the PR URL when done.
