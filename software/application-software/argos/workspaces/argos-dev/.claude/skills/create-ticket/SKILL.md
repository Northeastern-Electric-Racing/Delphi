---
name: create-ticket
description: Draft and file a GitHub issue (idea, spike, epic, or dev work) on Argos or Nero from the repo's issue templates. Use whenever the user wants to create, file, write up, or log a ticket, issue, idea, spike, epic, bug, or task.
---

# Create ticket

The repo's issue templates are the source of truth. Each field's description says what goes in it; follow those descriptions rather than anything restated here. Repo-wide issue conventions live in the repo's docs/agents/issue-tracker.md.

## 1. Pick the template

| Template | Use for | Issue type | Parent |
|---|---|---|---|
| idea.yml | A feature or direction to explore | Feature | none |
| spike.yml | One approach to an idea, or a small standalone improvement | Task | the idea, if any |
| epic.yml | A settled idea, ready to break into dev work | Feature | none (link the idea in "From idea") |
| dev-work.yml | Any implementation work | Feature, Bug, or Task | the epic, if any |

Pipeline: idea → spikes → epic → dev work. If the user is unsure, a small thing is a spike and a big unexplored thing is an idea.

## 2. Read the template

Repo is a workspace repo (argos) or owner/name (Nero is Northeastern-Electric-Racing/Nero-2.0):

`gh api repos/<owner>/<name>/contents/.github/ISSUE_TEMPLATE/<template> -q .content | base64 -d`

Use its `labels`, `type`, the markdown blocks (context for you, not part of the body), and each field's `label`, `description`, and `required`.

## 3. Draft

- **Title:** concise and imperative ("Add …", "Fix …"), no prefixes.
- **Body:** one `### <field label>` section per field, in template order, matching what the web form produces. Omit empty optional fields. Fields with `render: text` (Context transfer) go in a fenced text block that starts with a short summary. Diagrams may be a mermaid block, ASCII in a text block, or an image link.
- **Backticks:** outside the diagram and context-transfer blocks, use at most three inline backticks; reference files and identifiers in plain text.
- **Labels:** the template's category label, plus:
  - written-by, exactly one: `by: human` (the user dictated the text), `by: ai-assisted` (the user supplied the substance, you drafted), `by: ai` (you wrote it largely on your own);
  - area, one or more: `frontend`, `backend`, `devops`.
- Check for duplicates with `gh issue list -R <repo> --search "<keywords>" --state open` and mention any strong match.

Show the full draft (title, type, labels, parent, body) and get the user's OK before filing.

## 4. File

Write the body to a temp file, then from the workspace root:

`bash .claude/skills/create-ticket/scripts/file-ticket.sh <repo> <type> "<title>" <body-file> [--parent <n>] <label>...`

It assigns the user, sets the issue type, links the sub-issue, and prints the URL. Exit 2 means a label is missing on the repo: tell the user, don't create labels. Exit 3 means GitHub failed: file with the GitHub MCP server instead.

When filing an epic from an idea, offer to close the idea as completed afterward.
