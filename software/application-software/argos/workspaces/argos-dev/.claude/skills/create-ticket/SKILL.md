---
name: create-ticket
description: Draft and file a GitHub issue (idea, spike, epic, or dev work) on Argos or Nero from the repo's issue templates, or rewrite an existing issue into them. Use whenever the user wants to create, file, write up, or log a ticket, issue, idea, spike, epic, bug, or task, including an out-of-scope idea that comes up mid-work.
---

# Create ticket

The templates in .github/ISSUE_TEMPLATE are the source of truth, with conventions in docs/agents/issue-tracker.md. Read the template you need (`gh api repos/<owner>/<repo>/contents/.github/ISSUE_TEMPLATE/<file> -q .content | base64 -d`) and follow its field descriptions. Nero is Northeastern-Electric-Racing/Nero-2.0.

Pipeline: idea → spikes → epic → dev work. If unsure, a small thing is a spike and a big unexplored thing is an idea.

**Before drafting**
- Check the code first: the work may already be done, or tracked under another number.
- Rewriting an old ticket: carry over its intent, but use the project's current vocabulary (check the code; for example, Zenoh key expressions rather than MQTT topics).
- Leave unknowns as open questions in Notes. Don't invent answers.

**Draft**
- Keep it short. Plain words; explain any project-specific term the reader may not know.
- One `### <field label>` per field, in template order; omit empty optional fields.
- Idea and spike: never prescribe a solution. Ideas list open options; spikes say what to learn. Context transfer holds facts, not instructions.
- Epic: the approach without a walkthrough of each ticket; requirements are outcomes for the whole epic, not one per sub-issue.
- Dev work: testable requirements; Notes can carry gotchas and pointers to code.
- Labels: the template's category, one written-by (`by: human` if the user dictated it, `by: ai-assisted` if they gave the substance, `by: ai` if you wrote it, including rewrites of old tickets), and area labels.
- Rewriting an old ticket: keep assignees, swap in current labels, set the issue type, link it under its epic.
- Folding one ticket into another: add it as a requirement on the target, then close it as not planned with a comment pointing there. Closing any ticket gets a one-line comment saying why.

Check for open duplicates, then show the full draft (title, type, labels, parent, body) in the chat, never only in a file. Get the user's OK before filing or editing, and file only what they asked for.

**File** with the REST API (GraphQL may be blocked): POST repos/<owner>/<repo>/issues with title, body, type, labels and the user as assignee. For a parent, POST repos/<owner>/<repo>/issues/<parent>/sub_issues with the new issue's id. Report the URL. When an epic comes from an idea, offer to close the idea as completed.
