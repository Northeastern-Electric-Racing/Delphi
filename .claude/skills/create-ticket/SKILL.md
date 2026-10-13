---
name: create-ticket
description: Draft and file a GitHub issue (idea, spike, epic, or dev work) on Delphi from its issue templates. Use whenever the user wants to create, file, or log a Delphi ticket, issue, idea, spike, epic, bug, or task.
---

Follow the shared rules in `software/application-software/workspace-inherit/.claude/skills/create-ticket/SKILL.md`, with these Delphi specifics:

- Repo: Northeastern-Electric-Racing/Delphi (base branch `main`); templates in `.github/ISSUE_TEMPLATE/`.
- Labels: the template's category and a written-by label; Delphi has no area labels.
- Vocabulary: `docs/design.md`'s terms (workspace, ws branch, refresh, propose, `workspace-inherit/`).
- Diagrams: show the branches and folders a change touches (main, `ws/*`, `.delphi/`, CI), before and after.
