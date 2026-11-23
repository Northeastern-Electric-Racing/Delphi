# Judge, round 1: `throwaway-shutdown-ui` + the shared contract for all four shutdown branches

Inputs: `ui-correctness.md`, `ui-live.md`, `ui-spec.md`, and the integration and merge sections of `logic-spec.md`, `proc-spec.md` and `gltf-spec.md`. Code: `worktrees/argos/throwaway-shutdown-ui` at bf6f70ae (read only, diffed against `origin/shutdown-loop-page`) and the three sibling worktrees. Context: ADR 0007, `docs/CONTEXT.md` (Conventions and Flagged ambiguities), `theme.css`, and `@angular/aria` 22.2.3 (installed, already used by `ui/select`).

Paths are relative to `angular-client/src/pages/shutdown-page/` unless they say otherwise.

## Verdict

**Round 2 required.** The Tailwind restyle is close to the conventions: lint, Prettier and 108 specs are clean, and there are no palette, `dark:` or `::ng-deep` violations. The single store with the page-owned detail panel is the right architecture. Four things block it:

1. **It breaks every sibling at compile time.** It deletes `cssClass` and `--sd-color` and leaves no replacement that three.js can read.
2. **The view contract exists only as a comment.** Neither 3D branch follows it.
3. **There are three verified interaction bugs.** Hover freezes the panel against the keyboard. The strip's auto-scroll moves a different node under the pointer. On phones, car markers overlap, so a tap selects the wrong loop node.
4. **The page's main job is weakened.** The strip is below the fold, the culprit is the smallest text, and with live data the page jumps and chatters.

### Spot checks (scratch copies only, in `scratchpad/judge-ui/`)

- **Aria Listbox: the reviewers' proposed `selectionMode="follow"` does not fit.** I ran a probe spec, `judge-ui/angular-client/src/judge/aria-probe.spec.ts`, against the installed 22.2.3:
  - With `value=[]`, the first render emits `valueChange(['a'])`. It selects the first option without any user action. Wired to the store, this would pin GLVMS on page load in both views, and the detail panel would stop showing the break.
  - Every click emits `[]` and then `[id]`, a transient `select(null)`. In 3D that would fly the camera to the break and back.
  - After the first interaction, the tab stop no longer follows a selection made in another view. Re-syncing it with the public `gotoIndex` moves DOM focus, so it steals focus.
- **`selectionMode="explicit"` fits.** I probed it with `judge-ui/angular-client/src/judge/aria-explicit.spec.ts`:
  - The first render emits nothing, and the first option is the tab stop.
  - A click emits once (`['b']`), and a second click on it clears it (`[]`).
  - Arrows move `Option.active()` and do not select.
  - Enter toggles.
  - Escape is not handled, so we add it.
  - `Option.active()` is `true` on the first option even before focus, so any bridge from it must check that focus is inside the listbox.
- **Confirmed by reading the code:**
  - `activeId = previewed ?? selected`, and keydown never clears the preview (store:23, both views).
  - `scrollTargetId` includes `highlightId`, so it scrolls on every preview (strip ts:72-83).
  - The connector and segment after the break node take `suspect` (display.ts:54, car-view.ts:80-92).
  - `downstream-open` is labelled "Open — upstream".
  - `silentText` hard-codes `STALE_AFTER_MS`.
  - `boardFreshness` marks a board stale when it has never published.
  - The latch coordinates are 58.7/61.6/64.4/67.2 % apart, about 10 px at 390 px for 20 px markers.
- **Merged ui + logic tree:** the ui-spec reviewer type-checked it clean, with 138 tests passing. I checked the logic branch's `NodeStatus`. It has no `staleAfterMs`, so the UI has no per-reading timeout to show today.

## MUST FIX (in this order)

### M1 · Land the shared contract as the first commit, and push it at once (blocker for all siblings)

- **Finding:** ui-spec blocker and majors 1, 4 and 7. proc-spec and gltf-spec blockers. 3D colour drift: suspect is `#ff4d4d` in 3D but `danger` in 2D, and 3D HV uses `--color-danger`.
- **Decision:** implement **SHARED CONTRACT §1–§5** below exactly. Commit it before any other round-2 work and push, so the 3D branches can merge it early.
- **Acceptance:**
  - `StateDisplay` has `token`, `dash` and `emphasis`.
  - `readStateColours()` exists, and so does `shutdown-loop.theme.ts`.
  - `loop-view.ts` exports `LoopView`, and `LoopStripComponent` and `CarViewComponent` both `implements LoopView`.
  - `node-detail` is renamed `loop-node-detail` / `LoopNodeDetailComponent`.
  - `NodeStatus.staleAfterMs` exists (§4).
  - A display spec asserts that every state's class lists use its token: `bg-<name>`, `border-<name>` and `stroke-<name>`, where `<name>` is the token without `--color-`.
  - A spec asserts that every `SHUTDOWN_LOOP` id has a `SHORT_LABEL` entry.
  - The glossary entry is added (§5).
- **Files:**
  - `shutdown-loop.display.ts` and its spec
  - new `shutdown-loop.theme.ts` and its spec
  - new `loop-view/loop-view.ts`
  - `shutdown-selection.store.ts` and its spec
  - `components/node-detail/*` moved to `components/loop-node-detail/*`
  - `shutdown-page.component.*`
  - the workspace root's `/home/user/Delphi/docs/CONTEXT.md`, not inside the worktree

### M2 · Merge `origin/throwaway-shutdown-logic-scylla`, then show per-reading staleness and `source` correctly

- **Finding:** ui-spec majors 5 and 6, logic I1, I2 and I4, correctness minor (silent text), live minor (silent text).
- **Decision:** merge first; it is textually clean. Then:
  - Drop every UI use of `STALE_AFTER_MS`.
  - Drive the copy from `NodeStatus` (`state`, `ageMs`, `staleAfterMs`) and `LoopStatus.source`, as set out in §4.
- **Acceptance:**
  - `grep STALE_AFTER_MS components shutdown-loop.display.ts` finds nothing.
  - The banner names loop nodes, not durations. It says "since the page opened" when `ageMs` is undefined, and never "for over 60 s".
  - A board chip is stale only when all of that board's measured loop nodes are `no-data`. When some are, it shows "· N stale".
  - explainNode for a measured `no-data` loop node says "No new reading for 12 s (it goes stale after 3 s without one)" and never "No message from the VCU".
  - `loop-meta` shows a source chip: "Status: scylla" or "Status: this client".
  - When `source === 'server'` and the local value contradicts the state, explainNode does not cite the value. The detail panel adds the note "Decided by scylla-server, which sees every message; this client's latest reading is 0 (open)."
  - The mock panel says "stale a few seconds after publishing stops".
  - Specs cover each case. `loop-banner.component.spec.ts:113`, which locks in the 60 s text, is rewritten.
- **Files:** `loop-banner.*`, `loop-meta.*`, `shutdown-loop.display.ts` (`explainNode`, `boardFreshness`), `loop-node-detail.*`, `mock-panel.component.html`.

### M3 · Selection and keyboard model: Aria Listbox in explicit mode, with one shared bridge

- **Finding:** ui-spec major 2 (hand-rolled duplicate roving), correctness major 2 (hover beats keyboard; the panel freezes), live minor (focus pins the selection; there is no way back to the break), ui-spec minors (no way for a pointer to clear; the tab stop after Escape; `aria-orientation`; the double emit).
- **Decision:**
  - The strip and the 2D car each become `ngListbox selectionMode="explicit" orientation="horizontal" [wrap]="false"`, with `ngOption [value]="id" [label]="SHORT_LABEL[id]"`.
  - One directive, `loop-view/loop-node-listbox.directive.ts`, does the bridging (contract §3):
    - `valueChange` emits `nodeSelect`.
    - While focus is inside, the active option emits `nodePreview`. Focus leaving emits `nodePreview(null)`.
    - Escape emits `nodeSelect(null)`.
  - `store.select()` clears the preview.
  - Remove the `(focus)` emits, `rovingIndex`, both `onKeydown` methods and their duplicated tests.
  - The detail panel gets a "Show the break" `uiIconButton` while something is pinned. It calls `select(null)`.
- **Acceptance (page-level specs):**
  - Load the page: nothing is selected, and the detail shows the break.
  - Tab into the strip and out again: still nothing is selected.
  - mouseenter TSMS, focus EM interlock, then ArrowRight: the detail title follows focus.
  - Click a selected loop node, or press Escape: the pin clears and the detail shows the break.
  - Each click causes exactly one `select` call.
  - `rovingIndex` and `onKeydown` no longer appear in `components/`.
- **Files:** `loop-view/loop-node-listbox.directive.ts` and its spec, `loop-strip.*`, `car-view.*`, `shutdown-selection.store.*`, `loop-node-detail.*`.

### M4 · The strip scrolls only when something outside the strip changes

- **Finding:** correctness major 3, plus the live minor on scrolling back.
- **Decision:**
  - Delete the preview path from `scrollTargetId`.
  - Scroll when `selectedId` changes, unless the pointer is over the scroller.
  - Scroll when the first loop node of the stretch changes, unless the user scrolled or pressed a pointer on the scroller in the last 5 s.
  - Keyboard navigation already scrolls natively, because focus moves.
- **Acceptance:**
  - Specs with a stubbed scroller: hovering a half-visible item leaves `scrollLeft` as it was, and leaving the pointer does not reset it.
  - A banner chip click scrolls to that loop node.
  - A stretch change within 5 s of a user scroll does not scroll.
- **Files:** `loop-strip.component.ts` and its spec.

### M5 · Car markers: overview only on phones, badges with leader lines from `sm` up

- **Finding:** correctness major 1, ui-spec major 3, live major (phone blobs, WCAG 2.5.8), ui-spec minor (ping forever), live nits (cog rings, ping).
- **Decision:**
  - The page passes `[interactive]="carInteractive()"`, a `BreakpointObserver` signal from `@angular/cdk/layout` that is true at the `sm` breakpoint and up.
  - **Below `sm`:** no listbox, no tab stops and `pointer-events-none`. The car is `role="img"` with `aria-label` set to `loopSummary(status)`. The highlighted loop node, or else the break, is a `size-6` disc with its glyph. Every other loop node is a `size-2.5` dot, and suspects get an extra ring. The strip is the control.
  - **From `sm` up:**
    - Every loop node has a small non-interactive anchor dot at `node.car` and a `size-7` interactive badge.
    - Badge positions come from `CAR_BADGE_2D` in `components/car-view/car-view.layout.ts`, joined to the anchor by an SVG leader line. Clustered loop nodes (the latches, the side BRBs, GLVMS/TSMS, the sense row with the AIRs) fan out. Loop nodes that are not clustered keep their badge on the anchor.
    - Badges have no `hover:scale-125`. Highlighting is a ring.
    - The glyph shows at every interactive size.
    - Dashed rings use `border-2`.
  - The ping span gets `pointer-events-none` and runs 3 iterations, re-keyed when the break id changes.
- **Acceptance:**
  - A spec asserts that every `SHUTDOWN_LOOP` id has a badge.
  - A spec asserts that every pair of badge centres is at least 28 px apart in a 600 × 321 px drawing.
  - At 390 px the car has no `role="option"`.
  - A Playwright tap on each badge centre at 640, 1024 and 1280 px selects that loop node (re-run `r1-ui-correctness/s4.js`).
- **Files:** `car-view.*`, new `car-view.layout.ts` and its spec, `shutdown-page.component.*`.

### M6 · Above the fold and culprit prominence

- **Finding:** live majors (the strip is below the fold; the culprit is the smallest text), live minor (the strip doesn't fit at 1280), the minor in ui-spec and live (no h1), live minor (chips don't separate measured from unmeasured), correctness nit (chips out of loop order).
- **Decision:**
  - **Layout.** Order is banner, strip (full width), then car beside the detail panel at `lg`. On phones: banner, strip, detail, car.
  - **Title.** The title is an `<h1>` using `typographyClass('x-large-title', 'm-0 max-md:text-title')`. It stays the app-standard size.
  - **Single suspect.** The culprit goes into the verdict line at the verdict's size: "LOOP OPEN · TSMS".
  - **Several suspects.** One chip list from `status.nodes` in loop order, `text-lg min-h-10`:
    - the measured break is a solid chip, "BMS latch · reads 0";
    - unmeasured suspects are hollow chips, "· no sensor";
    - no-data loop nodes are dashed chips, "· no data".
  - **Strip items at `lg`.** `flex-1 min-w-14` on a `w-full` list, so all 19 fit from 1100 px up.
- **Acceptance:**
  - At 1280×720 and 1440×900, with a warning row showing, the strip's bottom edge is inside the viewport without scrolling.
  - At 1280 the strip has no horizontal scroll.
  - axe `page-has-heading-one` passes on /shutdown.
  - Specs check the chip order and the measured/unmeasured classes.
- **Files:** `shutdown-page.component.html`, `loop-banner.*`, `loop-strip.component.html`.

### M7 · The live region announces verdict changes, debounced

- **Finding:** live major (45 announcements in 20 s), correctness nit (the `firstChild` test proves nothing).
- **Decision:**
  - The live text is `loopSummary(status)`: the verdict plus the break loop node only. No mismatch, and no stretch list.
  - It changes only after that text has held for 2 s, and at most once every 5 s (the trailing value wins).
  - The visible banner stays live and undebounced.
- **Acceptance:**
  - Fake-timer specs: flapping every 300 ms for 10 s gives at most 2 announcements.
  - A stable change is announced after 2 s.
  - The specs assert on `textContent`.
- **Files:** `loop-banner.*`, `shutdown-loop.display.ts` (`loopSummary`).

### M8 · No layout shift from the warning row

- **Finding:** live major (CLS 0.29).
- **Decision:**
  - The warning slot always renders, with `min-h-10`.
  - When it is empty, it shows a quiet `text-fg-muted` line: "No sensor warnings".
  - Mismatch and silent sit side by side (`flex-wrap`) in that one slot.
  - No hold timers.
- **Acceptance:** the banner host's height is identical with and without a single warning (spec on the rendered structure). Re-run `s3.js`: CLS under 0.1 at 1440.
- **Files:** `loop-banner.component.html`.

### M9 · Diagnosis wording and wiring that match the logic

- **Finding:**
  - correctness minor: the connector after the break is drawn as the cause;
  - correctness minor: every suspect is "Open — cause";
  - live minor: downstream is labelled "Upstream";
  - correctness nit: "which have no reading of their own" for no-data loop nodes.
- **Decision (all in `shutdown-loop.display.ts`, shared by 2D and 3D):**
  - **`segmentState(nodes, i)`:** the wire after the break loop node (the last suspect) is `downstream-open`.
  - **`stateLabel(s, loop)` / `shortStateLabel(s, loop)`:**
    - single culprit: "Open — cause" / "Cause";
    - other stretch members: "Open — possible cause" / "Suspect";
    - `downstream-open`: "Open — after the break" / "Downstream".
  - `nodeAriaLabel(s, loop)` uses them.
  - explainNode says "no live reading" for no-data loop nodes in the stretch.
- **Acceptance:** display specs for each label. The strip connector and car segment after the break carry `data-state="downstream-open"`.
- **Files:** `shutdown-loop.display.ts` and its spec, `loop-strip.*`, `car-view.*`, `loop-node-detail.*`.

### M10 · Colour-blind safety

- **Finding:** live major (closed and cause are identical under deuteranopia and protanopia), ui-spec minor (no glyph on phones).
- **Decision:** every state differs by shape as well as colour:
  - a glyph on every interactive marker (M5);
  - wire `emphasis`:
    - `strong` (the cause) is a 5 px `danger` core over a 9 px `stroke-page` casing;
    - `normal` (closed) is a solid 3 px line;
    - `muted` (downstream and no-data) is 2 px with its `dash`;
  - the frame image is `grayscale opacity-30`, so the drawing never shares a hue with a state.
- **Acceptance:**
  - A display spec asserts that `(icon, dash, emphasis)` is distinct for each state.
  - Re-run the deuteranopia and protanopia screenshots: closed and cause wires can be told apart.
- **Files:** `shutdown-loop.display.ts`, `car-view.*`.

### M11 · The callout never scrolls the page

- **Finding:** correctness minor (overflow at 375 px), live minor (the callout covers its neighbours).
- **Decision:**
  - The callout shows only for the highlighted loop node, not by default; the banner and detail already name the break.
  - It chooses start, centre or end from the remaining space.
  - It may wrap (`max-w-64 whitespace-normal`).
  - The car section gets `overflow-hidden`.
- **Acceptance:** at 375 and 640 px, selecting each loop node keeps `document.scrollingElement.scrollWidth === clientWidth`.
- **Files:** `car-view.*`, `shutdown-page.component.html`.

### M12 · Tests that prove the contract

- **Finding:** ui-spec minors (vacuous bracket test; no car Enter/Space/Escape tests; no banner chip end-to-end test), correctness nit.
- **Decision:**
  - Add `loop-view/loop-view.contract.ts` exporting `expectLoopViewContract(create: () => ComponentFixture<LoopView>)`. Run it from the strip and car-view specs; the 3D specs will run it later.
  - The bracket test asserts "Broke the loop" and "Suspect stretch".
  - A page spec checks that a banner chip click reaches the strip, the car and the detail.
- **Acceptance:** the helper covers:
  - `aria-selected` follows `selectedId`;
  - one tab stop;
  - click toggles;
  - Escape emits `null`;
  - hover preview and leave;
  - no emit on load.
- **Files:** `loop-view/loop-view.contract.ts`, the strip, car and page specs.

## SHOULD FIX

- **S1 · Intermittent chip** (the live "no hysteresis" major, kept partly). A page-local computed keeps a 10 s ring of break-node changes. With 3 or more changes it shows a warn chip in the M8 slot: "Intermittent: break moved 7× in 10 s between BMS latch, IMD latch, BSPD latch". Live-only and in memory.
- **S2 · Card look.** One `panelClass` recipe (page-local, documented), or the app's `cardClass()` look (`bg-panel`) with an icon and title per card ("On the car", "Loop order", "Details"), to match eFuses and Charging. Pick `cardClass` unless it fights the strip's brackets.
- **S3 · Detail panel empty state** (closed or unknown loop): a compact legend (states, measured vs no sensor, wire patterns) and `lg:self-start`.
- **S4 · Mismatch presentation:**
  - a warn ring and a `<ui-icon name="priority_high">` badge in place of the literal "!";
  - the short label "Reads 1";
  - the name "HVD: reads closed after the break — sensor mismatch".
- **S5 · Header chips:**
  - `min-w-[7ch] tabular-nums` on the age;
  - "<1 s ago" in place of "just now";
  - TS "—" made `aria-hidden`, with sr-only "unknown".
- **S6 · Strip heading:**
  - the hint moves to a `<p id>` referenced by `aria-describedby`, and is hidden below `md`;
  - the verdict becomes an `h2`;
  - "arrow keys move along the loop".
- **S7 · Strip column heights:**
  - a fixed label height (`h-8 line-clamp-2`);
  - use `PLACEHOLDER_TAG` in place of the literal "placeholder".
- **S8 · Nits:**
  - comment what each magic pixel value is derived from;
  - `aspect-1000/535`;
  - `typographyClass('header', 'm-0')` for the h2s.
- **S9 · Mock panel:**
  - add a TS ON/OFF toggle;
  - once the logic branch exposes a way to force local status (logic I3), the panel turns it on while publishing. That hook is the logic branch's to add; the UI only calls it.

## REJECTED

| Proposal | Reason |
|---|---|
| Aria Listbox `selectionMode="follow"`, with selection following focus (ui-spec) | Verified: it auto-selects the first option on load, emits `[]` then `[id]` on every click, and its tab stop doesn't follow a selection made in another view. Explicit mode plus the preview bridge (M3) gives the same arrow-key reading without those bugs. |
| A 2 s hold and hysteresis on displayed states (live major) | Hiding state changes on a live safety page misleads, and the drawn state would lag the real one. The churn is the sim's random bits, which logic's churn reduction and scylla's B1 debounce address. Debouncing only the live region (M7) and showing an intermittent chip (S1) keep the truth visible. |
| Holding a mismatch warning for 3 s or more | It would show a warning that has already cleared. The reserved slot (M8) removes the layout shift without it. |
| Moving `short` onto `LoopNode` (ui-spec) | scylla's parity test parses `SHUTDOWN_LOOP` with regexes (logic I5). Per-view data stays in id-keyed tables (`SHORT_LABEL`, `CAR_BADGE_2D`, `NODE_POSITIONS_3D`) with completeness specs. |
| Renaming the outputs to `loopNodeSelect`/`loopNodePreview` now | The churn would land on four branches. Inside `LoopView`, "node" is scoped by the interface, and its doc says "node = loop node". User-facing copy, component names and the glossary say "loop node" now. The types (`NodeStatus` and the rest) are renamed in one commit after the merges. |
| Scaling markers in `cqw`/% (correctness) | Between `sm` and `lg` they would drop below the 24 px minimum, and the spacing exception doesn't apply to overlapping targets. Badges with leader lines (M5) fix it. |
| Horizontal scrolling for the car on phones (live) | A second horizontal scroller next to the strip. The overview mode is simpler, and the strip is the control. |
| Shrinking the page title to `text-title` | Every page uses the same title size. The culprit moves into the verdict line instead (M6). |
| The break loop node as the default tab stop (correctness nit) | Aria makes the selected option, else the first, the tab stop. Starting at the loop start is natural, and the banner chips and bracket lead to the break. |
| WebP/`srcset` for the car frame | It is a base PR asset and out of scope. File it as an idea if wanted. |
| The nav bar's NG0100 console errors | They come from other components and appear on every page. |
| "Position: from the model/table" in the detail panel (gltf) | It is a 3D dev detail. Show it in a dev-mode `title` on the 3D badge, not as a field in the shared detail panel. |

## SHARED CONTRACT (binding on ui, logic, 3d-procedural and 3d-gltf)

### §1 State colours: theme tokens, plus a helper three.js can read

There is no new CSS file and no new custom property. `shutdown-states.css`, `cssClass` and `--sd-color` are gone for good, along with every probe element, `resolveStateColours`, `FALLBACK_STATE_COLOURS` and `DEFAULT_SCENE_COLORS.states`.

**`shutdown-loop.theme.ts` (new):**

```ts
export type ThemeColourToken = `--color-${string}`;
/** Reads a custom property; a test injects a fake. */
export type CssVarReader = (token: ThemeColourToken) => string;
export const cssVarReader =
  (root: Element): CssVarReader =>
  (token) => getComputedStyle(root).getPropertyValue(token).trim();
/** Used only if a token resolves empty (jsdom, a missing token); warns once. The one hex value in shutdown code. */
export const MISSING_THEME_COLOUR = '#808080';
export function readThemeColour(token: ThemeColourToken, read: CssVarReader): string;
```

**`shutdown-loop.display.ts`:**

```ts
export type WireEmphasis = 'strong' | 'normal' | 'muted';
export interface StateDisplay {
  label: string; short: string; icon: string;          // defaults; stateLabel()/shortStateLabel() refine suspect
  text: string;
  marker: { measured: string; unmeasured: string };    // Tailwind, also used by 3D HTML badges
  connector: string; stroke: string;                   // Tailwind (2D)
  token: ThemeColourToken;   // closed '--color-success', suspect '--color-danger',
                             // downstream-open '--color-fg-dim', no-data '--color-fg-muted'
  dash: string | null;       // SVG dasharray; 3D maps to LineDashedMaterial / dashPieces
  emphasis: WireEmphasis;    // suspect strong, closed normal, downstream/no-data muted (2D width, 3D tube radius)
}
export function readStateColours(read: CssVarReader): Record<NodeState, string>;
export function segmentState(nodes: readonly NodeStatus[], i: number): NodeState; // wire i -> i+1 (M9)
export function stateLabel(s: NodeStatus, loop: LoopStatus): string;
export function shortStateLabel(s: NodeStatus, loop: LoopStatus): string;
export function nodeAriaLabel(s: NodeStatus, loop: LoopStatus): string;
export function loopSummary(loop: LoopStatus): string;   // "LOOP OPEN — cause: TSMS"; banner live region + 3D/2D role="img" label
export const SHORT_LABEL: Readonly<Record<string, string>>;  // + completeness spec
export { PLACEHOLDER_TAG, formatAge, formatValue, explainNode, nodeNotes, breakNode };
```

**Reserved colours on this page:**

| Token | Meaning |
|---|---|
| `--color-danger` | The cause, and nothing else. 3D HV parts move to `--color-secondary-border`. |
| `--color-fault` | The banner's LOOP OPEN fill only. |
| `--color-warn` | TS ON and the mismatch/intermittent warnings. |
| `--color-fg` | The selected ring, in 2D and 3D. |
| `--color-focus` | The focus ring. |
| `--color-accent` (NER red) | Never a state colour. |

3D frame and surface colours come from neutral tokens through `readThemeColour` (`--color-surface-3`, `--color-border-strong`, `--color-page`).

### §2 Selection store (`shutdown-selection.store.ts`, page-provided)

```ts
@Injectable() export class ShutdownSelectionStore {
  readonly selectedId: Signal<string | null>;   // pinned loop node
  readonly previewId: Signal<string | null>;    // pointed at, or keyboard-active, anywhere on the page
  readonly activeId: Signal<string | null>;     // previewId ?? selectedId: highlight + loop-node-detail
  select(id: string | null): void;              // sets the pin AND clears previewId; idempotent
  preview(id: string | null): void;
}
// rovingIndex is deleted.
```

### §3 `LoopView`: every view of the loop implements it (`loop-view/loop-view.ts`)

"Node" in these member names means **loop node**.

```ts
import { InputSignal, OutputEmitterRef } from '@angular/core';
import { NodeStatus } from '../shutdown-loop.utils';

export interface LoopView {
  readonly nodes: InputSignal<NodeStatus[]>;            // LoopStatus.nodes, loop order
  readonly selectedId: InputSignal<string | null>;
  readonly previewId: InputSignal<string | null>;
  readonly nodeSelect: OutputEmitterRef<string | null>;  // the toggled pin: id, or null to clear
  readonly nodePreview: OutputEmitterRef<string | null>; // hover / keyboard-active id; null on leave
}
/** Car views only (2D and 3D). False below `sm`: an overview, not a control. */
export interface CarLoopView extends LoopView {
  readonly interactive: InputSignal<boolean>;
}
```

**Rules:**

1. **A view never owns selection.** There is no `selectedId = signal()` in any view, and the view highlights `previewId() ?? selectedId()`.
2. **Click, tap, Enter or Space on a loop node toggles the pin:** `nodeSelect.emit(id === selectedId() ? null : id)`. Escape emits `null`. Hover emits `nodePreview(id)`, and leaving emits `nodePreview(null)`. Focus alone never selects.
3. **Keyboard.** The strip and the 2D car (when `interactive`) are `ngListbox selectionMode="explicit" orientation="horizontal" [wrap]="false"` plus `loopNodeListbox` (`loop-view/loop-node-listbox.directive.ts`). The directive handles three things:
   - `valueChange` to `nodeSelect`;
   - the active option to `nodePreview` while focus is inside, and `null` when focus leaves (on pointer leave it re-emits the active id if focus is still inside);
   - Escape to `nodeSelect(null)`.

   Options are `ngOption [value]=id [label]=SHORT_LABEL[id]`. Loop nodes never get `aria-pressed` toggles or `role="toolbar"`.
4. **3D views.**
   - Keyboard and assistive-tech access to loop nodes goes through the strip. The canvas wrapper is `role="img"` with `[attr.aria-label]="loopSummary(...)"`.
   - HTML badges, if any, are `aria-hidden` labels that take pointer clicks, with no tab stops.
   - A canvas pick toggles (rule 2), and a raycast or screen-space hover previews.
   - The camera reacts to `selectedId` in an `effect` with no other side effect.
   - When `interactive` is false: no picking, and only the active loop node's badge shows.
5. **One detail panel.** `loop-node-detail` (`LoopNodeDetailComponent`, `[status]`, `[nodeId]="selection.activeId()"`) is the only one. 3D views delete their in-view panels, `nodeInfo`, `nodeDetail` and procedural's 19-button loop-node toolbar. 3D camera and material controls (view presets, CAD/Theme/Ghost) stay inside the 3D view, built with `segmentedClasses` and `aria-pressed`.
6. **Switching between 2D and 3D.**
   - There is no forwarding wrapper.
   - The 3D branches add a `car-view-mode` component (`components/car-view-mode/`, `mode = model<'2d' | '3d'>()`, storage key `argos.shutdown.carView` with try/catch) in the car section header slot.
   - The page renders `@if (carMode() === '3d') { <car-view-3d …same five bindings… [interactive] (unavailable)="carMode.set('2d')" /> } @else { <car-view …/> }`.
   - The default mode is the 3D judges' call.
7. **Page wiring.** The page binds the store exactly once per view: the strip, the car view, the banner chips (`nodeSelect`) and the detail.
8. **Tests.** Every `LoopView` spec calls `expectLoopViewContract` from `loop-view/loop-view.contract.ts` (M12).

### §4 Status semantics the UI consumes (logic owns the computation)

- **`NodeStatus` gains** `/** How long this reading stays live without a new message: staleAfterMs(reading). Set only for measured loop nodes with a reading. */ staleAfterMs?: number;`. The UI branch adds this in `shutdown-loop.utils.ts`, in the interface and as one line in `computeLoopStatus`'s `base` object (`staleAfterMs: reading ? staleAfterMs(reading) : undefined,`). `resolveLoopStatus` keeps it through its spread. Logic's round-2 implementer must keep the field if they restructure `computeLoopStatus`.
- **The UI never** imports `STALE_AFTER_MS`, `isLive` or `staleAfterMs()`, and never calls `computeLoopStatus`/`resolveLoopStatus`. It reads `LoopStatus` and `NodeStatus` only. "Stale" means `state === 'no-data' && node.topic` (logic decides).
- **Board freshness.**
  - `boardFreshness(nodes)` returns `{ board, ageMs?, staleCount, stale }`. `stale` is true when every measured loop node of the board is `no-data`.
  - `silentBoards` (logic: boards with at least one loop node in `no-data`) drives only the UNKNOWN title.
  - The banner's silent warning lists the `no-data` loop nodes by name.
- **`LoopStatus.source`.** Treat `undefined` as `'local'`.
  - `loop-meta` shows it.
  - When it is `'server'`, explainNode reasons from the states and cites a value only when that value agrees with the state.
  - `loop-node-detail` adds the scylla note when they disagree.
  - This is the single place where the server-state/local-value question (logic I4) is decided. 3D views show no values of their own.

### §5 Terminology

- Add to the workspace glossary, `/home/user/Delphi/docs/CONTEXT.md`: "**Loop node** — one element of the shutdown loop (`LoopNode` in the angular-client, `shutdown_loop` in scylla-server), in series order from the GLV master switch to the AIR coils; not a CAN node." Also add "loop node" to the Node entry under Flagged ambiguities.
- Copy uses "loop node": "Loop node details", "Selected loop node", "Select a loop node in the loop or on the car…".
- Component names: `loop-node-detail`, `loop-node-listbox`.
- Type renames (`NodeStatus` to `LoopNodeStatus`, and the others) wait for one mechanical commit after all four branches have merged.

## ROUND-2 SEQUENCING

1. **`throwaway-shutdown-ui` goes first.**
   - **Merge logic first: yes.** Run `git -C worktrees/argos/throwaway-shutdown-ui merge origin/throwaway-shutdown-logic-scylla`. It is textually clean and its 138 tests pass.
   - **Commit A, the contract:** M1 (§1–§5, including `staleAfterMs`), with the existing views converted just enough to compile against it. Run lint, tests and Prettier, then **push at once** and tell the orchestrator.
   - **Then M2–M12, then the SHOULDs.**
   - **At the end,** if logic's round 2 has pushed, merge `origin/throwaway-shutdown-logic-scylla` again, re-run the shutdown specs, and push.
2. **`throwaway-shutdown-logic-scylla`** runs in parallel with no dependency on the UI. It must:
   - keep `NodeStatus` and `LoopStatus.source` as in §4, keeping `staleAfterMs` if it touches `computeLoopStatus`;
   - expose a way to force local status while the mock publishes (logic I3), for example `ShutdownLoopService.preferServer: WritableSignal<boolean>`, which the UI's mock panel will call;
   - not edit `shutdown-loop.display.ts` or any component.
3. **`throwaway-shutdown-3d-procedural` and `throwaway-shutdown-3d-gltf`** start once UI commit A is pushed. Each implementer:
   - **Merges:** `git merge origin/throwaway-shutdown-ui`. On `shutdown-page.component.{html,ts}` conflicts, take the UI version, then add `car-view-mode` in the car section header and the `@if` from §3 rule 6.
   - **Colours:**
     - delete `../../shutdown-states.css` from `styleUrls`, and delete the probes, `resolveStateColours`/probe reads, `FALLBACK_STATE_COLOURS`/`DEFAULT_SCENE_COLORS.states` and every `cssClass` use;
     - read colours with `readStateColours(cssVarReader(inject(DOCUMENT).documentElement))` and `readThemeColour` for scene neutrals;
     - move HV to `--color-secondary-border`;
     - map `dash` and `emphasis` to tubes;
     - use `segmentState` for each tube.
   - **Selection:**
     - `CarView3dComponent implements CarLoopView`;
     - delete the local `selectedId` signal;
     - picking toggles per rule 2, and hover previews;
     - highlight `previewId ?? selectedId`;
     - the camera `effect` reacts to `selectedId`.
   - **Panels:** delete the in-view detail panel, `nodeInfo`/`nodeDetail`, and procedural's loop-node toolbar. Badges become `aria-hidden` and click-only. The canvas wrapper is `role="img"` labelled with `loopSummary`.
   - **The 2D fallback:** `car-view-3d` no longer nests a `<car-view>`. The page's `@else` is the fallback, entered through the `unavailable` output.
   - **Styling:** rewrite `car-view-3d.component.css` as utilities. No `styleUrls`.
   - **Tests:** add `expectLoopViewContract` to the 3D component spec, plus a spec that `readStateColours` with a fake reader reaches the scene options.
   - **Naming:** use the names `car-view-mode` and `argos.shutdown.carView` in both 3D branches, so combining them later is mechanical. The 3D judges decide the rest: the coordinate frame, the car source chain, and which branch survives.
4. **Merge order for landing:** logic, then ui (with the contract), then one combined 3D branch.
