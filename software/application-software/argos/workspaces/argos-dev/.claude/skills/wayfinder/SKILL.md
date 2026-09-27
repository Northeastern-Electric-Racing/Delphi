---
name: wayfinder
description: Plan a huge chunk of work (more than one agent session can hold) as a shared map of decision tickets on the Argos issue tracker, and resolve them one at a time until the way to the destination is clear.
disable-model-invocation: true
---

A loose idea too big for one session, wrapped in fog: the way to the **destination** (a spec to hand off, a decision to lock, or an in-place change) isn't visible yet. Chart the way as a **map** on GitHub Issues, then resolve its **decision tickets** one at a time until the route is clear.

- **Plan, don't do.** Tickets resolve decisions, not slices of the build. The pull to just do the work means you've reached the edge of the map: hand off. The map's Notes may override this.
- **Refer by name.** Name maps and tickets by title with the link inside it, never a bare `#42`.
- **Tracker mechanics** (map, child issues, blocking, frontier query, claim, resolve): the Wayfinding operations section of `repos/argos/docs/agents/issue-tracker.md`.

## The map

One issue labelled `wayfinder:map`; tickets are its child issues. It's an index: a decision lives only in its ticket, the map gists and links it. Open tickets aren't listed; query for them.

```markdown
## Destination
<what reaching the end looks like, one or two lines>

## Notes
<domain; skills every session should consult; standing preferences>

## Decisions so far
- [<closed ticket title>](link): <one-line gist>

## Not yet specified
<in-scope fog you can't ticket yet>

## Out of scope
<work ruled beyond the destination, with why and a link>
```

## Tickets

A child issue sized to one 100K-token session: label `wayfinder:<type>`, body `## Question` plus the decision it resolves. Answers go in a resolution comment; assets are linked, not pasted. Claim by assigning the driving dev before any work. Blocking uses GitHub's native dependencies; the **frontier** is open, unblocked, unclaimed children.

HITL tickets resolve only through live exchange with the human; never answer your own questions.

- **research** (AFK): a subagent calls the Skill tool with "research".
- **prototype** (HITL): call the Skill tool with "prototype"; link the result.
- **grilling** (HITL, default): call the Skill tool for "grilling" and "domain-modeling".
- **task** (AFK, or a HITL checklist): work that must happen before a decision, like provisioning access. The answer records what was done and facts later tickets need.

## Fog and scope

- Ticket a question you can state precisely now, even if blocked. Otherwise write it loosely under Not yet specified; don't pre-slice it.
- Resolutions graduate fog into tickets; remove each graduated patch from Not yet specified.
- Work past the destination is out of scope, never fog. Close such a ticket and add one line under Out of scope, not Decisions so far.

## Invocation

At most one ticket resolved per session (research excepted). Expect other sessions editing the tracker concurrently.

**Chart** (user gives a loose idea):
1. Grill ("grilling" + "domain-modeling") to name the destination.
2. Grill again, breadth-first, for open decisions and first steps. No fog? Stop and ask how to proceed.
3. Create the map with fog under Not yet specified, then the tickets you can specify now, then wire blocking in a second pass.
4. Start a research subagent per research ticket. Stop: charting resolves nothing.

**Work** (user gives a map; a ticket is optional):
1. Load the map body only. Take the named ticket, else the first frontier ticket, and claim it.
2. Resolve it, zooming into related tickets and using the skills in Notes.
3. Comment the answer, close it, and add a line to Decisions so far.
4. Create-then-wire new tickets, graduate fog, rule past-destination tickets out of scope, and fix tickets the decision invalidates.
