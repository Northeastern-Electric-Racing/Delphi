# Round 2 · `throwaway-shutdown-ui` (6bde6a19) · CORRECTNESS

I reviewed only the delta from `origin/throwaway-shutdown-logic-scylla` (d01e0b9f). Paths are relative to `angular-client/src/pages/shutdown-page/`.

**Evidence sources:**
- **Specs:** all 243 shutdown specs pass in the worktree (`ng test --include='src/pages/shutdown-page/**'`). I also wrote probe specs in a scratch copy: `r2rev-ui-correctness/ac/src/pages/shutdown-page/probe/r2-probe.spec.ts`.
- **Playwright** against the live client at http://localhost:4201/shutdown. The scripts are `r2rev-ui-correctness/s*.js`.
  - "blocked" means the socket was blocked in the test browser and the dev mock panel published the data, so the data stays stable.
  - "live" means the calypso sim was flapping the data.
- **Screenshots:** `/home/user/Delphi/pictures/throwaway-shutdown-ui/review-r2/r2-correctness-*.png`.

## Round-1 MUST status

| MUST | Status | Evidence |
|---|---|---|
| M2 staleness and `source` | **PARTIAL** | **Done:** `STALE_AFTER_MS`, `isLive` and `staleAfterMs(` are gone from `components/` and display.ts. The banner names loop nodes ("No reading since the page opened from …"). The board chip shows "· N stale". The source chip shows "Status: scylla" / "Status: this client". The `serverNote` exists. The mock panel copy is right.<br>**Still wrong under `source==='server'`:** explainNode cites readings this client does not have (N8). A server no-data next to a fresh local reading gives a self-contradicting sentence and the chip "BMS 1 s ago · stale" (N9; seen live right after "Stop publishing"). |
| M3 Aria Listbox (explicit) and one bridge | **PARTIAL** | **Done:** both views use `ngListbox selectionMode="explicit"` with `loopNodeListbox`. Nothing emits on load. Tab in and out selects nothing. Escape clears the pin (live: "Where the loop broke"). Keyboard beats a resting pointer (live: hover TSMS, ArrowRight, detail shows the focused node). `store.select` clears the preview. Touch taps pin and unpin correctly at 390 and 1024 (s3-touch.js). `rovingIndex` and `onKeydown` are gone from `components/`.<br>**New bugs in the bridge:** the hover preview drops while the pointer is still inside an option (N1, major). The tab stop does not follow a pin made in the other view (N6). "Show the break" drops focus to `<body>` (N7). Leaving a car badge clears the strip's keyboard preview (N10). |
| M4 strip scrolls only for outside changes | **PARTIAL** | **Done:** the selection path is guarded by `pointerOver`. There is no scroll on hover or leave (spec, and live at 1024). The 5 s lock after wheel, pointerdown or touchstart works for the stretch path.<br>**Still wrong:** the stretch path still scrolls under a resting mouse. At 390 the strip moved 827 px and the detail switched to the loop node now under the pointer (N4). This is the round-1 major-3 symptom, through the other path. On touch, a tap also makes the strip jump (N5). |
| M5 car markers and `interactive` | **VERIFIED-FIXED** | **Taps:** I tapped every badge centre at 640, 768, 1024 and 1280 (s7-badges.js). There were 0 wrong taps. The minimum distance between badge centres was 35.9, 42.1, 33.5 and 48.8 px, and every badge was inside the drawing.<br>**Below `sm`:** at 390 the car is `role="img"` with 0 options.<br>**Resizing** from 1280 to 390 with a badge hovered or focused leaves no stuck preview (s8-resize.js). The ping is `pointer-events-none` and runs 3 times.<br>Nit N14 is about the spacing spec's premise. |
| M6 above the fold | **VERIFIED-FIXED** | **Fold:** the strip's bottom stayed inside the viewport in 40/40 live samples at 1280×720 and at 1440×900, with 2–3 warnings showing.<br>**Horizontal scroll:** none at 1280.<br>**Headings:** there is one `h1`. |
| M7 debounced live region | **PARTIAL** | **Done:** the debounce follows the letter of M7: a 2 s hold, a 5 s gap, specs on `textContent`.<br>**Still wrong:** while the break keeps moving, a verdict change is never announced (N2). The probe went CLOSED to OPEN with the break moving every 1.5 s and got 0 announcements in 60 s. Live, there was 1 announcement in 60 s while the visible title changed 58 times. |
| M8 no layout shift | **REGRESSED** (live) | **Done:** the slot always renders, with "No sensor warnings" when empty.<br>**Fails live (s6-shift.js, 20 s):** CLS was 0.556 at 1440 (round 1 measured 0.293), 0.695 at 1280 and 3.78 at 390. The strip's top moves between 403, 424, 451 and 472 px at 1280. Two things cause it: the slot wraps to 2 rows (88 to 136 px) when mismatch, intermittent and silent warnings all show, and the banner body switches between the culprit sentence and the chip row (21 px). See N3. |
| M9 wording and wiring | **VERIFIED-FIXED** | `segmentState` and the labels are as specified, with specs. Live, the wire after TSMS is dashed downstream (screenshot). |
| M10 shape, not only colour | **VERIFIED-FIXED** | A spec asserts that `(icon, dash, emphasis)` is distinct per state. The core and casing widths are in `WIRE_WIDTH`. The frame image has `grayscale opacity-30`. |
| M11 callout never scrolls the page | **VERIFIED-FIXED** | I selected each of the 19 loop nodes at 375 and 640: `scrollWidth === clientWidth` every time (s12-fold.js). |
| M12 contract tests | **VERIFIED-FIXED** (with a gap) | `expectLoopViewContract` covers the six listed behaviours and runs from the strip and car specs. The page spec covers the banner chip end to end.<br>**Gap:** the helper only fires `mouseenter`/`mouseleave` on the option element itself, so N1 got through. |

Overall: 6 of the 11 MUSTs (M2–M12) are verified fixed, 4 are partial and 1 has regressed live.

## New findings

### N1 · major · Hover preview is lost while the pointer is still on a strip option
- **Where:** `loop-view/loop-node-listbox.directive.ts:46-47` and `:77-81`.
- **Issue:**
  - The capture-phase `mouseleave` listener sees every descendant's `mouseleave`.
  - Moving from a child (the disc, the label span) onto the option's own padding fires `mouseleave` with target = child. `nodeIdOf(child)` resolves to the same option, so it emits `nodePreview(null)`, or the focused id.
  - No `mouseenter` follows, because the pointer never left the `<li>`.
  - From then on the preview stays cleared until the pointer leaves the whole item.
- **Steps:**
  1. Open the page at 1280, blocked, with the mock's "Break at TSMS".
  2. Hover the BOTS disc. The detail shows "Loop node | 9 BOTS".
  3. Move down into the `<li>`'s bottom padding. The detail shows "Where the loop broke | 12 TSMS" and the car highlight is gone, while `elementFromPoint` is still the BOTS `<li>`.
  4. A 51-point sweep inside the BOTS option lost the preview at 26 points (s14-sweep.js).
  5. A probe spec gives previews `["b","b",null]` for child-leave into the parent.
- **Fix:**
  - In `onPointerLeave`, return when `(event as MouseEvent).relatedTarget` is inside the same option: `relatedTarget?.closest('[data-node-id]') === target.closest('[data-node-id]')`.
  - Or switch to delegated `pointerover`/`pointerout` and compare option ids.
  - Add the child-to-parent case to `expectLoopViewContract`.
- **Evidence:** `r2-correctness-hover-lost-inside-option-1280.png`. The BOTS column shows hover-bg, but the detail is on TSMS and the car has no BOTS ring.

### N2 · major · Under a moving break, the live region never announces that the loop opened
- **Where:** `components/loop-banner/loop-banner.component.ts:166-199`, and `loopSummary` in `shutdown-loop.display.ts:379`.
- **Issue:**
  - The live text is `loopSummary`, which includes the break's label.
  - Every break move restarts the 2 s hold, so a verdict change (CLOSED or UNKNOWN to OPEN) is not announced while the break is intermittent, which is the real-world case the S1 chip exists for.
  - The screen-reader text also keeps naming a stale cause indefinitely.
- **Steps and evidence:**
  - **Probe spec** (fake timers): announced "LOOP CLOSED · AIRs on", then OPEN with the break alternating BMS/IMD every 1.5 s for 60 s. The announcements stayed `["LOOP CLOSED · AIRs on"]`.
  - **Live (s1-live.js, 60 s):** the region changed once, to "LOOP OPEN — cause at or before BMS latch" at about 1.3 s. The visible title changed 58 times, between "LOOP OPEN", "· IMD latch" and "· BSPD latch".
- **Fix:**
  - Debounce the verdict separately: announce a verdict change once the verdict has held 2 s, whatever the break does.
  - While the break is moving, announce the intermittent form once, for example "LOOP OPEN — intermittent between BMS latch, IMD latch and BSPD latch".
  - Add a spec for "verdict change under a flapping break is announced within 2–5 s".

### N3 · major · The page still jumps under live data (M8 regressed), and pointing at the strip becomes unreliable
- **Where:**
  - `components/loop-banner/loop-banner.component.html:264-288`: the warning slot is only `min-h-10`, and 2–3 warnings wrap.
  - `:233-251`: the culprit sentence and the chip row differ in height.
- **Issue:** with the sim, the strip and everything below it move vertically several times a second.
- **Evidence (s6-shift.js, live, 20 s):**
  - **1440:** CLS 0.556. Round 1 measured 0.293 with the same method.
  - **1280:** CLS 0.695. The strip's top was at 403, 424, 451 and 472 px.
  - **390:** CLS 3.78. The strip's top was at 404, 428, 474, 529, 583 and 599 px.
  - **Slot heights:** 88 and 136 px at 1280, and 132, 186 and 202 px at 390.
  - **Effect on pointing (s5d-live.js):** with the mouse resting on BSPD at 1280, the detail showed BSPD in only 1 of 40 samples and the break in 39. The event log shows `mouseleave` with `relatedTarget=UL` while the mouse was still: the item slid out from under it.
- **Fix:**
  - Give the slot a fixed height for one row, with a horizontal scroller or `line-clamp-1` and an expand control, or one combined line.
  - Or reserve two rows and never exceed them.
  - Give the verdict body a `min-h` equal to the chip row's height.

### N4 · minor · The stretch auto-scroll moves the strip under a resting mouse
- **Where:** `components/loop-strip/loop-strip.component.ts:142-147`.
- **Issue:** the stretch path checks only the 5 s user-scroll lock, not `pointerOver`. A mouse resting on the strip (below `lg`) without wheeling is scrolled away, and Chrome's synthetic boundary events then preview whatever loop node is now under the pointer.
- **Steps (s5b.js):**
  1. Open the page at 390 with a mouse, blocked, with "Break at BMS latch".
  2. Rest the mouse on BRB L for more than 5 s. The detail shows BRB L.
  3. Click the mock button "Break at Acc sense" programmatically. `scrollLeft` goes from 0 to 827, the element under the pointer becomes `em-interlock`, and the detail shows "14 Energy meter interlock". After a 2 px move it shows "15 Accumulator sense".
  4. The same happens at any width where the strip scrolls, which is every width below `lg`. At 1024 everything fits after the M6 change.
- **Fix:** skip the stretch scroll while `pointerOver`, and run the pending stretch scroll on `pointerleave`, subject to the 5 s lock.

### N5 · minor · On touch, tapping a half-visible strip item makes the strip jump about 180 px
- **Where:** `loop-strip.component.ts:136-141`, with the template's `pointerenter`/`pointerleave` on the scroller.
- **Issue:** for touch, `pointerleave` fires right after `pointerup`, before `click` selects, so `pointerOver` is false when the selection effect runs. It then scrolls to `left - clientWidth/3`. Native focus had already scrolled the item into view by about 24 px ("nearest"), so this extra jump only moves the item away from where the finger was. A quick second tap, for example to unpin, can land on a neighbour.
- **Steps (s10-tapscroll.js):** at 390 with touch, from `scrollLeft` 0, tap IMD latch, which is half visible at the right edge. `scrollLeft` becomes 179.
- **Fix:** record `pointerdown` on the scroller (any `pointerType`) and skip the selection scroll within about 1 s of it, or keep `pointerOver` true for touch until the next frame after `click`.

### N6 · minor · The tab stop does not follow a pin made in the other view, and Tab-in replaces the pinned loop node in the detail
- **Where:** `loop-view/loop-node-listbox.directive.ts` has no sync. Aria's `setDefaultStateEffect` stops once `hasBeenInteracted`, which focusin alone sets.
- **Steps (s4-kbd.js, 1280, blocked):**
  1. Click strip BMS latch twice: pin, then unpin.
  2. Click the car's HVD badge. HVD is pinned, but the strip's tab stop stays `bms-latch`.
  3. Tab into the strip. Focus lands on BMS latch, and the focusin preview replaces "Selected loop node | 13 HVD" with "Loop node | 4 BMS latch".
- **Fix:** in the directive, add an `effect` on `listbox.value()`. When `!host.contains(document.activeElement)`, call `listbox._pattern.setDefaultState()`. That only sets `activeItem` (the tab stop) to the selected option and does not move focus. It is not public API, so wrap it in one place with a spec that pins the Aria version. Re-check this when `@angular/aria` is upgraded.

### N7 · minor · "Show the break" drops keyboard focus to `<body>`
- **Where:** `components/loop-node-detail/loop-node-detail.component.html:187-199`. The button is inside `@if (pinnedId())`.
- **Steps (s4-kbd.js):**
  1. Pin a loop node.
  2. Focus the unpin button and press Enter.
  3. `document.activeElement` is `BODY`. The next Tab goes to the car's stale tab stop (HVD), not near the detail.
- **Fix:** after `unpin.emit()`, move focus to the detail section, using `tabindex="-1"` on its heading. Or keep the button rendered and `aria-disabled` when nothing is pinned.

### N8 · minor · With `source==='server'`, explainNode cites a reading this client never received
- **Where:** `shutdown-loop.display.ts:267-270` (`contradictsServer` is false when `s.value === undefined`), and `:285` (`cites = measured && !contradictsServer`).
- **Issue:** this breaks M2 ("cites a value only when that value agrees with the state"). Under server states, a measured loop node with no local reading is explained as "Reads 1: 24 V is present just after it.", while the same panel shows "Value —" and "Updated never". The unmeasured case has the same problem: "Inferred closed: Accumulator sense further along the loop reads 1" when Accumulator sense has no local value. This happens on page load, before slow topics arrive, or when the client dropped messages, which is the reason `source` exists.
- **Evidence:** probe spec (server codes all closed, no local HVD/BMS readings): `hvd server closed undefined -> Reads 1: 24 V is present just after it.`
- **Fix:**
  - Set `cites = measured && s.value !== undefined && s.value === expectedValue(s)`.
  - Use the same agreement test for `next` in the closed/unmeasured branch.
  - When the server decided and there is no local value, say "scylla-server sees it closed; this client has no reading yet".

### N9 · minor · A server no-data next to a fresh local reading gives "No new reading for 1 s (it goes stale after 5 s without one)" and "BMS 1 s ago · stale"
- **Where:**
  - `shutdown-loop.display.ts:324-333`: the no-data branch uses the local `ageMs` and `staleAfterMs`.
  - `:358-366` and `components/loop-meta/loop-meta.component.ts:61-66`: `stale` comes from the server states, but `ageMs` comes from local readings.
- **Steps (s9-mock.js, live):**
  1. Click Publish, then Stop publishing.
  2. The meta chip reads "BMS 1 s ago · stale" with "Status: scylla". The server never saw the mock's BMS readings.
  3. The probe spec gives `No new reading for 1 s (it goes stale after 5 s without one), so it is skipped.` and `{"board":"BMS","ageMs":1000,"staleCount":4,"stale":true}`.
  4. Outside the mock, the same mismatch appears whenever the server's and the client's staleness disagree.
- **Fix:**
  - Under `source==='server'`, if `ageMs < staleAfterMs`, explain it as "scylla-server has no live reading from it; this client last heard it 1 s ago".
  - In the chip, show "stale (scylla)", or drop the local age when `stale` comes from the server.

### N10 · minor · Leaving a car badge clears the strip's keyboard preview
- **Where:** `loop-node-listbox.directive.ts:77-81`. Each directive only knows its own host's focus, and the store has one `previewId`.
- **Steps (s15-cross.js, 1280):**
  1. Tab into the strip and arrow to BRB L. The detail shows BRB L.
  2. Hover the car's AIRs badge. The detail shows AIRs.
  3. Move the pointer away. The detail shows "Where the loop broke | TSMS" while focus is still on strip BRB L.
- **Fix:** split the store's preview into `hoverId` and `keyboardId`, with `activeId = hoverId ?? keyboardId ?? selectedId`. The directive sets `keyboardId` on focusin/focusout and `hoverId` on enter/leave.

### N11 · nit · The banner's culprit sentence always says "Reads 0"
- **Where:** `loop-banner.component.html:234`.
- **Issue:** the string is hard-coded and does not use the `contradictsServer` logic. When scylla's state and the local value disagree, the banner says "Reads 0 while the reading before it is closed", while the detail says "Open while …" and adds the scylla note "latest reading is 1 (closed)".
- **Evidence:** code-verified. The live sample hit 0 of 120 polls, because the server note only appeared with several suspects.
- **Fix:** use `explainNode(culprit, status)`, or the same `cites` rule.

### N12 · nit · The mock panel's TS toggle flips both its label and `aria-pressed`
- **Where:** `components/mock-panel/mock-panel.component.html:118-120`.
- **Issue:** "TS OFF" is announced as not pressed, which is ambiguous. A toggle button keeps a fixed label.
- **Fix:** label it "TS ON" with `aria-pressed`, or use a two-option segmented control.
- **Note:** the behaviour itself is correct. Live, the chip went to "BMS: TS ON" within about 1 s, and the source chip went to "this client" on Publish and back to "scylla" on Stop.

### N13 · nit · The car's options use the full label, not `SHORT_LABEL` (contract §3)
- **Where:** `components/car-view/car-view.component.html:89`.
- **Issue:** typeahead differs between the two listboxes.

### N14 · nit · The badge-spacing spec measures the wrong drawing size
- **Where:** `components/car-view/car-view.layout.ts:222` and `car-view.layout.spec.ts:10`.
- **Issue:** the spec assumes the narrowest interactive drawing is 600×321 px at `sm`. Live, it is 558×299 at `lg` = 1024, because the detail column takes 24rem. The minimum distance there is 33.5 px, so it passes today, but the spec does not guard the real worst case.
- **Fix:** measure at 558×299, or derive it from the `lg` grid.

### Checked and fine (no finding)
- **Touch tap toggling:** works on the strip at 390 and 1024, and on the car at 1024.
- **Escape**, and **resizing** across `sm` (no stuck preview or focus).
- **BreakpointObserver `requireSync`.**
- **Ping:** re-keyed per break id through `@if (m.isBreak)` inside the tracked option.
- **Cleanup:** the directive removes its listeners, and the banner and mock clear their timers.
- **OnPush:** `pointerOver` is a plain field that is read only in handlers and untracked effects, so this is fine.
- **Intermittent chip:** refreshes on the 1 s status tick.
