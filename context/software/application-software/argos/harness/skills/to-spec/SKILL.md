---
name: to-spec
description: Turn the current conversation into a spec, review it as a PR, then publish it as an issue. No interview, just synthesis.
disable-model-invocation: true
---

Synthesize a spec from the conversation and the codebase. Don't interview the user.

1. **Tracking issue.** Use the existing issue, or create a stub one. Its number names the branch (`{issue-number}-{slug}`).
2. **Explore** the code in the area, using `CONTEXT.md` terms and respecting its ADRs.
3. **Test seams.** Propose where the feature will be tested: prefer existing seams, as high as possible, ideally one. Confirm with the user.
4. **Write** `docs/spec/<name>/spec.md` from the template and open it as a PR. Follow `docs/agents/spec-review.md` for review, publishing to the issue with `ready-for-agent`, and removing the file afterwards.

<spec-template>
## Problem Statement
The problem, from the user's perspective.

## Solution
The solution, from the user's perspective.

## User Stories
An extensive numbered list: "As a <actor>, I want <feature>, so that <benefit>".

## Implementation Decisions
Modules built or changed and their interfaces, architecture, schema and API contracts, and key interactions.

## Testing Decisions
The agreed seams, which modules get tested, and prior art. Test external behavior only.

## Out of Scope

## Further Notes
</spec-template>
