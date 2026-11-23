# Round 1 review: throwaway-shutdown-3d-procedural (lens: live UX, visual quality, accessibility)

Tested live at http://localhost:4202/shutdown with Playwright (Chromium, SwiftShader WebGL, deviceScaleFactor 1). The Calypso sim overwrites the mock panel's values (see the last item), so for deterministic presets socket.io was blocked in the test browser and only the dev mock panel published. Breaks were made with "All closed" and then opening the chosen node plus everything after it. Scripts: `/tmp/claude-0/-home-user-Delphi/6e25b80b-05af-58e5-9050-4f2faa446aec/scratchpad/r1-proc-live/`. Screenshots: `/home/user/Delphi/pictures/throwaway-shutdown-3d-procedural/review-r1/proc-live-*.png`.

**What works (verified):** both `--disable-webgl` and `--disable-3d-apis` fall back to the 2D view with a note. Losing the WebGL context also falls back. The 2D/3D choice survives a reload and leaving and returning to the page. Reduced motion stops the suspect pulse (the canvas stays still while idle; without reduced motion it keeps changing). Clicking a marker selects it and clicking empty space clears it. Escape clears the selection. There is no horizontal scroll at 390 or 1280. The card sits top-left on desktop and moves below the canvas on a phone. The 3D code logs no console errors. The only errors are the existing NG0100 from `MessagesPerSecondComponent` in the nav bar, plus SwiftShader "GPU stall" warnings. Car credibility: the proportions are plausible (wheelbase 1.63 m, track about 1.2 m, main hoop 1.22 m). The space frame, hoops, braces, nose, steering wheel, wishbones and four wheels read as an FSAE car in "x-ray". The greys fit the dark theme. The tyres are chunky flat-shaded drums and there is no floor, seat or sidepods. That is fine for a diagnostic view.

## Findings

- **blocker** · Top preset (and Iso for the sense cluster) · **The culprit can be completely invisible.** Node labels are sprites lifted +y and drawn with `depthTest: false`. From Top, every label sits exactly on top of its own marker and on top of neighbours at the same x. The latches (y 0.5) and sense points (y 0.22) share x, so labels 4–7 cover markers and labels 15–19. With a TS+ sense break in Top, no red is visible anywhere: about 139 stray red pixels, against 1,838 for a TSMS break in Iso. In Iso, the TS+ marker sits behind the HVD marker and its label "18" sits under "13". Red pixels in the canvas by break: TSMS/iso 1838, Cockpit BRB/iso 916, BOTS/iso 387, TS+/iso 318, TS+/side 205, IMD latch/top 188, TS+/top 139. Salience varies about 13× by location, so "obvious within 2 s" fails for the sense points and latches.
  - Steps: mock panel → All closed → toggle `TS+ sense = 0` → Publish → click Top (or stay on Iso).
  - Fix: draw labels in screen space (CSS2DRenderer or an HTML overlay) with collision avoidance and leader lines, offset sideways rather than toward the camera. Always draw suspect markers and their labels last and on top: `depthTest: false` and `renderOrder` above the other labels. Hide or dim labels of non-suspect nodes in clusters. Add a screen-space halo or ring around every suspect, like the selection ring, so it shows even when occluded. Auto-frame the suspect stretch when the verdict becomes open.
  - Screenshots: `proc-live-05-break-ts-sense-top.png`, `proc-live-05-break-ts-sense-top-zoom.png`, `proc-live-05-break-ts-sense-iso-zoom.png`, `proc-live-05-break-imd-latch-top.png`

- **major** · wire colouring (`buildLoopSegments`: a segment takes the state of the node it *leaves*) · **The red wire points at the wrong place.** The red segment runs from the culprit to the next, downstream node. For a Cockpit BRB break, the brightest red is a long line across the cockpit that ends at TSMS on the main hoop. The culprit marker itself is half hidden behind the steering wheel. For a TSMS break, the red line runs down into the E-box to HVD. For a BMS latch break, the stretch is drawn red 2→3→4 and then on to 5. The eye follows the red to a downstream node, which is the confusion the spec's anti-goal forbids.
  - Steps: All closed → open Cockpit BRB and everything after → Publish → Iso.
  - Fix: colour each segment by the state of its *downstream* end. The wire into a suspect is red and the wire leaving the last suspect is dead or dashed. Only the wires inside the suspect stretch (from P to F) should be red. Optionally add an arrowhead or gap at F.
  - Screenshots: `proc-live-05-break-cockpit-brb-iso.png`, `proc-live-05-break-cockpit-brb-iso-zoom.png`, `proc-live-02-tsms-iso.png`

- **major** · colour-vision safety (3D markers, wires, node toolbar) · Under a deuteranopia simulation (feColorMatrix on the page), suspect red and closed green become the same mustard. The culprit wire is then indistinguishable from the closed wires. The node-toolbar buttons rely on colour only: a coloured border with a number, no glyph. Button 12 (cause) looks identical to button 11 (closed). Marker shapes do differ (octahedron vs sphere vs cone vs cube), but at roughly 15–20 px on desktop and under 8 px on a phone they can't be told apart. Spec: "Status must not rely on colour alone".
  - Steps: TSMS break, Iso; apply the deuteranopia matrix (script `s6.js`).
  - Fix: put the strip's status glyph (check / x / arrow / ?) inside or next to each toolbar button. Give suspects a non-colour cue in 3D: a larger size, a screen-space ring or halo, a thicker wire with a pattern or animated dash, or an "x" badge on the label. Consider a blue/orange-safe pair or adding a luminance difference.
  - Screenshots: `proc-live-19-cvd-deuteranopia-tsms.png`, `proc-live-19-cvd-protanopia-tsms.png`

- **major** · clustered nodes (latches 4–7, sense 15–18 + AIRs 19, HVD 13 / EM 14, GLVMS 1 / TSMS 12) · Clustered nodes are hard to tell apart. The latches and sense points are 7 cm apart in a row and their labels touch. From Iso, "18" is fully covered by "13" and the 17/18/19 markers are hidden behind 13. From Top, 17–19 vanish under 4–6. The labels are numbers only, so the reader has to cross-reference the toolbar or strip to learn that 18 is TS+ sense.
  - Fix: use screen-space labels with leader lines fanned out from the cluster, showing short names (TS+, IMD) at least for suspects. Offer an "explode cluster" or focus-zoom when a cluster is selected, or space the cluster nodes further apart in the model, since the positions are schematic anyway. Put the culprit's name in a leader-line callout on the car.
  - Screenshots: `proc-live-05-break-ts-sense-iso-zoom.png`, `proc-live-nosim-03-tsms-top.png`

- **major** · phone 390×844 · On a phone the stage is 326×280 px. Node labels render at about 6–8 px and are unreadable, and markers are a few pixels. The 3D view is still the default on a phone, so the culprit is only readable from the banner and the toolbar. Selecting a node works and the card stacks below the canvas.
  - Fix: default to 2D under about 600 px, or when `pointer: coarse` and no choice is stored. Or use screen-space labels at a fixed CSS size. Auto-frame the suspect so it fills the small canvas.
  - Screenshots: `proc-live-15-phone-390-full.png`, `proc-live-16-phone-390-selected.png`

- **minor** · wire routing · The loop is drawn as straight node-to-node tubes, which gives long diagonals through the car. 8 (MC, rear) → 9 (BOTS, pedal box) runs the full length through the cockpit. 11 → 12 crosses the cockpit. 12 → 13 and 14 → 15 cut through the E-box and accumulator. From Top the wire crosses the car about 4 times. The wire is the same thickness as the frame tubes, so in grey (downstream) it reads like frame.
  - Fix: route the harness along frame rails through a few waypoints per segment, such as the lower side rail and the main hoop, or draw it as a thinner glowing line clearly distinct from the frame. At minimum, make dead (downstream) wire visually lighter than the frame.
  - Screenshots: `proc-live-nosim-03-tsms-top.png`, `proc-live-05-break-bots-iso.png`

- **minor** · zoom limits (`controls.minDistance = 0.8` around the target inside the E-box) · Zooming fully in puts the camera inside the space frame, among the tubes. World-sized label sprites then blow up to about 80 px badges and the view becomes unreadable. Orbiting while zoomed in clips through the tubes.
  - Steps: Iso → scroll-wheel in about 40 notches → drag.
  - Fix: raise `minDistance` to about 1.6–1.8, or set the near plane and clamp so the camera stays outside the car's bounding box (`CAR_EXTENT_3D`). Keep labels at a constant screen size.
  - Screenshots: `proc-live-09-zoom-min.png`, `proc-live-10-zoom-min-orbit.png`

- **minor** · pan limits · Panning with right-drag is unbounded. Three drags and the car leaves the canvas entirely, with no hint how to get it back. The presets do reset the target. Max zoom-out (8 m) leaves the car small but visible, which is OK.
  - Fix: clamp `controls.target` to the car's extent on `change`, or disable pan. Add a "Reset view" label or make "Iso" visibly the reset.
  - Screenshots: `proc-live-12-panned-away.png`, `proc-live-11-zoom-max.png`

- **minor** · selection · Selecting a node, by click or toolbar, only draws a thin light-grey ring. The camera doesn't move, so a selected node that is occluded (for example 18 in Iso) stays hidden behind other markers, and the card doesn't say where on the car the node is.
  - Fix: focus-zoom (tween the target to the node and dolly in) when a node is selected, unless reduced motion is on, in which case jump. Add a "Where" row to the card in words, such as "Right main-hoop brace, behind driver's right shoulder". This is the page's "where it physically is" job, and screen readers need it too. Consider an x-ray toggle that fades the frame to about 20 % to declutter.
  - Screenshots: `proc-live-07-card-acc-sense.png`, `proc-live-16-laptop-1280-selected.png`

- **minor** · mismatch display · A mismatched node shows only a tiny "13!" label in the 3D view. Its marker is otherwise identical, and the toolbar button and its aria-label ("13 HVD: Open — upstream") carry no mismatch at all. The banner does say "Sensor mismatch: HVD read closed after the break".
  - Steps: TSMS break, then toggle `HVD = 1`, wait 2 s.
  - Fix: add the mismatch to `ariaLabel` and give the toolbar button a warning badge. Use a distinct warning colour or shape on the 3D marker or label.
  - Screenshot: `proc-live-20-mismatch-hvd.png`

- **minor** · node toolbar keyboard model · Arrow keys move focus *and* select (selection follows focus), so each arrow press re-renders the card. The card is in `aria-live="polite"`, so arrowing across 19 nodes queues 19 announcements. Pressing Space on a node that arrowing just selected *closes* the card (toggle), which is surprising. Tab order, Home/End, Escape and the visible focus ring work.
  - Fix: let arrows move focus only and Enter/Space select (or keep selection-follows-focus but drop the toggle-off on Space). Announce only "12 TSMS, Open — cause" rather than the whole card.

- **minor** · touch target size · Node buttons are 28×24 px and preset buttons 38×24 px. That passes WCAG 2.5.8's 24 px minimum but is small for a trackside tablet or gloves.
  - Fix: use 44 px targets under `@media (pointer: coarse)`.
  - Screenshot: `proc-live-16-phone-390-selected.png`

- **minor** · WebGL fallback and context loss · In the fallback, the 2D/3D toggle still shows **3D** as pressed while the 2D view is displayed. After a context loss (forced with `WEBGL_lose_context`), the note says "unavailable on this device" even though it worked a moment ago. Keyboard focus drops to `<body>`, losing the user's place in the toolbar, and the selection is lost. The fallback itself renders correctly.
  - Fix: disable the 3D option or mark it "3D (unavailable)" in the fallback. Use a different message with a "Retry 3D" button for context loss. Keep `selectedId` in the switcher so it survives the swap, and move focus to the view's container.
  - Screenshots: `proc-live-17-nowebgl--disable-webgl.png`, `proc-live-21-context-lost.png`

- **minor** · dev mock panel vs the live sim · With the Calypso sim connected, the "All closed" and "Break at TSMS" presets have no visible effect. The banner stayed "cause is one of: Side BRB R, Side BRB L, BMS latch" through both, because the sim's faster updates overwrite the mock's 1 Hz publishes. Reviewers and devs can't use the presets without cutting the socket.
  - Fix: have the mock panel shadow (ignore) live shutdown topics while publishing, or publish at the sim's rate. Or label the panel "stop the sim to use presets".
  - Screenshot: `proc-live-01-sim-initial-full.png`

- **nit** · framing and layout · The Iso preset crops the bottom of the near rear tyre at 1440×900 and 1280×720. The 3D/2D toggle takes its own row above the canvas, leaving about 50 px of dead space, while the presets float inside the canvas. At 1280×720 the loop strip is below the fold.
  - Fix: move the camera back slightly or lower the target y. Put the 3D/2D toggle in the same overlay row as the presets.
  - Screenshots: `proc-live-15-laptop-1280-viewport.png`, `proc-live-02-tsms-iso.png`

- **nit** · no keyboard orbit or zoom · The canvas isn't focusable and `controls.listenToKeyEvents` is never called, so keyboard users only have the three presets. That is acceptable, but a focusable stage with arrow-key orbit and +/- zoom would complete it.

- **nit** · downstream vs no-data · Their colours are nearly the same (#8a8a8a vs #8b93a1) and both wires are drawn dashed grey, so the two states differ only by marker shape (cone vs cube).
  - Fix: use a different dash pattern, or dotted for no-data.
  - Screenshot: `proc-live-nosim-01-sim-initial-full.png`

- **nit** · 2D/3D round trip · Switching to 2D and back resets the camera to Iso and drops the selection.
  - Fix: keep the preset and selection in the switcher.

- **nit** (out of this branch, seen via the fallback) · The 2D side view's photo has red frame tubes, which compete with the red suspect colour. A red "12" sits among red tubes.
  - Screenshot: `proc-live-17-nowebgl--disable-webgl.png`
