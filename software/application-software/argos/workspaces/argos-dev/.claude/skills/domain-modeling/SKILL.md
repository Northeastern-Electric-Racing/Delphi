---
name: domain-modeling
description: Build and sharpen Argos's domain model. Use when discussing domain terminology, editing docs/CONTEXT.md, or recording or editing an ADR.
---

Actively build and sharpen the domain model as you design. Merely *reading* `docs/CONTEXT.md` for vocabulary is not this skill; this is for changing the model.

The glossary and ADRs are workspace docs, not files in `repos/argos/`: `docs/CONTEXT.md` and `docs/adr/` at the workspace root.

- **Challenge against the glossary.** When a term conflicts with `docs/CONTEXT.md`, call it out: "The glossary defines Run as X, but you seem to mean Y. Which is it?"
- **Sharpen fuzzy language.** Propose one canonical term for vague or overloaded ones: "CAN node or tree node?"
- **Test with scenarios.** Invent edge cases that force precise boundaries between concepts.
- **Check the code.** When the user says how something works, check `repos/argos/` and surface contradictions.
- **Update `docs/CONTEXT.md` as each term resolves**, matching its existing format: one or two sentences on what a term IS, an `_Avoid_` line of rejected synonyms, overloaded terms under Flagged ambiguities. Argos-specific terms only; no implementation details.
- **Offer an ADR only** when a decision is hard to reverse, surprising without context, and a real trade-off. Name it `docs/adr/<NNNN>-<prefix>-<topic-slug>.md` (next number, prefix per `repos/argos/docs/agents/domain.md`). A title plus 1-3 sentences of context, decision, and why is enough; add Considered Options or Consequences only when they earn it.
