## Your task

Update the PR description for the current branch to accurately reflect the current state of the changes. Run each step in order. Stop and report if any step fails.

### 1. Identify the PR

```bash
gh pr view --json number,title,body,baseRefName,headRefName
```
If no PR exists for the current branch, stop and tell the user to open one first (or suggest running `/open-pr`).

### 2. Gather current changes

```bash
git log --oneline develop..HEAD
git diff develop..HEAD --stat
```

Read the full diff to understand what changed:
```bash
git diff develop..HEAD
```

### 3. Rewrite the PR description

Use `.github/pull_request_template.md` as the base structure.

Fill in sections from the diff, following the **PR writing rules** below. **Before rewriting, carefully read the existing PR body** to identify content that should be preserved:

**Preserve existing screenshots:**
- Parse the existing body for any `<img>` tags or `![...]()` image markdown that contain GitHub-hosted URLs — **always preserve them in place** with their exact URLs, alt text, and surrounding headers/captions
- Only remove a user-attachments screenshot if the feature it depicts has been removed from the PR

**General preservation rules:**
- Preserve any manually-written context from the existing body that is still accurate — only update what has changed or is stale
- When existing content conflicts with the current diff, default to what the diff shows
- Add new bullet points for new changes, remove bullets for reverted changes
- Preserve any `Closes #...` or `Fixes #...` references from the existing body

**Redundancy rule:**
- Remove bullet points that describe things that are standard practice / always true for this project (e.g., "uses external templateUrl" when inline templates are never used, "uses OnPush" when that's the default convention)
- Only mention something if it's notable, unusual, or a deliberate deviation from the norm
- If a bullet point would make a reviewer think "obviously, why is this mentioned?" — cut it
- If a bullet would just restate something already in the prose, cut it. Bullets must add information the prose doesn't already cover.

### 4. Update the PR

Write the new body to the body file, then:

```bash
gh pr edit --body-file "/tmp/$(git branch --show-current)-pr-body.md"
```

Report what was updated, including a summary of what changed in the description.
