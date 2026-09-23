---
name: grill-with-docs
description: Grill the user relentlessly about a plan or design, recording the glossary and ADRs as decisions land. Use when the user wants to stress-test a plan before building, or uses any 'grill' trigger phrases.
---

Interview me about every aspect of this plan until we share an understanding. Walk each branch of the design tree, resolving dependencies between decisions one by one.

- Ask one question at a time, with your recommended answer, and wait for mine.
- Look up facts in the code yourself. Put decisions to me. If the code contradicts what I say, point it out.
- Hold me to `docs/CONTEXT.md`. Call out a term that conflicts with it, pin down fuzzy terms, and test boundaries with concrete edge-case scenarios.
- When a term is resolved, update `docs/CONTEXT.md` right away. It's a glossary only, with no implementation details.
- Offer an ADR in `docs/adr/` only when a decision is hard to reverse, surprising without context, and a real trade-off. Match the format of the existing entries.
- Don't enact the plan until I confirm we're aligned. Next step: `/to-spec`.
