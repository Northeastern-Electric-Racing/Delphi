# Round 2 review: throwaway-shutdown-3d-procedural (lens: live UX, visual quality, accessibility)

I tested the branch at 4df0fb6b live on http://localhost:4202/shutdown, using Playwright with Chromium, SwiftShader WebGL and deviceScaleFactor 1. socket.io was blocked in the test browser so that only the dev mock panel published. A break at node k was made by setting mock nodes k and later to 0 and every node before k to 1.

- **Scripts:** `/tmp/claude-0/-home-user/6e25b80b-05af-58e5-9050-4f2faa446aec/scratchpad/r2rev-proc-live/`:
  - `sweep.js`, which measures every break × preset × viewport;
  - `count.py`, which counts suspect-colour pixels in the canvas only, with the overlay hidden;
  - `drift.js`, `touch*.js`, `defaults.js`, `fb2.js`, `cvd.js`, `kbd.js`, `zoom4.js`.
- **Raw sweep output:** `sweep-{1440x900,1280x720,390x844}.json`, plus the contact sheets `sheet-*.png` built from `shots/`.
- **Screenshots:** `/home/user/Delphi/pictures/throwaway-shutdown-3d-procedural/review-r2/proc-live-*.png`.

## Round-1 blocker re-check: culprit visibility across every break location

The sweep covers 14 break locations (every mock-measurable node: BMS, IMD, BSPD and CAN latches, MC HVIL, BOTS, Inertia, Cockpit BRB, TSMS, HVD, Acc, TSIP, TS− and TS+ sense), each in Iso, Side and Top, at 1440×900, 1280×720 and 390×844 (phone, 3D opted in). That is 126 combinations.

| Check | 1440×900 | 1280×720 | 390×844 |
|---|---|---|---|
| Every suspect has a halo, fully inside the stage and the viewport | 42/42 | 42/42 | 42/42 |
| The cause badge is shown and inside the stage | 42/42 | 42/42 | 42/42 (overview: one badge) |
| Halo under the preset toolbar or the hint | 0 | 0 | 0 |
| A badge reaches within 14 px of a halo centre (into the ring) | 1 (BMS stretch, Iso: "12") | 1 (BMS stretch, Side: "4 BMS" on its own halo) | 0 |
| Another badge overlaps the cause badge | 0 | 1 (TSIP, Top: "18" touches "16 TSIP") | 0 |
| Suspect-colour pixels drawn by the canvas at the suspect marker (overlay hidden; min / median) | 55 / 233 | 37 / 156 | 15 / 39 |

Round 1 measured 139 stray red pixels with no visible culprit (TS+ in Top). Now every suspect marker draws through the scene: `depthTest:false` plus render order 10, at 37–490 px on desktop. On top of that, the halo and badge are HTML and always visible. The salience spread between break locations dropped from 13× to about 3×, and the HTML cues no longer depend on it.

- Contact sheets: `sheet-1280-a.png`, `sheet-1280-b.png`, `sheet-1440-*.png` and `sheet-390-*.png` in the scratch dir.
- Representative shots: `proc-live-30-phone-390-3d-optin-tsms.png`, `proc-live-60-compare-3d-tsms-1280.png`.

**The blocker is fixed.** Two caveats follow as new findings: in some views the cause badge sits far from its halo (N1), and badge widths are underestimated (N2).

## Round-1 MUST status (this lens)

| MUST | Status | Evidence |
|---|---|---|
| M1: culprit always visible; screen-space badges and halo | **VERIFIED-FIXED** (with N1 and N2) | Table above. HTML badges stay 24 px at any zoom (`proc-live-80-zoom-min.png`, `proc-live-81-panned-zoomed-out.png`). Suspects are placed first. The canvas suspect marker draws through the frame. |
| M2: picking (live part) | VERIFIED (live spot check only; correctness is another lens) | Clicking the TSMS badge pins TSMS. A touch tap in the phone overview changes nothing (by design). |
| M3: render on demand | not this lens | The halo motion is CSS `motion-safe:animate-ping`, 3 iterations, re-keyed when the break moves, and off under reduced motion. |
| M4: the wire after the break | **VERIFIED-FIXED** (under the UI contract's `segmentState`) | Cockpit BRB break, Side: the wire from Cockpit BRB to TSMS is dashed grey, and no orange segment leaves the cause (`crop-cockpit-side.png` in scratch). In a multi-suspect stretch the run is strong orange (BMS 2→3→4, EM→Acc). A single cause has a green wire in and a dashed wire out, the same as the strip and the 2D car (`proc-live-61-compare-2d-tsms-1280.png`). |
| M5: non-colour cues and colour-blind safety | **VERIFIED-FIXED** | Under deuteranopia, protanopia and achromatopsia, the TSMS and TS+ causes are still identifiable by the ✕ glyph, the "12 TSMS" name text, the halo ring and the strong wire on stretches (`proc-live-40-cvd-*.png`). Downstream is dashed and no-data is dotted. The mismatch pip shows on the badge, and the title carries "sensor mismatch" (`proc-live-70-mismatch-hvd-1024.png`). See N8 for the one weak spot. |
| M6: selection contract (live part) | **VERIFIED-FIXED** | A strip keyboard pin on HVD highlights the 3D badge and dollies the camera to it (`proc-live-50-strip-keyboard-pin-focuses-3d.png`). A badge pick opens the page's single detail. A context loss with TSMS pinned keeps the pin in 2D, and "Retry 3D" restores the highlight on TSMS. The toolbar and the info overlay are gone. |
| M7: whole car in every preset at 1440, 1280 and 390 | **VERIFIED-FIXED** (nit N9) | All 126 shots show all four wheels; the round-1 Iso rear-tyre crop is gone. On a phone in Top, the preset toolbar sits over the front-left wheel area. |
| M8: default view rule | **VERIFIED-FIXED** | With no storage: 1440, 1280 and 1024 with a fine pointer give 3D; 1023 with a fine pointer gives 2D; 1280 with touch (coarse) gives 2D; 390 phone gives 2D. A stored `'3d'` on a 390 phone gives 3D. The storage-throws case is not checked live: my getter-throw init stopped the app shell before the page rendered. The unit specs cover it. |
| S3: fallback notices | VERIFIED | `--disable-webgl` and `--disable-3d-apis` show "3D view unavailable (no WebGL). Showing 2D." A blocked three chunk shows "The 3D view failed to start. Showing 2D." A context loss shows "…lost its graphics context (sleep or GPU reset)…". In every case 2D is pressed and 3D carries `aria-description="unavailable; press to retry"`. Focus moves to the car section. A retry re-fails cleanly for WebGL and recovers after a context loss (`proc-live-20/21/22-*.png`). |
| S4: camera on select, zoom and pan limits | VERIFIED | Pinning dollies in. After 4 right-drag pans plus a full zoom-out, the target stays on the car. |
| S6, S7: mismatch cue and names on suspect badges | VERIFIED | "12 TSMS", "11 Cockpit BRB", and a warn pip on HVD. |
| S11: one finger scrolls, two fingers orbit (touch phone) | **VERIFIED** | With CDP touch at 390×844 (coarse pointer): a one-finger vertical drag over the canvas scrolls the page (scrollY 451→576) and the camera doesn't move. A one-finger horizontal drag does nothing. A two-finger drag and a pinch orbit and zoom without scrolling (`proc-live-31-phone-390-after-two-finger-orbit.png`). |

## New findings

### N1 (major): the cause badge can sit about 75 px from its halo, behind other badges, with an invisible leader

- **Where:** :4202/shutdown at 1280×720, Iso (the default view).
- **Code:** `angular-client/src/pages/shutdown-page/components/car-view-3d/car-view-3d.projection.ts`, in `placeBadges`: `if (prev !== undefined && prev < SPOTS.length && cost(prev) === 0) spot = prev;`. It is fed by the component's `linkedSignal` `previous`.
- **Issue:** placement keeps each badge's previous spot. A node that was crowded out to the far ring as a non-suspect (54 px gap, about 76 px from its marker) keeps that spot when it becomes the cause, because nothing overlaps it there. The suspect-first rule from M1 ("the culprit gets its preferred spot") is skipped.
- **Leader line:** the badge's leader is a 1 px `stroke-fg-muted` SVG line *under* the badges. Over the frame it is indistinguishable from a tube, and badges 16 and 15 cover it.
- **Result:** the orange halo marks one place, and the "18 TS+" pill sits next to the BOTS badge and the pedal-box wire.
- **Steps:**
  1. All closed, Publish.
  2. Break at TS+ sense (fresh load, or after TSMS).
  3. Look at Iso.
- **Measured** (distance from the cause badge's edge to its halo centre, `drift.js`), against 15–17 px for the rest:
  - TS+ 76 px; TS− 77 px;
  - EM 54 px (Acc stretch);
  - TSIP 45 px; Cockpit BRB 45 px;
  - CAN 43 px (MC HVIL stretch).
- **Fix:**
  - Ignore `previous` for suspect points, or whenever a point's `suspect` or highlight flag changed since the last placement. Simplest: key the hysteresis by `id + suspect`.
  - Draw suspect leaders in the danger colour, above the badges.
- **Acceptance:** a spec where a point placed at spot ≥ 8 becomes a suspect lands on spot 0–7.
- **Evidence:** `proc-live-05-ts-plus-after-tsms-iso-1280-badge-far.png`; `crop-leader.png` in scratch.

### N2 (minor): badge widths are underestimated by 3.6–4.1 px, so left-placed badges grow into their own halo and their neighbours

- **Code:** `car-view-3d.utils.ts`, `badgeModels` `width: Math.ceil(26 + text.length * 7 + …)`; the template sets it as `[style.min-width.px]`.
- **Issue:** the comment budgets a 14 px glyph, but `ui-icon size="xs"` is 16 px (`icon.component.ts`). Text also runs wider than 7 px per character. Measured: 17 of 19 badges are wider than estimated ("✓1" estimated 33, rendered 36.8; "4 BMS" 61 vs 65.1).
- **Why it matters:** a badge placed to the *left* of its marker (`left = x − gap − width`) overflows rightward, toward the marker.
- **Seen:**
  - 1440 Iso, BMS stretch: badge "12" overlaps the BRB L halo.
  - 1280 Side, BMS stretch: "4 BMS" sits 14 px from its own halo centre, which is inside the 16 px keep-out.
  - 1 to 3 badge-on-badge overlaps in most Iso views.
- **Fix** (either):
  - measure the rendered badge widths (e.g. read `offsetWidth` after render and re-place once);
  - or correct the constant and anchor left-side badges by `right` instead of `left`.
- **Evidence:** `proc-live-03-bms-break-side-1280-badge-on-halo.png`; `widths.js` output.

### N3 (minor): the mouse wheel over a badge scrolls the page instead of zooming

- **Code:** `car-view-3d.component.html`; the badges are `pointer-events-auto` siblings of the canvas.
- **Issue:** OrbitControls listens on the canvas only. Badges cover about 6.5 % of the stage, concentrated in the E-box and accumulator cluster, which is exactly where people zoom.
- **Effect:** a wheel notch over a badge is not prevented, so the page scrolls by 120 px and the canvas jumps away under the cursor. The next notches then land on the strip or header and keep scrolling.
- **Measured:** scrollY 507→387 on one notch over the BMS badge. Over bare canvas, every wheel event is `defaultPrevented` and scrollY doesn't change.
- **Fix:** connect OrbitControls to the stage container, which contains both the badges and the canvas (`controls.connect(stage)`, or construct with `container`), and keep picking on the canvas. Alternatively, re-dispatch `wheel` and `pointerdown` from the overlay to the canvas.
- **Evidence:** `zoom2.js` (scrollY 507→0 over 10 notches started at the canvas centre) and `zoom4.js`.

### N4 (minor): the phone overview labels only the last suspect of a stretch

- **Where:** 390×844, 3D opted in, BMS-latch break.
- **Code:** `car-view-3d.component.ts`, `badges` (with `!interactive`, only `highlightId ?? breakId`).
- **Issue:** three halos joined by the strong orange wire carry a single badge, "4 BMS". The banner says "Cause is one of: Side BRB R · Side BRB L · BMS latch", but the car reads as "BMS is the cause". The MC HVIL break (CAN + MC HVIL) and the Acc break (EM + Acc) behave the same way.
- **Fix:** in the overview, badge every suspect (there are at most a few, and they're already placed first), or show one stretch badge ("2–4 · one of 3").
- **Evidence:** `proc-live-32-phone-390-overview-bms-stretch-one-badge.png`.

### N5 (minor): a phone with 3D opted in never shows the touch hint, and taps silently do nothing

- **Code:** `car-view-3d.component.html`, the hint `<p … max-sm:hidden>`.
- **Issue:**
  - Under a coarse pointer the hint text is "Two fingers to rotate and zoom", but `max-sm:hidden` hides it on every phone (verified hidden at 390). One finger scrolls (S11, correct), so a user who tries to rotate just scrolls and gets no hint.
  - In the overview (below `sm`), taps on the car do nothing (verified), and nothing says so.
- **Fix:** show a one-line hint on phones too: "2 fingers rotate · pick on the strip".
- **Evidence:** `touch.js` output (`hint visible: false`); `proc-live-30-phone-390-3d-optin-tsms.png`.

### N6 (minor): Iso is the default but fills only about half the stage width, which crowds 10+ badges into the E-box and accumulator

- **Where:** 1440×900 and 1280×720, Iso.
- **Measured:** the car spans 51 % / 48 % of the stage width in Iso, against about 72 % in Side and Top (canvas-only bounding box, `shots/canvas-*-tsms-*.png`). The wide stage (aspect about 2.1) is height-limited from the Iso direction `[1, 0.7, 0.8]`.
- **Effect:**
  - badges 4–8, 12, 13 and 15–18 share a region of about 250×150 px;
  - which badge belongs to which marker is guesswork without hovering;
  - the leaders are invisible (see N1).
- **What still works:** the cause is never hidden, and no badge covers a halo except the N2 cases.
- **Fix:**
  - use a lower, more side-on Iso direction, e.g. `[1, 0.45, 1.1]` (to check against the S8 12 px spacing spec);
  - and/or show non-suspect badges as a bare number pip until hover or zoom;
  - and make leaders visible (`stroke-fg-dim`, 1.5 px, above the canvas but below the badges, not under neighbouring badges).
- **Evidence:** `proc-live-05-…` / `stage-1440-accumulator-sense-iso.png` (scratch `shots/`), `sheet-1440-b.png`.

### N7 (nit): the keyboard route is implicit

- **What works:**
  - Tab through the car section goes to 3D, 2D, Iso, Side and Top only. The canvas and badges are skipped cleanly (`aria-hidden`), with no traps.
  - The stage is `role="img"` labelled "3D car view with the shutdown loop nodes. LOOP OPEN — cause: TSMS".
  - The strip's arrow and Enter keys drive the 3D highlight and camera.
- **What's missing:** nothing in the car card tells a sighted keyboard user that the strip is how to pick. The car hint is pointer-only ("Drag to orbit…"), and the strip's own keyboard hint is `max-md:hidden`.
- **Fix:** append "· select with the loop strip" to the car hint, or add it to the img's label.
- **Evidence:** `kbd.js` output; `proc-live-51-preset-focus-ring.png` (focus ring visible).

### N8 (nit): under colour-vision deficiency the cause badge doesn't pop; it has to be read

- **Where:** CVD simulations, 1280×720, Iso.
- **Issue:** under deuteranopia, protanopia and achromatopsia, the cause pill and the closed pills become the same hue and close in lightness. The cause is found by its ✕ glyph and longer name, and by the halo, which is a thin ring in the same hue as the wires. M5's "identifiable" holds, but "instantly" is weaker than with normal vision. The CSS ping, the one strong non-colour cue, runs 3 times and is off under reduced motion.
- **Fix:** a shape or size cue on the cause badge only, such as a thicker 3 px outline in `fg`, square corners, or a slightly taller pill. Alternatively, make the halo ring thicker or doubled.
- **Evidence:** `proc-live-40-cvd-{deuteranopia,protanopia,achromatopsia}-{tsms,ts-sense}-iso.png`.

### N9 (nit): phone Top view and maximum zoom-out cosmetics

- **Phone Top:** at 390, the Iso/Side/Top toolbar covers the front-left wheel and wishbones (`shots/stage-390-tsms-top.png`).
- **Maximum zoom-out:** at full zoom-out after panning, badges don't shrink while the car does. The crowd forces a compromise, and "✓2" covers part of the TSMS halo (`proc-live-81-panned-zoomed-out.png`).
- **Fix:**
  - reserve the toolbar's height in the fit (top margin) on narrow stages;
  - cap the zoom-out (`MAX_DISTANCE` 2 → about 1.4).

## Questions from the brief

- **Does a single cause without a strong wire still read instantly?** Yes, with normal vision at all three sizes. Under the contract a single cause has a green wire in and a dashed wire out, so there is no orange wire at all. The only orange elements on the stage are then a filled "✕ 12 TSMS" pill and a 28 px halo that pings three times, against all-green and grey badges, and that is the strongest signal on screen (`sheet-1280-*.png`). The weaker cases are N1, where the pill is far from the halo, and N8 (colour-vision deficiency).
- **The default rule and toggle discoverability:** the rule is correct (M8 row). The 3D/2D segmented toggle sits in the "On the car" header at top right on every size, including phones where 2D is the default, with a visible pressed state and a group label "Car view". It is discoverable.
- **Fallback notices:** all three reasons have distinct, plain wording next to the toggle, with a warn glyph, `role="status"`, and a retry by pressing 3D (S3 row). The only weak spot: 3D isn't *visibly* marked unavailable, only through `aria-description`, which is acceptable because the notice sits beside it.
- **Is the procedural car credible and on-brand next to the 2D view?**
  - **On-brand:** yes. Every colour is a theme token, the badges reuse the strip and 2D marker classes and glyphs, the HV boxes are drawn in the secondary-border blue (not danger), and the dark-neutral palette matches.
  - **Credible as a diagnostic x-ray:** yes. Main and front hoops, side tubes, wishbones, four wheels and the E-box/accumulator boxes make it read as an FSAE space frame.
  - **Next to the 2D view** (a detailed render of the real car with motor, accumulator and sprocket), it looks schematic: flat-shaded drum tyres, and the large flat nose pyramid is the biggest solid surface in Iso and draws the eye forward, away from the E-box. There is no floor, seat or sidepods.
  - **Verdict:** fine for a throwaway diagnostic. A smaller or darker nose, or a slimmer cone, would put the focus back on the loop. Evidence: `proc-live-60-compare-3d-tsms-1280.png` vs `proc-live-61-compare-2d-tsms-1280.png`.

No console errors came from the 3D code in any run. The only messages are SwiftShader "GPU stall" warnings and the blocked socket.io requests.
