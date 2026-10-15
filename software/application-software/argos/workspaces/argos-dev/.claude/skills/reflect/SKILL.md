---
name: reflect
description: Review a session (this one, or past ones the user points to) for what went wrong or took too long, and turn each lesson into an edit to the skill, workflow, or CLAUDE.md that was in use. Use when the user says "reflect", "what can we learn", "improve this skill/workflow", or after corrections or a rough session.
---

1. **Scope.** Which sessions, and which skills, workflows, or agents to improve. Default: this session and every skill it used. For past sessions, ask for the transcript or a summary; never read another project's history. State the scope back.
2. **Evidence.** List in turn order, citing each (a quote or the command): user corrections, retries, context the user handed over that you could have fetched, facts you re-derived, skill steps skipped or improvised. No diagnosis yet.
3. **Review in parallel.** Give three read-only subagents the evidence and the skills in scope, each returning problem / evidence / edit / target file:
   - Judgment: where was a decision wrong, and what rule would have made it right?
   - Tooling: what command, path, or fact had to be rediscovered, and what could have been fetched instead of asked for?
   - Divergent: what step, skill, or workflow should be cut, merged, or shaped differently?
4. **Filter.** Keep a finding only if it stays true once paths and versions change, recurred or cost real time, and changes what a future agent does. Read the target first: if it already says this and was skipped, make it more prominent instead of adding. Findings from two or more reviewers rank first.
5. **Pick the mechanism, highest first:** delete or merge a step; a script or check that fails; a `description` fix when the skill didn't trigger; prose last. A recurring lesson with no home goes to `new-skill`.
6. **Propose** one table and apply nothing yet, then list rejected findings one line each with the reason.

   | Problem | Edit | Target | Mechanism |
   |---|---|---|---|

## Close out

1. **Feedback.** The user approves, revises, or rejects each row; ask again after revisions until every row is settled. Keep a one-line reason for each revision. Then apply the approved rows:
   - This workspace's own files: edit them here.
   - Inherited skills (from a `workspace-inherit/`; sync overwrites them here): park the edit with `journal`, then PR it to `main` (`AUTHORING.md`).
   - `.delphi/`, `.claude/settings.json`, `.github/workflows/delphi.yml`: never edit; report the finding instead.
2. **Improve this skill.** From those revisions and any step here you skipped or improvised, propose up to three edits, one line each (what happened → the edit), tagged:
   - **general**: an edit to this `SKILL.md`, true for any review.
   - **domain**: a bullet for `../new-skill/notes.md` under the kind of skill reviewed, true only for that kind.

   Apply only the ones the user approves. Nothing learned: say so and skip.
