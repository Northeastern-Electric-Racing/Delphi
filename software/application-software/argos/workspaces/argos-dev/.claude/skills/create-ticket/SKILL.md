---
name: create-ticket
description: Draft and file a GitHub issue (idea, spike, epic, or dev work) on Argos or Nero from the repo's issue templates, or rewrite an existing issue into them. Use whenever the user wants to create, file, write up, or log a ticket, issue, idea, spike, epic, bug, or task.
---

# Create ticket

The templates in .github/ISSUE_TEMPLATE are the source of truth, with conventions in docs/agents/issue-tracker.md. Read the template you need (`gh api repos/<owner>/<repo>/contents/.github/ISSUE_TEMPLATE/<file> -q .content | base64 -d`) and follow its field descriptions. Nero is Northeastern-Electric-Racing/Nero-2.0.

Pipeline: idea → spikes → epic → dev work. If unsure, a small thing is a spike and a big unexplored thing is an idea.

**Draft**
- One `### <field label>` per field, in template order; omit empty optional fields.
- Idea and spike: never prescribe a solution. Ideas list open options; spikes say what to learn. Context transfer holds facts, not instructions.
- Epic: the approach without a walkthrough of each ticket; requirements are outcomes for the whole epic.
- Dev work: testable requirements; Notes can carry gotchas and pointers to code.
- Labels: the template's category, one written-by (`by: human` if the user dictated it, `by: ai-assisted` if they gave the substance, `by: ai` if you wrote it, including rewrites of old tickets), and area labels.
- Rewriting an old ticket: keep assignees, swap in current labels, set the issue type, link it under its epic.

Check for open duplicates, then show the full draft (title, type, labels, parent, body) in the chat and get the user's OK before filing or editing.

**File** with the REST API (GraphQL may be blocked): POST repos/<owner>/<repo>/issues with title, body, type, labels and the user as assignee. For a parent, POST repos/<owner>/<repo>/issues/<parent>/sub_issues with the new issue's id. Report the URL. When an epic comes from an idea, offer to close the idea as completed.
