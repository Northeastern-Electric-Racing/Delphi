---
name: new-skill
description: Turn a workflow, a session, or a repeated correction into a new skill, or into a script or check when that enforces it better. Use when the user says "make this a skill", "automate this", "encode this", "we keep doing X", or after a session worth repeating.
---

1. **Source.** Name what you're encoding: this session, a workflow the user describes, or earlier sessions they point to (ask for the transcript or a summary; never read another project's history). State it back in one line.
2. **Look for a home first.** Read the description of every skill in `.claude/skills/`, inherited ones included, and the body of any that overlaps. If one fits, stop and use `reflect` to extend it instead. One more step in an existing skill beats a new skill.
3. **Pick the mechanism, highest first.** A script or check that fails when the step is skipped beats prose; write prose only for judgment calls. A skill can be a description plus one script call.
4. **Ask only what you can't see.** At most two multiple-choice rounds: when it should trigger, what "done" looks like, what must never happen. Take the rest from the source.
5. **Draft** `.claude/skills/<kebab-name>/SKILL.md`, applying `notes.md` for this kind of skill:
   - Frontmatter `name`, and a `description` that leads with when to use it (the user's words), then what it does.
   - Numbered imperative steps, each one an action an agent can tell it did. Name other skills instead of restating them.
   - Scripts go in `scripts/`, called as `bash scripts/<script>.sh <names>…`; they take only names and read the workspace from `$DELPHI_ROOT`. Name nothing harness-specific.
   - Needed by every Argos workspace, not just this one: say so, and land it in `workspace-inherit/` on `main` by PR (`AUTHORING.md`).
6. **Prove it.** Replay the source against the draft: would an agent reading it cold get the good outcome and avoid every correction the user made? Run each script it ships once. Fix what fails.

## Close out

1. **Feedback.** Show the draft and ask: approve, revise (what?), or drop. Apply each revision and ask again until approve or drop. Keep a one-line reason for each revision.
2. **Improve this skill.** From those revisions and any step here you skipped or improvised, propose up to three edits, one line each (what happened → the edit), tagged:
   - **general**: an edit to this `SKILL.md`, true for any skill.
   - **domain**: a bullet for `notes.md` under the kind of skill it was, true only for that kind.

   Apply only the ones the user approves. Nothing learned: say so and skip.
