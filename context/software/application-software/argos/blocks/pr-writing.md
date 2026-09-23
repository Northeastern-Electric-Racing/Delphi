## PR writing rules

**PR style for this repo:**
- Changes section: precise and dense. Aim for 1–3 short sentences that tell a reviewer exactly what landed and the key design decision. Bullets are optional and only earn their place if they add information the prose doesn't already cover (a second concrete change, a non-obvious file, a tradeoff). If your bullets would just restate the prose in list form, drop them.
- No filler in Changes: skip "this is a building block for X", "lays the groundwork for Y", or future-facing motivation — that goes in Notes if it matters at all. Skip "when on… when off…" narration; state the behavior directly. Skip aspirational marketing ("polished", "robust", "comprehensive").
- Tone: casual but technical — describe what was done and the why behind a non-obvious choice, not how it was implemented step by step
- Test Cases: brief abstract descriptions of what was tested, not CLI commands or screenshots
- Remove sections that don't apply (Screenshots if no UI changes, To Do if nothing remaining)
- Always fill in Changes and Checklist with real content; check off all applicable Checklist items with [x]
- Always end with `Closes #NNN` on its own line referencing the GitHub issue (extract the ticket number from the branch name or commits)
- Notes section: mention anything a reviewer should know — tradeoffs, edge cases, follow-up work, or future-direction context that would otherwise bloat Changes. Omit if nothing to note.

**Example Changes section (good — precise):**
> Adds a Flat toggle to the graph sidebar topic tree (desktop + mobile) that swaps the nested tree for an alphabetical flat list of leaves. Labels show the full path when it fits a 30-char budget, otherwise compact to firstSegment...tail. Selection state is preserved across toggles.

**Example Changes section (bad — verbose, redundant bullets, filler):**
> Adds a Flat toggle to the graph sidebar topic tree (desktop and mobile). When on, the tree renders as a flat alphabetical list of leaves; when off, it returns to the nested tree with selection state preserved across the toggle. This is a building block for selected-topics-only views.
>
> - New flattenTreeNodes + compactTopicLabel helpers in src/utils/tree.utils.ts
> - Toggle UI (PrimeNG ToggleSwitch) wired into the desktop and mobile sidebar headers
> - Flat labels show the full path when it fits (default 30-char threshold) and otherwise compact to firstSegment...tail, keeping as much of the tail as fits

The bad version repeats the same information in prose and bullets, narrates the toggle behavior instead of stating it, and pre-pitches a future feature in Changes.

**Screenshot rule (CRITICAL):**
- Only `user-attachments/assets/...` URLs (drag-and-dropped by the user via the GitHub web UI) belong in the Screenshots section
- **Never** commit screenshots to the repo or write any committed image path, `raw.githubusercontent.com` URL, SHA-pinned raw URL, or local file path into the Screenshots section
- If UI changes need new screenshots, add a `_screenshot pending_` placeholder (alongside any preserved ones) — do not link to local files
- Afterwards, if screenshots were captured locally under `pictures/<branch>/`, report the full paths to the user and remind them to drag-drop the relevant ones into the PR body via the GitHub web UI themselves

**Writing shape (borrowed from Matt's writing-shape skill):**
- Pick the format that fits the content: prose for narrative or rationale, a bulleted list only for genuinely parallel items, a table when comparing across two or more dimensions, a callout (blockquote) for a single warning or caveat. Default to prose; reach for the others only when the content's shape calls for it.
- Reader filter: before keeping any paragraph or bullet, ask what it does for the reviewer. If the answer is nothing they can act on or learn from, cut it. Same earn-its-place test as the Changes guidance above, run as one deliberate pass over the finished body.

**Backtick rule:** Max 3 backtick usages in the entire PR description. You can reference files, functions, and identifiers without backticks — only use them for commands worth copy-pasting.

**Body file:** write the body to `/tmp/<branch-name>-pr-body.md`, where `<branch-name>` is the current git branch (`git branch --show-current`). Using a branch-specific filename avoids stale content from previous PRs leaking in.
