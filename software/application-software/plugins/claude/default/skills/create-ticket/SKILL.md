---
name: create-ticket
description: Draft and file a GitHub issue (idea, spike, epic, or dev work) on an application-software repo (Argos, Nero) from the repo's issue templates, or rewrite an existing issue into them. Use whenever the user wants to create, file, write up, or log a ticket, issue, idea, spike, epic, bug, or task, including an out-of-scope idea that comes up mid-work.
---

# Create ticket

These are the ticket conventions for every application-software repo. The repo's own `.github/ISSUE_TEMPLATE` holds only the fields (`gh api repos/<owner>/<repo>/contents/.github/ISSUE_TEMPLATE/<file> -q .content | base64 -d`); follow each field's description.

First load the project's `ticket-conventions` skill (e.g. `argos:ticket-conventions`) for its repo, area labels, vocabulary, and diagrams. If none is enabled, ask which repo.

## Workflow

idea → spikes → epic → dev work

| Ticket | What it is | Issue type | Parent |
|---|---|---|---|
| Idea | What could be built and why, with open options to explore. | none | none |
| Spike | One approach to an idea, or a small standalone improvement: what is explored and the hypothesis. Findings go in comments and draft PRs, not the ticket. | none | its idea, if any |
| Epic | A settled idea: a new issue linking the idea in "From idea"; then offer to close the idea as completed. The approach and whole-epic outcomes, not a walkthrough of each ticket. | Feature | none |
| Dev work | Any implementation work: testable requirements, Notes for gotchas and pointers to code. | Feature, Bug, or Task | its epic, if any |

If unsure, a small, clear change is dev work, a small unknown is a spike, and a big unexplored thing is an idea. Ideas and spikes explore work, so they get no issue type; bug, feature, and task are issue types, never labels.

## Draft

- Check the code first: the work may be done or already tracked. Leave unknowns as open questions in Notes.
- Title: concise and imperative, no prefixes.
- Short and plain; explain project-specific terms. One `### <field label>` per field in template order; omit empty optional fields.
- Requirements: clear, broad checkboxes, each an outcome rather than an implementation step; 3-5, never more than 7. If it needs more, split the ticket.
- Backticks: at most three inline uses per body; name files and identifiers in plain text. Diagram and context-transfer blocks don't count.
- No prescriptions on ideas and spikes: say what to explore and why, never how to build it. Context transfer (optional on spikes, epics, and dev work) starts with a short summary, then raw facts, not instructions or a proposed solution.
- Labels: the template's category (`idea`, `spike`, `epic`, `dev work`), one written-by (`by: human` if the user dictated it, `by: ai-assisted` if they gave the substance, `by: ai` if you wrote it, including rewrites), and at least one of the project's area labels.
- Rewriting an old ticket: keep its intent and assignees; update vocabulary (check the code), labels, issue type, and parent.
- Folding one ticket into another: add it as a requirement on the target, then close it as not planned. Every close gets a one-line comment saying why.

## File

Check for open duplicates, then show the full draft (title, type if any, labels, parent, body) in the chat, not only in a file. File or edit only what the user OKs.

Use the REST API (GraphQL may be blocked): POST repos/<owner>/<repo>/issues with title, body, labels, the issue type from the table, and the user as assignee (not on spikes, which stay unassigned), then, if it has a parent, POST repos/<owner>/<repo>/issues/<parent>/sub_issues with the new issue's id. Report the URL.
