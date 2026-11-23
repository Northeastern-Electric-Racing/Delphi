# Round 2 review: throwaway-shutdown-3d-gltf (40739def). Lens: live UX, visual quality, accessibility

I tested live on http://localhost:4203/shutdown with Chromium and SwiftShader, deviceScaleFactor 1, dark theme. The :8000 socket was blocked so the sim couldn't overwrite the mock panel. The machine was heavily loaded the whole time (load average about 35, shared with the other reviewers).
- Scripts: `/tmp/claude-0/-home-user/6e25b80b-05af-58e5-9050-4f2faa446aec/scratchpad/r2rev-gltf-live/` (`lib.js`, `s1`–`s10`, `s3c.js` is the hop metric).
- Screenshots: `/home/user/Delphi/pictures/throwaway-shutdown-3d-gltf/review-r2/`.

Counts: 0 blocker, 3 major, 5 minor, 3 nit.

## Round-1 MUST status

| MUST | Status | Evidence |
|---|---|---|
| M1 contract (selection, one panel, badges, fallback, copy) | VERIFIED-FIXED | <ul><li>Strip arrows and Enter highlight and pin the same loop node in 3D (`data-highlighted`, ring).</li><li>Hovering a badge previews HVD in `loop-node-detail`; moving away restores it.</li><li>Clicking a badge pins it; clicking empty canvas unpins; Escape on a 3D preset unpins.</li><li>One detail panel, and no live region in the 3D view.</li><li>Under the shared contract §3.4, badges are `aria-hidden` and have no tab stops. Tab goes 3D, 2D, Side, Top, Iso, Original, Solid, See-through, then the mock panel.</li><li>The stage is `img` labelled "3D car view with shutdown loop nodes. LOOP OPEN — cause: TSMS".</li><li>Fallbacks land in the page's single 2D view, with a `role=status` callout and 3D described as "unavailable; press to retry".</li></ul> |
| M2 frame | VERIFIED-FIXED (live part) | Side preset puts the nose on the left, matching the 2D view (`01-tsms-see-through-side.png` against `05-fallback-truncated.png`). |
| M3 loading | VERIFIED-FIXED (live part) | <ul><li>404 gives wiring only plus the notice, and hides the Model group.</li><li>`text/html` with 200 gives wiring only ("not a GLB (text/html)" in the console).</li><li>A truncated GLB and a `glTF`-garbage body both give 2D plus the model notice.</li><li>A hung request (`page.route` never answers) gives 2D after 21.3 s from navigation.</li><li>Progress streams 0→98 % from a slow server with Content-Length, and the badges and wiring show during the load (S2). Model buttons are disabled while loading.</li><li>No WebGL gives 2D plus the "no WebGL" notice; pressing 3D retries and falls back again.</li><li>Shots: `05-*`.</li></ul> |
| M4 placeholder anchors | VERIFIED-FIXED | <ul><li>Console: `car.glb: 3/19 loop nodes from anchors (side-brb-r, tsms, hvd), scale ×1, unknown: none`.</li><li>No anchor geometry is visible.</li></ul> |
| M5 model doc | PARTIAL | `car-model.md` has the right frame and axes, but its troubleshooting and part-anchor advice contradict the code, and the worked example doesn't match the table. See findings 4–6. |
| M7 status without colour | VERIFIED-FIXED | <ul><li>Greyscale, deuteranopia and protanopia, Iso and Side: the cause reads as "× 12 TSMS" by glyph and name (`02-cvd-*`).</li><li>No-data `?` and downstream `–` differ.</li><li>BMS latch open gives 12 "!" pips plus warn rings, matching the banner's 12 mismatched nodes exactly (`07-bms-open-mismatch-iso.png`).</li><li>Downstream wires are dashed.</li><li>The selected cause stays orange with an fg ring (`08-tsms-selected-zoom.png`).</li><li>The suspect badge is still 24 px tall (`h-6 text-sm`), not the 32 px the judge asked for. It is legible, so I'm not flagging it.</li></ul> |
| M8 badges stay attached | **NOT-FIXED** | <ul><li>Leaders exist, and there are no top-left ghosts.</li><li>But on round 1's 60-step, 240 px orbit, 17/19 loop nodes hop more than 20 px against the median in Iso (74–90 hops in total over 3 runs). Side: 11–14/19. Top: 14/19.</li><li>The acceptance bar was 0 hops for at least 17/19.</li><li>`s3c.js` shows these are real placement flips (the badge's offset from its own marker jumps more than 20 px), not parallax: 78 flips in Iso, 77 in Side.</li><li>Round 1 had 5 nodes hopping, 120 hops in total.</li><li>A vertical orbit gives 0 hops.</li><li>See finding 3.</li></ul> |
| M9 reduced motion | VERIFIED-FIXED | Badge motion after mouse release: 0.0 px with `reduce`, 113.7 px without. |
| M10 touch | PARTIAL (env limit) | <ul><li>At 390×844 (`isMobile`, `hasTouch`), computed `touch-action` is `pan-y` (set inline).</li><li>A CDP one-finger vertical swipe over the canvas scrolls the page (378→483) and leaves the camera unchanged. A horizontal one-finger swipe does nothing.</li><li>The hint reads "Two fingers to rotate and zoom. Pick a view to reset."</li><li>Real two-finger pinch could not be verified here. CDP `Input.dispatchTouchEvent` with two points gives the canvas only **one** pointer (`pointerdown#3` only), even with `touch-action:none` forced, so this is a headless limit, not the code.</li><li>Synthetic `PointerEvent`s with `pointerType:'touch'` (`s6f.js`) show the OrbitControls config works: one finger is a no-op, a pinch zooms (marker x-spread 135→379 px), and a two-finger drag rotates.</li><li>Still untested on a real device: how the browser arbitrates `pan-y` against a two-finger vertical drag.</li></ul> |
| S3/S4/S9/S10 (in lens) | done | <ul><li>Original / Solid / See-through, with visible "View" and "Model" labels.</li><li>Presets are momentary, with a visible focus ring (`08-toolbar-focus-ring.png`).</li><li>Wires and markers draw over the body in Solid and Original (`01-tsms-solid-iso.png`, `01-tsms-original-top.png`).</li><li>The notice is a callout.</li><li>At 1280×720 the strip ends at y=557, above the fold; the stage is 360 px.</li></ul> |

## New findings

### 1. major: on phones the 3D overview shows all 19 badges, not just the active one (contract §3.4 broken)
- **Where:**
  - `car-view-3d.component.ts:60` (`BADGE_BASE` contains `inline-flex`) and `:167` (`!this.interactive() && (active ? 'pointer-events-none' : 'hidden')`);
  - spec `car-view-3d.component.spec.ts:315-316`;
  - URL `/shutdown` at 390×844 with `argos.shutdown.carView=3d`.
- **Issue:**
  - `cx` only joins class lists; it doesn't merge them. So a hidden badge carries both `hidden` and `inline-flex`, and in the built CSS `inline-flex` wins: computed `display` is `inline-flex` (checked with a bare `<div class="hidden inline-flex">` on the page).
  - All 19 badges render, with no selection and with TSMS pinned alike.
  - Their leaders are suppressed (`!el.classList.contains('hidden')`), so displaced badges float with nothing tying them to a marker (badges 18 and 7 at the top of `06-phone-390-overview-no-selection.png`). The 346×238 canvas is covered.
  - The spec only asserts `classList` contains `hidden`, which jsdom passes.
- **Steps:**
  1. Open a 390-wide touch device and set 3D.
  2. Publish, then Break at TSMS.
  3. Optionally tap TSMS in the strip. Still 19 visible (`s6.js` output).
- **Fix:** don't render non-active badges when `!interactive()`, either by filtering `badges()` or with an `@if`. Or move the display utility out of `BADGE_BASE` so `hidden` has nothing to fight. Make the spec assert `getComputedStyle`-independent behaviour: the badge element is absent.
- **Evidence:** `06-phone-390-overview-no-selection.png`, `06-phone-390-overview-tsms-selected.png`, `06-phone-390-viewport.png`. This is also the phone screenshot the implementer couldn't take.

### 2. major: stale badge widths let neighbours cover the culprit's name and push it off the stage
- **Where:** `car-view-3d.component.ts:273-275` measures `badgeWidths` only when the map is empty. The map is cleared only by the `badgeEls()` effect (`:148-152`), which never fires on a state change, because `@for … track b.id` reuses the same elements.
- **Issue:**
  - When a loop node becomes suspect while 3D is open, its badge grows from "? 12" (about 36 px) to "× 12 TSMS" (92 px). `placeBadges` keeps using the old width for overlap and bounds.
  - The suspect also has no z-index, so later badges paint over it.
- **Measured** (`s2.js`, visible-badge rectangle intersections):
  - Break at TSMS, Iso: `glvms/tsms 9x23`.
  - Then Break at Acc sense, Iso: `side-brb-r/em-interlock 24x9, bspd-latch/acc-sense 12x21, can-latch/airs 3x8`; Side and Top have one each.
  - After a 2D→3D remount (widths re-measured): 0 overlaps in all presets.
- **Visible damage:**
  - "4 BMS" is cut off by badge 7 (`07-bms-open-mismatch-iso.png`).
  - "15 Acc" overlaps 6 (`03-acc-iso-after-switch.png`).
  - On the phone, "× 12 TSMS" is clipped at the stage's right edge (`06-phone-390-overview-no-selection.png`).
- **Fix:**
  - Re-measure whenever `badges()` changes: an effect on `badges()` that clears `badgeWidths`, or read `offsetWidth` per placement for suspects only.
  - Give suspect badges `z-[5]` (below the highlight's `z-10`).
  - Add a spec in which a node turns suspect after the first placement.

### 3. major: hysteresis doesn't hold: badges flip corners on nearly every node while orbiting (M8 NOT-FIXED)
- **Where:** `car-view-3d.projection.ts:236-250`.
- **Issue:**
  - The previous spot is kept only while its cost is exactly 0. Any overlap with an already-placed badge (they are placed in loop order) sends the search back to spot 0 and takes the first clear spot.
  - One badge moving cascades to every later badge. In dense Iso, at any moment about 9 of 19 badges are displaced with leaders (average 8.9, max 11).
- **Metric** (`s3c.js`, 4 px steps × 60, Break at TSMS), offset-from-own-marker jumps over 20 px:
  - Iso: 17/19 loop nodes, 78 flips (`airs` 15, `ts-plus` 12);
  - Side: 11/19, 77.
  - Round 1's median-relative metric gives the same picture (`s3.js`): Iso 17/19 and 13/19 on two runs, Side 14/19, Top 14/19.
- **Fix:**
  - Make leaving the previous spot cost something. When the previous spot overlaps, pick the minimum of `cost(i) + STICKY·(i≠prev)`, and only move if that saves more than a threshold, for example 30 % of the badge area.
  - Or place in the previous frame's order.
  - Re-run `s3c.js` as the acceptance test.
- **Evidence:** script output above; `04-orbit-*` frames are not needed.

### 4. minor: `car-model.md` troubleshooting and part-anchor advice contradict the code
- **Where:** `docs/spec/shutdown-loop-page/car-model.md:59-61, 76`; `car-model.ts:55-56, 75-78`.
- **Issue:**
  - For a part anchor (a mesh or group), `anchorPosition` uses the **bounding-box centre**, so the object's origin is never read.
    - "Set its origin to its geometry anyway" changes nothing.
    - The troubleshooting row "Every anchored marker at the rear axle → part anchors exported with their origin at the model origin" can't happen with this code.
  - The failure that *does* land a marker on the origin is an **empty** added with Add ▸ Empty while Blender's 3D cursor sits at the world origin, which is the default. The doc never says how to put the empty where the part is.
  - The console warning ("set its origin to its geometry") says the same wrong thing for an empty, which has no geometry.
- **Fix:**
  - Bullet: "Select the part, Shift+S ▸ Cursor to Selected, then Add ▸ Empty ▸ Plain Axes (it appears at the cursor); rename it (F2)."
  - Part anchors: "its bounding-box centre is used; nothing else to do."
  - Troubleshooting row: "an empty added at the 3D cursor and never moved."
  - Warning: "anchor X is at the model origin: was it moved to its part?"

### 5. minor: the doc's worked example doesn't round-trip to the table
- **Where:** `car-model.md:34-35` and `shutdown-loop.positions-3d.ts:39`.
- **Issue:** the doc says TSMS at Blender (−0.20, −0.66, 0.75) "is the table's `tsms: [-0.2, 0.75, 0.66]`". The table has `tsms: [-0.2, 0.75, 0.69]`, which is Blender Y −0.69. A CAD member checking the conversion against the file finds a 3 cm discrepancy and doubts the rule.
- **Fix:** use Y −0.69, or quote the table value as it is.

### 6. minor: the SolidWorks/Fusion route is too vague to follow, and CAD instance names are not accepted
- **Where:** `car-model.md:46-47, 62`; `ANCHOR_RE` at `car-view-3d.utils.ts:32`.
- **Issue:**
  - "Export STEP, import into Blender (an add-on, or via FreeCAD to OBJ/glTF)" names no add-on. Blender has no built-in STEP import, so this is where a CAD member stalls. The doc should name one concrete, tested route per tool, for example a mesh format the tool exports and Blender imports natively, or FreeCAD → glTF.
  - The doc doesn't say whether to name anchors in CAD or in Blender. CAD tools add instance suffixes, and the parser strips only Blender's `.001`. Checked with the regex:
    - `shutdown:tsms:1` parses to `tsms:1` and is reported unknown;
    - `shutdown:tsms<1>` parses to `tsms<1>`;
    - `shutdown-tsms:1` doesn't match at all.
  - Which suffixes each exporter actually keeps is unverified here.
- **Fix:**
  - State "add and name anchors in Blender, after import".
  - Optionally strip a trailing `:<n>` / `<n>` instance suffix as well as `.001`.
  - Note that a mesh route loses part names, so empties are the way.

### 7. minor: the loading progress and "No car model yet" notices are invisible to assistive tech
- **Where:** `car-view-3d.component.html:46-57`. Both `<p>` elements sit inside the stage `div role="img"`, whose children are presentational.
- **Issue:**
  - A screen reader never learns that the 3D view is wiring-only, or that a model is loading.
  - The fallback notice, by contrast, is a proper `role=status` in `car-view-mode`.
- **Fix:** move the two notices out of the `role=img` element (below the stage, or in the toolbar row) with `role="status"`. Or fold "no car model" into the stage's `aria-label`.

### 8. minor: at 1440 px in Iso, the 19 badges crowd the middle third and about 9 leaders cross the car
- **Where:** `01-tsms-see-through-iso.png`. The stage is 970×480; the car is about 520 px wide.
- **Issue:**
  - The badges for the E-box latches (4–7), the accumulator senses (15–19) and 12/1/2/3 sit in about a 330×250 px area. About 9 are displaced with thin leaders crossing each other.
  - It is readable when static. With finding 3, it churns while you orbit.
  - The camera still leaves large empty margins around the car, so there is room to spread out.
- **Fix:** fit Iso tighter to the model's bounds (S5). Re-measure clutter after findings 2 and 3 are fixed. No new mechanism is needed.

### 9. nit: disabled Model buttons look enabled while loading
- **Where:** `segmentedClasses.item` has no `disabled:` styles (`05-loading-progress.png`: Original and Solid look the same as when ready, with `cursor-pointer`).
- **Fix:** add `disabled:cursor-default disabled:opacity-50` locally.

### 10. nit: the Blender export path names a panel that doesn't exist, and "Apply All Transforms" can trip on CAD imports
- **Where:** `car-model.md:41-42`.
- **Issue:**
  - "+Y Up" is in the exporter's own **Transform** panel, not under "Include ▸ Transform".
  - Step 3 isn't needed for correctness, because the exporter writes object transforms and the view reads world matrices. CAD imports often share mesh data between instances, and Blender refuses to apply transforms to multi-user data.
- **Fix:** say "Transform ▸ +Y Up". Mark step 3 "optional; if Blender refuses with multi-user data, skip it".

### 11. nit: the doc orders export before anchors
- **Where:** `car-model.md`, sections "Exporting from Blender" and then "Placing loop nodes".
- **Issue:** following the doc top to bottom means exporting, then adding anchors, then exporting again.
- **Fix:** put "Placing loop nodes" between steps 3 and 4, or say "add anchors before step 4".

## CAD-team read of `car-model.md`

The frame table is correct: Blender (x, y, z) maps to glTF (x, z, −y), nose along −Y, driver's left along +X. The "Side view, nose left" check and the console line are good and easy to use.

Following the doc alone, a Blender user would export correctly. They would most likely fail at three points:
- getting from SolidWorks or Fusion into Blender at all (finding 6);
- placing empties, which land at the origin if the 3D cursor isn't moved first (finding 4);
- trusting the conversion, because the example disagrees with the table (finding 5).

None of the steps would put the car on its side. The round-1 axis error is fixed.

## Not verifiable here

- Real multi-touch gesture arbitration, as described in the M10 row.
- Under the heavy CPU load, absolute timings (21.3 s to fall back from a hung model) include page boot.
