# Shutdown Loop page: agent review loop (paused)

Improving Argos PR #1025 (Shutdown loop page) on four throwaway branches, all pushed to Northeastern-Electric-Racing/Argos:

| Branch | Head | Builds on |
|---|---|---|
| throwaway-shutdown-logic-scylla | d01e0b9f | shutdown-loop-page (PR #1025) |
| throwaway-shutdown-ui | 6bde6a19 | logic-scylla |
| throwaway-shutdown-3d-procedural | 4df0fb6b | ui |
| throwaway-shutdown-3d-gltf | 40739def | ui |

Loop per round: implement -> run-local -> 3 reviewers per branch (correctness, live QA, spec/integration) -> judge per branch -> teardown.

- round1/: 12 reviews + 4 judge files (judge-ui.md holds the shared contract). Round 2 implemented every judge MUST.
- round2/: 8 of 12 reviews finished. Not finished (hit the usage limit): logic-correctness, logic-live, proc-correctness, ui-live, gltf-correctness, proc-live (a partial proc-live.md exists). No round-2 judges yet.

Decisions already made for round 3:
- ADR 0010 (three.js 3D car view), status Proposed, neutral on the car source and identical in both 3D branches (overrides judge-gltf R4).

To resume: rerun the 6 unfinished round-2 reviews (round2/BRIEF.md is the shared brief), then the round-2 judges, then round-3 implementation.
