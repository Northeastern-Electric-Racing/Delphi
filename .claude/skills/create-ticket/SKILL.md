---
name: create-ticket
description: Draft and file a GitHub issue (idea, spike, epic, or dev work) on Argos or Nero from the repo's issue templates, or rewrite an existing issue into them. Use whenever the user wants to create, file, write up, or log a ticket, issue, idea, spike, epic, bug, or task, including an out-of-scope idea that comes up mid-work.
---

# Create ticket

Follow the repo's templates in .github/ISSUE_TEMPLATE (`gh api repos/<owner>/<repo>/contents/.github/ISSUE_TEMPLATE/<file> -q .content | base64 -d`) and docs/agents/issue-tracker.md. Repos: Northeastern-Electric-Racing/Argos and Northeastern-Electric-Racing/Nero-2.0.

## Workflow

One issue carries a feature from idea to epic; everything else is its sub-issue.

1. **Idea**: what could be built and why, with open options. Every spike has one as parent; if none fits, draft it with the spike.
2. **Spike**: a sub-issue of the idea; one approach and what to learn. Findings go in comments and draft PRs.
3. **Epic**: once settled, rewrite the idea issue itself from the epic template, swap `idea` for `epic`, and set its issue type; don't open a new one. The approach and whole-epic outcomes, not a walkthrough of each ticket.
4. **Dev work**: a sub-issue of its epic, if any; testable requirements, Notes for gotchas and pointers to code.

If unsure, a small, clear change is dev work, a small unknown is a spike, and a big unexplored thing is an idea. Ideas and spikes never prescribe a solution; context transfer holds facts, not instructions.

## Draft

- Check the code first: the work may be done or already tracked. Leave unknowns as open questions in Notes.
- Short and plain; explain project-specific terms. One `### <field label>` per field in template order; omit empty optional fields.
- Requirements: broad bullets, 3-5 and never more than 7.
- Labels: the template's category, one written-by (`by: human` if the user dictated it, `by: ai-assisted` if they gave the substance, `by: ai` if you wrote it, including rewrites), and area labels.
- Rewriting an old ticket: keep its intent and assignees; update vocabulary (check the code, e.g. Zenoh key expressions, not MQTT topics), labels, issue type (epics and dev work only), and parent.
- Folding one ticket into another: add it as a requirement on the target, then close it as not planned. Every close gets a one-line comment saying why.

## File

Check for open duplicates, then show the full draft (title, type if any, labels, parent, body) in the chat, not only in a file. File or edit only what the user OKs.

Use the REST API (GraphQL may be blocked): POST repos/<owner>/<repo>/issues with title, body, labels, the type the template sets (epics and dev work; ideas and spikes get none), and the user as assignee (not on spikes, which stay unassigned), then POST repos/<owner>/<repo>/issues/<parent>/sub_issues with the new issue's id. Report the URL.
