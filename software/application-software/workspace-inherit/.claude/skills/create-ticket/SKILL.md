---
name: create-ticket
description: Draft and file a GitHub issue (idea, spike, epic, or dev work) on an application-software repo (Argos, Nero) from the repo's issue templates, or rewrite an existing issue into them. Use whenever the user wants to create, file, write up, or log a ticket, issue, idea, spike, epic, bug, or task, including an out-of-scope idea that comes up mid-work.
---

# Create ticket

These are the ticket conventions for every application-software repo. The repo's own `.github/ISSUE_TEMPLATE` holds only the fields (`gh api repos/<owner>/<repo>/contents/.github/ISSUE_TEMPLATE/<file> -q .content | base64 -d`); follow each field's description.

First load the project's `ticket-conventions` skill (inherited from the project's `workspace-inherit/`) for its repo, area labels, vocabulary, and diagrams. If none is enabled, ask which repo.

## Workflow

idea → spikes → epic → dev work

| Ticket | What it is | Issue type | Parent |
|---|---|---|---|
| Idea | What could be built and why. Its approaches are areas (open questions), each with directions worth trying. | none | none |
| Spike | One direction to try in one area of an idea, or a small standalone improvement: what is tried and the hypothesis. Findings go in a comment and a draft PR (`report-spike`), not the ticket. | none | its idea, if any |
| Epic | A settled idea, filed by `consolidate-spikes` once every area of an idea has a chosen direction: the approach and whole-epic outcomes, not a walkthrough of each ticket. A new issue linking the idea in "From idea". | Feature | none |
| Dev work | Any implementation work: testable requirements, Notes for gotchas and pointers to code. Large work is cut into vertical slices (see Dev work below). | Feature, Bug, or Task | its epic, if any |

If unsure, a small, clear change is dev work, a small unknown is a spike, and a big unexplored thing is an idea. Ideas and spikes explore work, so they get no issue type; bug, feature, and task are issue types, never labels.

## Writing

How every ticket reads, on any project:

- Short and plain. Write for someone new to the project: explain project-specific terms, and use the project's vocabulary (its `ticket-conventions` says where it lives; check the code for current names).
- Outcomes, not implementation: say what changes and why, not how to build it. A rationale gives the reasoning, not a history of the problem.
- No prescriptions on ideas and spikes. Ideas name open options to weigh, not a plan or a recommended pick; spikes state what to learn and leave the how to whoever picks it up.
- Facts, not instructions: Notes and context transfer hold facts (where code lives, current behavior, constraints, links), not steps or a proposed solution. Context transfer (optional on spikes, epics, and dev work) starts with a short summary, then the raw context.
- Unknowns stay open questions in Notes; don't guess.
- Title: concise and imperative, no prefixes (except a spike's area).
- Requirements: clear, broad checkboxes, each a testable outcome rather than an implementation step; 3-5, never more than 7. If it needs more, split the ticket.
- Backticks: at most three inline uses per body; name files and identifiers in plain text. Diagram and context-transfer blocks don't count.
- Size: keep ideas short; one small enough to just try is a spike.

## Dev work

- One ticket by default. Split only when the work is too large for one PR or parts could run in parallel.
- When split, cut vertical slices: each goes end to end through every part it touches (e.g. backend through UI), not one layer, and works and is testable on its own. Cut for the most parallel work; mark a slice that must wait as blocked by the one it waits on (see File).

## Spikes

- One direction, not a set to choose between. If a spike reads "X or Y", it is two spikes.
- Prefer an idea with a few spikes (often 2-4) under it; a spike can also stand alone, or with siblings, to explore an area.
- Title it `<area>: <direction>`, with the area a short kebab-case name its siblings share (`graph-saving: Save a graph to a file and re-upload it`). An area may cover more than one of an idea's bullets. A lone small improvement needs no prefix.
- Sibling spikes share the context transfer's summary and common facts; each adds only the facts particular to its direction.
- An idea needn't get all its spikes at once: file an area's spikes when someone is ready to try them.

## Draft

- Check the code first: the work may be done or already tracked.
- One `### <field label>` per field in template order, following each field's description; omit empty optional fields.
- Diagrams: required on epics, optional on dev work. The project's `ticket-conventions` says what they show.
- Labels: the template's category (`idea`, `spike`, `epic`, `dev work`), one written-by (`by: human` if the user dictated it, `by: ai-assisted` if they gave the substance, `by: ai` if you wrote it, including rewrites), and at least one of the project's area labels.
- Rewriting an old ticket: keep its intent and assignees; bring it up to these rules and update vocabulary, labels, issue type, and parent.
- Folding one ticket into another: add it as a requirement on the target, then close it as not planned. Every close gets a one-line comment saying why.

## File

Check for open duplicates, then show the full draft (title, type if any, labels, parent, body) in the chat, not only in a file. File or edit only what the user OKs.

Use the REST API (GraphQL may be blocked): POST repos/<owner>/<repo>/issues with title, body, labels, the issue type from the table, and the user as assignee (on a spike, whoever will run it; ask), then, if it has a parent, POST repos/<owner>/<repo>/issues/<parent>/sub_issues with the new issue's id. If it waits on another issue, POST repos/<owner>/<repo>/issues/<n>/dependencies/blocked_by with the blocking issue's id. Report the URL.
