# Round 1 — UI correctness review: `throwaway-shutdown-ui`

Reviewed `git diff origin/shutdown-loop-page...HEAD` (bf6f70ae). All 108 shutdown-page specs pass (`ng test --include='src/pages/shutdown-page/**'`), so none of the bugs below are caught by tests. Each finding was checked against the live client (http://localhost:4201/shutdown, Calypso sim) with Playwright, or by running the real `computeLoopStatus` + `explainNode` through esbuild. Scripts are in `scratchpad/r1-ui-correctness/` (s1–s11.js, entry.ts).

Counts: 0 blocker · 3 major · 4 minor · 3 nit

---

- **major** — `components/car-view/car-view.component.html:41` (the marker class `size-5 … sm:size-7`) and `car-view.component.ts:63-76`
  - **Issue:** Car markers now have a fixed CSS size (20 px, or 28 px from `sm` up). The node coordinates are only about 2.9–3.2 % of the drawing width apart: the BMS/IMD/BSPD/CAN latches, the side BRBs, and the Acc/TSIP/TS−/TS+/AIRs row. So the markers overlap at every width, and later markers in the DOM cover earlier ones. The base PR drew `r=14` circles inside a 1000-unit viewBox, which scaled with the drawing and never overlapped. On top of that, `animate-ping` scales the suspect's halo `<span>` to 2× without `pointer-events-none`, so it takes clicks meant for its neighbours.
  - **Failure:** On a 390 px phone, tapping the centre of the BMS latch marker selects **IMD latch** (the detail panel shows "5 IMD latch"). The centres of IMD→BSPD and BSPD→CAN are covered the same way. At 1280 px, while Side BRB L is a suspect, clicking the centre of Side BRB R hits BRB L's ping halo (15 of 40 samples).
  - **Fix:** Scale markers with the drawing (size in `cqw`/% of the container with a minimum, or go back to SVG circles in viewBox units), or spread the clustered coordinates. Add `pointer-events-none` to the ping span. Optionally cap the hit area at the marker pitch.
  - **Evidence:** s4.js: `bms-latch->imd-latch`, `imd-latch->bspd-latch`, `bspd-latch->can-latch` at 390 px in 35–40 of 40 samples, and `side-brb-r->side-brb-l(suspect,ping)` at 1280 px. s5.js: a touch tap on the bms-latch centre gives `selected [ 'imd-latch' ]`. Screenshot: `r1-ui-correctness/tap-390.png`.

- **major** — `shutdown-selection.store.ts:23` (`activeId = previewed ?? selected`), together with `loop-strip.component.html:24-25` and `car-view.component.html:53-54`
  - **Issue:** Preview (hover) always wins over selection, and only `mouseleave` clears it. Keyboard navigation and Escape change only `selected`. The usual mouse-then-keyboard flow is to click a node and leave the pointer resting on it, and that freezes the detail panel, the car callout and `data-highlighted` on the clicked node.
  - **Failure:** Click TSMS in the strip, then press ArrowRight twice. Focus and `aria-selected` move to EM interlock, but the detail panel still shows "12 TSMS", the callout still reads "12 · TSMS · Open — upstream", and the highlight stays on TSMS. After Escape the selection is cleared, yet the panel still shows TSMS. Sighted keyboard users see stale details until they move the mouse.
  - **Fix:** Clear the preview whenever a selection comes from the keyboard or focus (call `select()` → `previewed.set(null)`, or `preview(null)` in the views' keydown/focus handlers). Alternatively, let `activeId` prefer the most recent interaction. Add a page-level spec: mouseenter a node, then a keydown ArrowRight, then expect the detail title to follow focus.
  - **Evidence:** s9.js output: `after 2x ArrowRight (pointer still on tsms) {"focus":"em-interlock","selected":["em-interlock"],"highlighted":["tsms"],"detail":"12 TSMS",...}` and `after Escape {"selected":[],"highlighted":["tsms"],"detail":"12 TSMS"}`.

- **major** — `components/loop-strip/loop-strip.component.ts:72-83,116-125` (`scrollTargetId` = `highlightId ?? stretch start`, run by `afterRenderEffect`)
  - **Issue:** The strip auto-scrolls on every change of the *preview*, including hovers that start inside the strip itself.
    - (a) Hovering a node that is only partly visible at the edge scrolls the strip so that a different node lands under the stationary pointer. Chrome then fires `mouseenter` on that node, so the preview, the detail panel and the next click all go to the wrong node.
    - (b) Moving the pointer off any strip node resets `previewId` to null, so the strip jumps back to the suspect stretch and throws away the user's manual scroll.
  - **Failure:** (a) At 1024 px, with the strip at scrollLeft 0, pointing at the half-visible EM node (x = 981) jumps scrollLeft to 418, and the highlighted node becomes **AIRs**, which is now under the cursor. Clicking would select AIRs. (b) The user scrolls the strip to its end (scrollLeft 418), hovers a visible node, and moves away: scrollLeft goes back to 0.
  - **Fix:** Only auto-scroll for previews and selections that come from *another* view (car hover, banner chip, keyboard focus), not for hover inside the strip. For example, skip the scroll while the pointer is over the scroller, or have the effect track `selectedId` plus car-originated previews. Don't fall back to the stretch when a preview ends; scroll to the stretch only when the stretch itself changes.
  - **Evidence:** s6.js: `hover partial em-interlock at x 981` → `{"scrollLeft":418,…,"hl":"airs"}`. s7.js: `user scrolled 418` → `hovering visible node 418` → `pointer left 0`.

- **minor** — `components/loop-banner/loop-banner.component.ts:93-97` (`silentText`)
  - **Issue:** The text says "No data from BMS for over 60 s" whenever a board is in `silentBoards`. That includes a board that has never published since the page opened, a few seconds ago. The same page contradicts it: the BMS chip says "never", and `explainNode` correctly says "since the page opened". The banner spec (`warns about a silent board`) locks in the wrong wording.
  - **Failure:** Open /shutdown with the sim running (VCU publishing, BMS silent). After about 4 s the banner reads "No data from BMS for over 60 s: its readings are skipped…".
  - **Fix:** Word it from the board's last-seen time: "No data from BMS since the page opened" or "for 1 min 5 s". `boardFreshness` already has the age. Or drop the duration.
  - **Evidence:** s1.js snapshot 4 s after load: `banner: '… No data from BMS for over 60 s …'`, `meta: '… BMS never'`.

- **minor** — `components/car-view/car-view.component.ts:114` (callout alignment) and `car-view.component.html:79-89`
  - **Issue:** The callout is `whitespace-nowrap`, and it is only end-aligned when `x > 85 %`. MC HVIL (x 80.3) and EM interlock (x 73.2) have long labels whose centred callout runs past the drawing. The section does not clip, so the whole page scrolls sideways on phones, which breaks the no-horizontal-scroll rule.
  - **Failure:** At 375 px, selecting MC HVIL gives document scrollWidth 407 px (callout right edge 407 > 363). EM interlock gives 399 px. At 640 px, MC HVIL ends 10 px past its section.
  - **Fix:** Clamp the callout inside the container: measure it and shift, or choose the alignment from the label width against the remaining space. Allow wrapping (`max-w-[min(…)] whitespace-normal`) and/or clip the car section.
  - **Evidence:** s10.js: `mc-hvil: callout [172,407] … docW 407`, `em-interlock: callout [133,399] … docW 399`.

- **minor** — `shutdown-loop.display.ts:54` (the `suspect` connector) and `loop-strip.component.html:33-38`. The car view's segment colouring at `car-view.component.ts:80-92` has the same rule, inherited from the base PR.
  - **Issue:** The connector or segment *after* a node takes that node's state. The docs define it as "the loop voltage just after it". The break node F reads 0, so the wire after it is known dead and belongs downstream. It is still drawn as a solid danger "cause" line, which extends the red past the "Broke the loop" bracket into the run marked "Not the cause". This is the colour the spec's anti-goal warns against.
  - **Failure:** With a break at BMS latch, the strip connector from 4 BMS to 5 IMD and the car segment from BMS latch to IMD latch are solid orange, while IMD sits under the dashed "Not the cause" bracket. This is visible in the 390 and 1280 screenshots.
  - **Fix:** Style the connector after the break node (`breakNode`) with the `downstream-open` connector or stroke. Keep danger only for connectors *between* stretch nodes.
  - **Evidence:** `r1-ui-correctness/shot-390.png` and `shot-1280.png` (orange connector between nodes 4 and 5). Code: `connector` is `[class]="it.d.connector"` from the node's own state.

- **minor** — `shutdown-loop.display.ts:46` (`label: 'Open — cause'`), used by `nodeAriaLabel`, the car callout and the detail state line
  - **Issue:** Every suspect is labelled "Open — cause", including unmeasured nodes in a multi-node stretch, which may well be closed. The detail panel then shows "Open — cause" directly above "…so it **could** be the break", and a screen reader announces each of Side BRB R, Side BRB L and BMS latch as "Open — cause".
  - **Failure:** With a break at BMS latch, the Side BRB R aria-label is "Side BRB R: Open — cause (no sensor)", and the callout says "2 · Side BRB R · Open — cause".
  - **Fix:** Use "Possible cause" / "Suspect" for stretch members, and keep "Open — cause" only for a single culprit or for the break reading. Short labels could be "Suspect" and "Cause".
  - **Evidence:** Code path `NODE_STATE_DISPLAY.suspect.label` → `nodeAriaLabel` (display.ts) and callout `stateLabel` (car-view.ts:115). Scenario A in entry.ts gives suspects `side-brb-r,side-brb-l,imd-latch`.

- **nit** — `shutdown-loop.display.ts:190-195`
  - **Issue:** For a measured break with no-data nodes in the stretch, the explanation lumps them in with unmeasured nodes as "which have no reading of their own". BMS latch has a sensor; its reading is just not live.
  - **Failure:** "Reads 0: the first open reading. The break is here or in Side BRB R, Side BRB L or BMS latch (no data), which have no reading of their own."
  - **Fix:** Use "which have no live reading", or split the clauses for unmeasured and no-data nodes.
  - **Evidence:** entry.ts scenario A (bms-latch never arrived, imd=0), run against the real `computeLoopStatus`.

- **nit** — `loop-banner.component.ts:65-68` and `loop-banner.component.html` (two `@for` loops)
  - **Issue:** The suspects and the no-data nodes are listed as two groups instead of in loop order.
  - **Failure:** Scenario A shows "Cause is one of: Side BRB R, Side BRB L, IMD latch, BMS latch · no data", although BMS latch sits between BRB L and IMD.
  - **Fix:** Build one list from `status.nodes` filtered to the stretch, in order.
  - **Evidence:** entry.ts scenario A.

- **nit** — tests: `loop-banner.component.spec.ts:86-94`, `loop-strip.component.spec.ts` ("brackets the suspect stretch…"), and the tab stop in `loop-strip.component.ts:68-71` / `car-view.component.ts:98-101`
  - **Issue:**
    - The "only then" announcement test asserts `firstChild` identity. Angular interpolation never replaces the text node, even when the text changes, so the assertion proves nothing about re-announcement.
    - The bracket test checks `el.textContent` contains 'Cause', which the node's short label already satisfies. It never checks "Broke the loop" or "Suspect stretch".
    - Separately, the Tab stop is the *first* suspect while the detail panel and callout default to the *break* (the last suspect). So tabbing into either view moves the panel from "Where the loop broke: BMS latch" to "Side BRB R".
  - **Fix:**
    - Assert on `textContent` / a MutationObserver for the live region.
    - Assert on the bracket label text.
    - Make `breakNode` the default tab stop.
  - **Evidence:** Code reading. The tab-stop mismatch shows in the live app when tabbing into the strip with a multi-node stretch.

Checked and not a problem: OnPush with signals (status ticks every second, but `computed` equality keeps the live-region text and the scroll target stable), interval and subscription teardown (service and mock panel), `rovingIndex` bounds, touch preview stickiness (Chrome fires `mouseleave` on the next tap, s11.js), lg layout shift from the detail panel's height (its content is always shorter than the car cell). The 1150 px horizontal overflow at 768–1100 px comes from the app's top nav, not this page.
