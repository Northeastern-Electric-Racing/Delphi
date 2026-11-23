# Review round 1: throwaway-shutdown-ui (conventions, architecture, integration)

Branch `throwaway-shutdown-ui` (1 commit, bf6f70ae) against `origin/shutdown-loop-page`. Paths below are relative to `angular-client/src/pages/shutdown-page/` unless they say otherwise.

What I checked:
- `npx eslint src/pages/shutdown-page` is clean and `prettier --check` passes.
- `ng test --include=src/pages/shutdown-page/**` passes: 11 files, 108 tests.
- `git merge-tree` against all three sibling branches.
- The merged ui+logic tree, unpacked into the scratchpad: `tsc` is clean and the shutdown specs pass (12 files, 138 tests).
- The merged ui+3D trees with the ui page files kept: `tsc -p tsconfig.spec.json` fails (details under Integration conflicts).
- Convention greps found no default-palette class, arbitrary colour, `!` modifier, `dark:`, `::ng-deep`, text opacity, `styleUrls` or inline `style=`. The only `[style.left.%]`/`[style.top.%]` bindings carry data-driven positions, which is acceptable.
- Arbitrary values are all layout values, not colours or font sizes, so the conventions allow them (see the nits).

Counts: 1 blocker, 6 major, 10 minor, 6 nits.

## Findings

- **blocker**: `shutdown-loop.display.ts:13-29` (StateDisplay), plus the deletion of `shutdown-states.css`
  - **Issue:** the branch removes `NODE_STATE_DISPLAY[state].cssClass` and the `--sd-color` custom property and puts nothing in their place that a non-Tailwind consumer can read. StateDisplay now holds only Tailwind class lists.
  - **Why:** both 3D branches read state colours through `cssClass` and `--sd-color` probes, and three.js needs raw colour values. After the merge they fail to compile (9× TS2339, listed under Integration conflicts) and fail to build (`styleUrls: ['../../shutdown-states.css']`). If those lines are patched out, the probes return '' and the 3D view falls back to off-theme hex values, so suspect shows NER-ish red `#ff4d4d` while 2D shows danger orange.
  - **Fix:** add a theme-token name per state to StateDisplay (`token: '--color-success' | …`) and a `readStateColours()` helper. The full API is under Proposed shared contract §2. Land it in this branch before any 3D branch rebases.

- **major**: `shutdown-selection.store.ts:38-56`, `components/car-view/car-view.component.ts:97-101,118-133`, `components/loop-strip/loop-strip.component.ts:67-71,99-114`
  - **Issue:** roving focus, the single tab stop, `aria-selected` and selection-follows-focus are hand-rolled, and the same code is copied in both views. `onKeydown` and `tabStopId` are identical in each, and the spec tests are duplicated too. The procedural 3D branch has a third copy (`onToolbarKey`).
  - **Why:** ADR 0007 and the CONTEXT.md conventions say shared behaviour is a primitive on Angular Aria or the CDK. `@angular/aria/listbox` 22.2.3 is installed and already used by `ui/select`. Its defaults are `focusMode='roving'` and `selectionMode='follow'`, which is exactly what was rebuilt here. It also brings typeahead by `label` (type "T" to reach TSMS), managed `tabindex` and `aria-orientation`.
  - **Fix:** in both views use `ngListbox orientation="horizontal" [wrap]="false" [value]="selectedIds()" (valueChange)="nodeSelect.emit($event[0] ?? null)"` with `ngOption [value]="id" [label]="label"`. Keep only Escape (host `keydown.escape`) and hover preview as custom code. Delete `rovingIndex` and its tests.
  - **Trade-off:** Aria makes the selected option (else the first) the tab stop, not the first suspect. That is acceptable because the banner chips already jump to the cause. If the first-suspect tab stop must stay, wrap the behaviour in one primitive under `src/ui/` instead of in a page store.

- **major**: `components/car-view/car-view.component.html:41` and `shutdown-loop.model.ts:28-31,25-27,36`
  - **Issue:** car markers are `size-5` (20 px) below `sm`, which is under the 24×24 px target minimum in the conventions. They also overlap. The four latches sit 2.8–2.9 % apart (x = 58.7 / 61.6 / 64.4 / 67.2), and the side BRBs and GLVMS/TSMS are about 3–4 % apart.
    - At 390 px (about 350 px of drawing) that is roughly 10 px between centres for 20 px markers.
    - Between `sm` and `lg` (about 700 px of drawing) it is roughly 20 px between centres for 28 px markers.
    - `hover:scale-125` makes it worse.
  - **Why:** this fails WCAG 2.5.8 (the spacing exception does not apply to overlapping targets), and taps land on the wrong loop node.
  - **Fix:** give the E-box latches and the hoop cluster offset badges with leader lines (positions in the model, the anchor dot stays at the real spot), or one cluster marker that expands. Minimum `size-6` everywhere.

- **major**: `components/node-detail/*` (selector `node-detail`, `aria-label="Node details"` at html:2, "Selected node" at html:7, "Select a node…" at html:46), `shutdown-page.component.html:30` ("arrow keys move between nodes"), and the contract names `nodeSelect`/`nodePreview`
  - **Issue:** new public names and user-facing copy use a bare "node".
  - **Why:** the CONTEXT.md "Flagged ambiguities" section says Node means a CAN device (`Bms`/`Dti`/…) and must always be qualified. This branch also defines the view contract the other three branches will adopt, so renaming after they merge means more conflicts.
  - **Fix:**
    - Add a glossary entry "**Loop node** — one element of the shutdown loop (`LoopNode`); not a CAN node" to `docs/CONTEXT.md`.
    - Rename the component to `loop-node-detail` / `LoopNodeDetailComponent`.
    - Use "loop node" in the copy ("Loop node details", "Selected loop node", "arrow keys move along the loop").
    - Name the contract outputs `loopNodeSelect`/`loopNodePreview`, or keep `nodeSelect` and say in the contract that "node" means loop node. Decide once, now.
    - Leave the pre-existing `NodeState`/`NodeStatus`/`NodeKind` types alone until all four branches have merged, then rename them in one mechanical commit (`LoopNodeState`, …) so the merges don't fight.

- **major**: `components/loop-banner/loop-banner.component.ts:96`, `shutdown-loop.display.ts:216,236-241`, `components/mock-panel/mock-panel.component.html:7`
  - **Issue:** staleness is shown as a fixed 60 s per board: "No data from BMS for over 60 s", "No message from the VCU for …", and `boardFreshness` marks stale only at `STALE_AFTER_MS`.
  - **Why:** throwaway-shutdown-logic-scylla replaces board-level staleness with per-reading adaptive staleness (`staleAfterMs`, clamped 3–60 s, 5× the smoothed interval) and derives the CAN latch from the critical faults. The merge is textually clean and all 138 tests pass (verified), so nothing catches the wrong text that results:
    - The banner says "for over 60 s" after 3 s.
    - The header chip shows "VCU 4 s ago" as fresh while the banner calls the VCU silent.
    - The CAN latch shows "No message from the VCU" while the VCU's 0x123 is live.
  - **Fix:** contract §4. Drive the copy from NodeStatus, not from constants.

- **major**: the whole branch has no display of `LoopStatus.source`; see also `shutdown-loop.display.ts:174-219` (explainNode)
  - **Issue:** the logic branch adds `source: 'local' | 'server'`. When it is `'server'`, the states come from scylla-server, but `explainNode` still reasons from local values ("Reads 0 while the reading before it is closed…").
  - **Why:** the page can show a server-decided state next to an explanation that local readings contradict, and nothing tells the user which side decided.
  - **Fix:** add a source chip in `loop-meta` ("Status: scylla" / "Status: this client"). When `source === 'server'`, explainNode should explain from the states and say the server decided. Spec test both.

- **major**: `shutdown-selection.store.ts:7-14`
  - **Issue:** the view contract exists only as a doc comment. Nothing enforces it, and the 3D branches already diverge from it:
    - they keep their own `selectedId` signal (procedural `car-view-3d.component.ts:59`, gltf `:108`);
    - they toggle on click;
    - they use `aria-pressed` toolbars and badges instead of listbox options;
    - each has its own detail panel.
  - **Why:** an unenforced contract between four branches will drift again.
  - **Fix:** make it a TypeScript interface (`LoopView`, contract §1) that every view `implements`, plus one shared spec helper that runs the contract tests against each view.

- **minor**: `components/car-view/car-view.component.html:64` (`status-glyph class="max-sm:hidden"`)
  - **Issue:** on phones the car markers lose their icon, so closed and cause are both solid discs that differ only in colour (green vs orange).
  - **Why:** this contradicts `shutdown-loop.display.ts:9`, which says state is never colour alone (WCAG 1.4.1). The strip below does carry text, which is why this is minor.
  - **Fix:** keep the glyph at `size="xs"` inside a `size-6` marker, or vary the shape (for example a square for the cause).

- **minor**: `shutdown-page.component.html:3`
  - **Issue:** the page title moved from `<h1>` (base) to `<typography>`, which renders a `<p>`, so the page has no h1. The h2s ("Loop order", the detail title) now hang under nothing.
  - **Why:** heading structure (1.3.1 / AXE `page-has-heading-one`). Other pages share the pattern, but this is a regression from the PR being restyled.
  - **Fix:** `<h1 [class]="titleClass">` with `typographyClass('x-large-title', 'max-md:text-title')`.

- **minor**: `shutdown-page.component.html:13,23` and `components/node-detail/node-detail.component.html:3`
  - **Issue:** the same panel look (`rounded-md border border-solid border-border bg-surface-1 p-3/4`) is written out three times. NODE_STATE_DISPLAY is itself a recipe kept inside the page.
  - **Why:** the conventions say a look used in more than one place is a recipe of complete `tw()` lists.
  - **Fix:** one `panelClass` constant (page-local is fine if documented, or `src/ui/recipes/`). Reuse it for the 3D view's frame when it merges.

- **minor**: `components/loop-strip/loop-strip.component.spec.ts:53`
  - **Issue:** `expect(el.textContent).toContain('Cause')` in "brackets the suspect stretch" passes because of the strip's short label "Cause". For a single culprit the bracket label is "Broke the loop", so the test is vacuous for the stretch bracket.
  - **Fix:** assert `'Broke the loop'`, and assert the "Suspect stretch" label for a multi-node stretch.

- **minor**: `components/car-view/car-view.component.spec.ts` and `shutdown-page.component.spec.ts`
  - **Issue:** the car-view spec doesn't cover Enter/Space/Escape/End. The page spec never checks that a banner chip click reaches the strip, car and detail.
  - **Why:** the banner's buttons are the fastest path to the cause and are untested end to end.
  - **Fix:** add those tests, or fold them into the shared contract spec helper.

- **minor**: `components/car-view/car-view.component.html:50-51` and `components/loop-strip/loop-strip.component.html:21-22`
  - **Issue:** pointer users cannot clear the selection (only Escape does). The 3D branches toggle on click instead.
  - **Why:** inconsistent semantics across views, and the detail panel stays pinned.
  - **Fix:** settle it in the contract: click selects without toggling, Escape clears, and the loop-node detail panel gets a "Show the break" or close button (`uiIconButton`) that calls `select(null)`.

- **minor**: `components/car-view/car-view.component.ts:125-127` and `components/loop-strip/loop-strip.component.ts:106-108`
  - **Issue:** Escape clears the selection, so `tabStopId` jumps to the first suspect and the focused element is left with `tabindex=-1`.
  - **Why:** Tab out and back lands somewhere else, which is odd.
  - **Fix:** this goes away with Aria Listbox. Otherwise keep the focused option as the tab stop.

- **minor**: `components/car-view/car-view.component.html:57`
  - **Issue:** `motion-safe:animate-ping` runs forever on every cause marker.
  - **Why:** WCAG 2.2.2 (moving content longer than 5 s, alongside other content, with no pause). `motion-safe` only covers users who set reduced motion.
  - **Fix:** limit it to a few iterations when the verdict changes (`[animation-iteration-count:3]`, keyed on the break id).

- **minor**: `shutdown-loop.display.ts:90-110` (SHORT_LABEL)
  - **Issue:** a second id-keyed table sits beside `SHUTDOWN_LOOP`, so adding a loop node takes two edits. The 3D badges and labels need short names too.
  - **Fix:** move `short` onto `LoopNode` in `shutdown-loop.model.ts`.

- **minor**: `components/loop-strip/loop-strip.component.html:5` and `components/car-view/car-view.component.ts:118-133`
  - **Issue:** the strip declares `aria-orientation="horizontal"` yet also moves on Up/Down. The car view's listbox has no orientation.
  - **Why:** ARIA semantics don't match the behaviour.
  - **Fix:** Aria Listbox sets this for you. Use one orientation per view.

- **nit**: `components/loop-strip/loop-strip.component.html:36` (`top-[22px]`, `w-[calc(100%+4px)]`), `components/car-view/car-view.component.ts:35` (`-translate-x-[calc(100%-16px)]`) and `car-view.component.html:81` (`-translate-y-[calc(100%+18px)]`)
  - **Issue:** magic pixel values tied to `size-9`, `pt-1.5`, `border-3` and the marker size. They are allowed (not colours or type sizes) but break silently when sizes change.
  - **Fix:** add a comment naming what each value is derived from, or place the connector with `top-1/2` on a wrapper around the disc.

- **nit**: `components/car-view/car-view.component.html:4`
  - **Issue:** `aspect-[1000/535]`.
  - **Fix:** Tailwind v4 takes the bare ratio `aspect-1000/535`.

- **nit**: `components/car-view/car-view.component.html:70-71`
  - **Issue:** the mismatch badge is a literal "!" glyph.
  - **Fix:** `<ui-icon name="priority_high" size="xs" />`, per the icon convention.

- **nit**: `shutdown-loop.display.ts:87`
  - **Issue:** `PLACEHOLDER_TAG` is now unused in this branch (the strip prints a literal "placeholder"), but 3d-gltf still imports it.
  - **Fix:** use it in the strip and the detail notes, or keep it and list it in the contract.

- **nit**: `components/car-view/car-view.component.html:50-51` and `components/loop-strip/loop-strip.component.html:21-22`
  - **Issue:** a mouse click emits `nodeSelect` twice (focus, then click).
  - **Why:** harmless today, but every future store side effect (3D camera fly-to) runs twice.
  - **Fix:** this goes away with Aria Listbox.

- **nit**: `shutdown-page.component.html:27` and `components/node-detail/node-detail.component.html:12`
  - **Issue:** the headings use ad hoc type classes.
  - **Fix:** `typographyClass('header', 'm-0')` exists. Optional.

## Integration conflicts

Each merge below was checked with `git merge-tree` or by type-checking the merged tree in the scratchpad.

1. **ui + throwaway-shutdown-logic-scylla merges textually clean.** `tsc` is clean and 12 files / 138 tests pass on the merged tree. The conflicts are semantic, and nothing fails:
   - `loop-banner.component.ts:96` still says "for over ${STALE_AFTER_MS/1000} s". `STALE_AFTER_MS` is still exported but is now only the upper clamp. The spec at `loop-banner.component.spec.ts:113` locks in the wrong text.
   - `display.ts:236-241` `boardFreshness` uses a fixed 60 s, which disagrees with the logic branch's `boardLive`: a board is live if any of its readings is live.
   - `display.ts:216` blames the board ("No message from the VCU"). Under the logic branch a single reading can be stale on its own, notably the CAN latch derived from the 0x502 faults.
   - The logic branch's `LoopStatus.source` is never shown, and explainNode can contradict server-decided states.
   - `loop-meta`'s `tsOn` chip still works: the logic branch changed what "undefined" means (stale BMS/Shutdown/State reading) but not its type.
   - `mock-panel.component.html:7` "stale after 60 s".
2. **ui + throwaway-shutdown-3d-procedural.**
   - **Text:** CONFLICT in `shutdown-page.component.html` and `shutdown-page.component.ts`. The 3D branch swaps `<car-view [nodes]>` for `<car-view-switcher [nodes]>` inside the base `<section class="panel">` and swaps the import. The ui branch rewrote both files.
   - **Compile:** keeping the ui page files gives 5× TS2339 `cssClass` errors: `car-view-3d.component.ts:68,79`, `car-view-3d.model.ts:76,93`, `car-view-3d.model.spec.ts:41`.
   - **Build:** `car-view-3d.component.ts:42` has `styleUrls: ['../../shutdown-states.css', …]`, and that file is deleted.
   - **Runtime:**
     - The `--sd-color` probes (`:182-185`, html `.probes`) return '', so the view uses `DEFAULT_SCENE_COLORS.states` (`model.ts:187`: `#2fd35a/#ff4d4d/#8a8a8a/#8b93a1`, not theme tokens).
     - Its `SCENE_COLOR_TOKENS.hv = '--color-danger'` (`model.ts:196`) is the colour this branch gives the cause, so HV parts would look like faults.
     - It keeps its own `selectedId` signal (`:59`), a toggle on click, a `role="toolbar"` with `aria-pressed`, and its own detail panel, so it is not linked to the strip, banner or detail.
     - Its fallback `<car-view [nodes]>` binds no selection.
     - `car-view-3d.component.css` (133 lines) and the base strip and car-view CSS it still assumes conflict with the utilities-only convention.
3. **ui + throwaway-shutdown-3d-gltf.**
   - **Text:** CONFLICT in the same two page files (`<car-view-switch>`).
   - **Compile:** 4× TS2339 `cssClass` errors: `car-view-3d.component.ts:114,120,138`, `car-view-3d.utils.ts:83`.
   - **Build:** `car-view-3d.component.ts:81` `styleUrls` points at the deleted `shutdown-states.css`.
   - **Runtime:**
     - `resolveStateColours` probes `--sd-color` and falls back to `FALLBACK_STATE_COLOURS` (`utils.ts:69-74`, the same off-theme hex values). `car-view-3d.utils.spec.ts:124` pins `'#8b93a1'`.
     - It has its own `selectedId` signal (`:108`), aria-pressed badges, its own detail panel, and imports `PLACEHOLDER_TAG`.
   - `car-view-3d.component.css` has 138 lines of component CSS.
4. **The 3D branches against each other.** Both add `components/car-view-3d/*`, `shutdown-loop.positions-3d.ts` and `three` in `package.json`, under two names for the switch (`car-view-switcher` vs `car-view-switch`). Pick one 3D branch and port only what is needed from the other.
5. **Recommended merge order:**
   1. logic (no textual conflict with anything here);
   2. ui, rebased on logic, with contract §2–§4 applied;
   3. the chosen 3D branch, rebuilt on the contract: utilities instead of CSS, tokens instead of `--sd-color`, the store instead of local selection, and node-detail instead of its own panel.

## Proposed shared contract

Settle this in `throwaway-shutdown-ui` before anything rebases. All four branches then code against it.

### 1. Selection: one store, one view interface (`shutdown-selection.store.ts`, plus a new `loop-view.ts`)

```ts
// The store stays as it is (page-provided, reset on leave), minus rovingIndex.
@Injectable() export class ShutdownSelectionStore {
  readonly selectedId: Signal<string | null>;  // pinned loop node
  readonly previewId: Signal<string | null>;   // pointed at anywhere on the page
  readonly activeId: Signal<string | null>;    // previewId ?? selectedId: highlight + detail panel
  select(id: string | null): void;             // idempotent, no toggle
  preview(id: string | null): void;
}

// loop-view.ts: every view of the loop implements it (strip, 2D car, 3D car, and the switch that wraps the car views).
export interface LoopView {
  nodes: InputSignal<NodeStatus[]>;              // loop order, straight from LoopStatus.nodes
  selectedId: InputSignal<string | null>;
  previewId: InputSignal<string | null>;
  nodeSelect: OutputEmitterRef<string | null>;   // click/tap, Enter/Space, focus (selection follows focus); null on Escape
  nodePreview: OutputEmitterRef<string | null>;  // pointer enter (3D: raycast hover); null on leave
}
```

The rules every view follows:
- **A view never owns selection.** Delete `selectedId = signal()` in both 3D views.
- **One detail panel.** `loop-node-detail` is the only one; delete the 3D in-view panels.
- **Keyboard.** Every focusable set of loop nodes is an Aria `ngListbox` (`orientation="horizontal"`, `[wrap]="false"`, selection follows focus) with `ngOption [value]=id [label]=label`. That covers the strip, the 2D markers and the 3D DOM badge overlay. Escape emits `null`. No `aria-pressed` toggles and no `role="toolbar"` for loop nodes.
- **3D specifics.** A canvas pick emits `nodeSelect`. A raycast hover emits `nodePreview`. An `effect` on `selectedId` drives the camera and has no other side effect, so a duplicate emit is harmless.
- **The car view switch.** One `car-view-switch` component, the name decided once. It `implements LoopView`, passes all five members through to whichever car view is shown (and to the WebGL fallback `<car-view>`), and owns only the 2D/3D mode, kept in `localStorage` with try/catch. Use `segmentedClasses` with `aria-pressed`, as both 3D branches already do.
- **Page wiring.** The page binds the store once per view: strip, switch, banner `nodeSelect`, and detail `[nodeId]="selection.activeId()"`.
- **Tests.** A shared helper, `expectLoopViewContract(fixtureFactory)`, runs the same assertions on every view: aria-selected follows `selectedId`, one tab stop, the emits, Escape.

### 2. State colours: theme tokens replace `--sd-color`

No new CSS file and no new custom property. Every state colour is an existing `theme.css` token, and `@theme static` emits all tokens on `:root`.

```ts
// shutdown-loop.display.ts
export type StateToken = '--color-success' | '--color-danger' | '--color-fg-dim' | '--color-fg-muted';
export interface StateDisplay {
  label: string; short: string; icon: string;
  text: string; marker: { measured: string; unmeasured: string }; connector: string; stroke: string;  // Tailwind (2D)
  token: StateToken;            // raw colour for canvas/WebGL: closed success, suspect danger, downstream fg-dim, no-data fg-muted
  dash: string | null;          // the non-colour cue, mandatory in every view (3D: LineDashedMaterial / hollow badge)
  emphasis: 'strong' | 'normal' | 'muted';   // line weight: the suspect is drawn thick (replaces car-view's `width` and gltf's EMPHASIS)
}
/** Resolved colours for three.js; jsdom returns '' so callers pass `fallback` (tests inject colours instead). */
export function readStateColours(el: Element = document.documentElement): Record<NodeState, string>;
```

- `cssClass`, `shutdown-states.css`, the probe elements, `FALLBACK_STATE_COLOURS` and `DEFAULT_SCENE_COLORS.states` all go. Any jsdom fallback copies the `theme.css` values exactly (`#4ade80`, `#fb923c`, `#8a8a8a`, `#a3a3a3`), in one place.
- A display spec asserts each StateDisplay's class lists use its own `token`, for example `marker.measured` contains `bg-success` when `token === '--color-success'`, so 2D and 3D can't drift.
- **Reserved colours.**
  - `--color-danger` means "the cause" on this page, so the 3D HV highlight moves to another token (for example `--color-warn` or `--color-secondary-border`).
  - `--color-fault` stays reserved for the banner's LOOP OPEN fill.
  - `--color-accent` (NER red) is never a state colour.
- The 3D component's CSS is rewritten as utilities on these tokens (`border-success`, `text-danger`), with no `styleUrls`.

### 3. Loop-node data (`shutdown-loop.model.ts`)

- **Model fields.** `LoopNode` gains `short` (replacing SHORT_LABEL). 3D positions stay in `shutdown-loop.positions-3d.ts`, keyed by `LoopNode.id`, with a spec that every id has a position. The 2D `car: {x, y}` stays on `LoopNode`.
- **Naming.** "Loop node" goes into the CONTEXT.md glossary. Component and copy names follow it now; type renames come as one commit after all four branches merge.

### 4. Status semantics the UI relies on (agreed with the logic branch)

- **`computeLoopStatus` and `resolveLoopStatus` stay the logic branch's.** The UI only reads `LoopStatus`/`NodeStatus` and never calls `STALE_AFTER_MS`, `isLive` or the board-last-seen logic.
- **`NodeStatus` gains `staleAfterMs?: number`** (the reading's current timeout, from `staleAfterMs(reading)`). Then:
  - explainNode says "No reading for 12 s (expected every ~1 s)" and names the topic, not the board;
  - `boardFreshness` becomes "a board is fresh if any of its readings is live", which matches the logic branch's `boardLive`, or it is dropped in favour of per-topic ages in the detail panel;
  - the banner's silent text lists loop nodes, not "for over 60 s".
- **`LoopStatus.source`** is shown in `loop-meta`. When it is `'server'`, explainNode explains from the states and says scylla decided.
- **`silentBoards`** is documented as "boards with at least one loop node in no-data", and the banner wording follows that definition.
