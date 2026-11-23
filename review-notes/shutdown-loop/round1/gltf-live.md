# Round 1 review: throwaway-shutdown-3d-gltf (lens: live UX, visual quality, accessibility)

Tested live at http://localhost:4203/shutdown (Chromium + SwiftShader WebGL, deviceScaleFactor 1, dark theme). For stable scenarios the backend socket (:8000) was blocked in Playwright so the Calypso sim couldn't overwrite the dev mock panel (it does so every second otherwise). Scripts: `/tmp/claude-0/-home-user-Delphi/6e25b80b-05af-58e5-9050-4f2faa446aec/scratchpad/r1-gltf-live/s1.js` … `s10.js` (shared helpers in `lib.js`). Screenshots: `/home/user/Delphi/pictures/throwaway-shutdown-3d-gltf/review-r1/`.

Counts: 0 blocker, 9 major, 15 minor, 5 nit.

What works: the culprit badge is the only red thing in Ghost mode, so for normal colour vision it's findable within 2 s from Side, Top and Iso. Each fallback (404, corrupt GLB, HTML served as GLB, `--disable-webgl`) lands on 2D with the right notice. Badge aria-labels are good ("12. TSMS: Open — cause"). The page doesn't scroll sideways at 390 px. 20 fast 2D/3D toggles leaked no WebGL contexts. The model loads about 1.4 s after the loading text appears on localhost.

## Major

- **major: the culprit stands out only by colour (CVD / greyscale)**
  - Where: `car-view-3d.component.css` `.badge.state-suspect` (only change is `border-color: var(--color-fg)`); markers in `car-scene.ts` (MARKER_SIZE 3.5 cm, so the shapes from MARKER_SHAPES can't be told apart at normal zoom).
  - Issue: under simulated deuteranopia, protanopia and greyscale, badge 12 (TSMS, the cause) looks like the green closed badges around it. Only a 2 px light ring is left to tell it apart. The thick red wiring segment turns the same yellow as the closed wiring. The spec says "Status must not rely on colour alone", and roughly 1 in 12 men on the team will miss the culprit.
  - Steps: Publish, then Break at TSMS, Iso. Put an feColorMatrix filter on `<html>` (s7.js).
  - Fix: put the status glyph in the suspect badge (the × the strip and detail panel already use, e.g. "×12"). Make suspect badges larger (32 px) with a halo; it can pulse once on change, and not at all under reduced motion. Or show the cause as a name chip ("12 TSMS") instead of a bare number.
  - Screenshots: `10-cvd-deuteranopia-iso.png`, `10-cvd-protanopia-iso.png`, `10-cvd-greyscale-iso.png` (compare `03-tsms-ghost-iso.png`)

- **major: badges aren't visibly tied to their markers, and they hop while you orbit**
  - Where: `car-view-3d.utils.ts` `placeBadges` / `BADGE_OFFSETS`
  - Issue: there are no leader lines. In clusters (latches 4–7, accumulator senses 15–19, GLVMS/TSMS 1/12) a badge often sits nearer a neighbour's marker than its own. In Side view, badge "15" sits over the gap between markers 15 and 16. Placement is redone from scratch every frame, so badges jump to another corner on small camera moves. A slow 240 px orbit in 60 steps measured these hops of more than 20 px against the median motion: ts-plus 31, ts-minus 23, airs 23, tsip-sense 24, em-interlock 19. In `06-badge-hop-sequence.png`, badges 17 and 19 jump below the wire after a 3 px drag.
  - Steps: Side preset, drag the canvas slowly by a few px (s3.js, s3b.js).
  - Fix: draw a thin leader (an SVG line in the `.badges` overlay) from each marker to its badge. Add hysteresis: keep last frame's offset while it's still clear. Place the suspect(s) first so the cause never gets bumped. When markers are under about 24 px apart, collapse the cluster into one stacked badge ("15–19") that expands on hover or focus.
  - Screenshots: `06-badge-hop-sequence.png`, `03z-ghost-iso-zoom.png`, `03-tsms-ghost-top.png`

- **major: mismatch isn't shown in the 3D view at all**
  - Where: `car-view-3d.component.html` badge template (mismatch is only in `ariaLabel`); `car-scene.ts` `setStatuses` ignores `s.mismatch`.
  - Issue: with BMS latch open and everything after it reading closed, the banner lists 13 mismatched nodes. The 3D badges and markers look the same as plain downstream nodes. The spec says mismatch is "shown on that node", and one anti-goal is silently hiding contradictory data.
  - Steps: Publish, All closed, then toggle "BMS latch = 1" to 0 and wait 1.5 s (s9.js).
  - Fix: add a warn-coloured "!" pip at the badge's top-right plus a warn ring on the marker. Add "mismatch" to the hover text.
  - Screenshot: `12-bms-open-mismatch-iso.png`

- **major: the detail panel's live region chatters for screen readers**
  - Where: `car-view-3d.component.html` `<div class="detail" aria-live="polite">`
  - Issue: while a node is selected, "Updated: 0 s ago / 1 s ago" re-renders with every reading. I measured 12 DOM mutations in 6 s, alternating between those two texts. A polite live region announces each one, so a screen-reader user hears the age forever and other announcements get drowned out.
  - Steps: select TSMS with mock publishing on, then watch the `.detail` mutations (s4.js).
  - Fix: take `aria-live` off the panel. Announce only selection changes and state changes, in a separate visually-hidden status element ("12, TSMS, Open — cause"), and leave the age out.

- **major: the canvas traps page scroll on touch, and the hint is mouse-only**
  - Where: `car-view-3d.component.css` `canvas { touch-action: none }`; hint text in the template.
  - Issue: at 390x844 the canvas is 326x292 and almost full width. A one-finger swipe that starts on it orbits the car instead of scrolling, so trackside phone users have to aim for the 32 px gutters to reach the loop strip. The hint says "scroll to zoom, right-drag to pan", which you can't do on touch.
  - Steps: open on a phone and swipe up over the car. The CSS settles it; Playwright can't emulate the gesture faithfully.
  - Fix: on coarse pointers, use `touch-action: pan-y` and set OrbitControls `touches` so one finger scrolls and two fingers rotate or zoom. Alternatively, add a tap-to-interact overlay. Pick the hint copy with `(pointer: coarse)`.
  - Screenshot: `09-phone-390x844-fold.png`

- **major: the loading state is a blank box, with no timeout or progress**
  - Where: `car-view-3d.component.ts` `start()` (no timeout around `loadAsync`); template `.loading`, `.badges.pending { display:none }`.
  - Issue: while the GLB loads, the 520 px stage is empty except for "Loading car model…". No nodes show, and the Side/Top/Iso and CAD/Theme/Ghost buttons look live but do nothing. On localhost it takes about 1.5 s. A real export of "a few MB" on trackside Wi‑Fi will take much longer. If the request never completes, it stays like this forever: still loading after 20 s, with no fallback.
  - Steps: `page.route('**/car.glb', () => {})`, wait 20 s (s5.js).
  - Fix: show the 2D view, or at least the badges over an empty grid, until the scene is ready, then swap. Show progress from GLTFLoader's onProgress ("Loading car model… 40%"). Add a 15–20 s timeout that falls back with a notice. Disable the toolbar while loading.
  - Screenshots: `01-loading.png`, `08-hung-model-20s.png`

- **major: README's Blender steps would put the car on its side**
  - Where: `angular-client/src/assets/models/README.md`, "Exporting and replacing" step 1 and "Placing nodes"
  - Issue: it says to rotate in Blender "so the nose points along +X with Y up". Blender is Z‑up, and its glTF exporter's default "+Y Up" option converts Z‑up to Y‑up. Someone who sets Y up inside Blender gets a model rotated 90° in the viewer, and the viewer doesn't rotate models. "Turned 90° about Y" doesn't say which way; it is +90°, and the wrong sign points the nose backwards. "Move the origin to the ground under the rear axle" reads like Blender's Set Origin, which only moves the pivot and doesn't change exported vertex positions. "Read its location (after the export transform)" leaves the user to work out that table = (Bx, Bz, −By).
  - Fix: write the steps in Blender's own terms. Nose along +X, up +Z, driver's left along +Y. Move the whole model so the point on the ground under the rear axle centre is at the world origin, then Object, Apply, All Transforms. Export glTF Binary with "+Y Up" left on. For the table, use `[Blender X, Blender Z, −Blender Y]`. Add a SolidWorks or Fusion export note too, since the CAD team works there rather than in Blender. Include a one-line check: in Side view the nose points left.

- **major: an anchor that's a "tiny part" is placed at the part's origin, not where it sits**
  - Where: `car-scene.ts` constructor, `obj.getWorldPosition(...)` for anchors; README "In CAD" bullet.
  - Issue: the position is the node's origin. A part modelled in context in an assembly (common in SolidWorks), or imported with transforms baked in, has its origin at the assembly origin. Every such anchor then lands on the ground under the rear axle, the panel still says "Position: from the model", and no warning is logged. Separately, an anchor part with more than one material loads as a Group: the Group is hidden-as-anchor, but its child meshes stay visible and get repainted like body panels.
  - Fix: for Mesh or Group anchors, use the world bounding-box centre (`new Box3().setFromObject(obj).getCenter()`) and hide the whole subtree. In the README, recommend empties, and for parts say "set origin to geometry". Log a console warning when an anchor sits within about 1 cm of the model origin.

- **major: a model exported in inches is scaled wrong without warning**
  - Where: `car-view-3d.utils.ts` `unitScaleFor`; README "The viewer is forgiving…"
  - Issue: an FSAE car is about 115 in long. That's over 50, so it's taken as centimetres and scaled by 0.01, giving a 1.15 m car. The node table is in metres, so every node ends up about 2.5x too far out. US CAD defaults are often inches, and the README never mentions them.
  - Fix: treat a largest dimension of about 60–200 as inches (×0.0254); a car in cm measures 200–500. Log the scale chosen ("model looks like mm, scaled ×0.001"). Have the README say to export in metres or mm and that inches are guessed.

## Minor

- **minor: in Theme and CAD modes the markers and wiring disappear inside the body**
  - Where: `car-scene.ts` (markers and tubes are depth-tested against opaque materials)
  - Issue: with an opaque body, the markers and almost all the wiring are hidden, including the red cause segment. The badges float over a solid sidepod with nothing to point at. The placeholder's CAD colours are red (#c62828), so in CAD Top view the red cause badge sits on a red body and the red segment can't be seen. A real NER export may well be red too.
  - Fix: in opaque modes, draw markers and tubes on top (`depthTest:false` with an outline, or a second x-ray pass). Desaturate or darken CAD materials. Consider dropping Theme, since Ghost does the job better.
  - Screenshots: `03-tsms-theme-iso.png`, `03-tsms-theme-side.png`, `03-tsms-cad-top.png`, `03-tsms-cad-iso.png`

- **minor: the Iso preset frames the car small, with empty space above**
  - Where: `car-scene.ts` `setView` / `fitDistanceToPoints` (fits the bounding box's 8 corners)
  - Issue: in Iso, the box's corners stick out well past the car's silhouette. At 1280x720 the car is about 370 px wide in a 1208 px stage, and about 45% of the stage height is empty sky. On phones the car is tiny under 19 badges.
  - Fix: fit to the projected mesh vertices, or to a decimated sample of them, or to markers plus a tighter body box. Recentre on the projected bounds.
  - Screenshots: `09-laptop-1280x720-iso.png`, `03-tsms-ghost-iso.png`

- **minor: orbit, pan and zoom limits are too loose**
  - Where: `car-scene.ts` OrbitControls setup
  - Issue:
    - The camera can orbit under the ground grid; there's no `maxPolarAngle`.
    - Right-drag pans the car completely off the canvas, leaving 0 badges visible and no hint that a preset button resets the view.
    - The closest zoom (`radius*0.3`) puts the camera inside the wiring tubes.
    - The farthest zoom leaves a postage-stamp car under a blanket of badges.
  - Fix:
    - Set `maxPolarAngle ≈ 0.48π`.
    - Clamp `controls.target` to the model's bounds.
    - Set `minDistance` around `radius*0.8` and `maxDistance` around 2x the fit distance.
    - Add a "Reset" button, or say "click a view to reset" in the hint.
  - Screenshots: `04-orbit-under.png`, `05-pan-away.png`, `05-zoom-in-max.png`, `05-zoom-out-max.png`

- **minor: Tab goes through all 19 node buttons before reaching the view controls**
  - Where: `car-view-3d.component.html` (badges come before the toolbar in the DOM)
  - Issue: from the 3D/2D toggle, Side is the 21st Tab stop. The 19 stops repeat the loop strip, which is also focusable, and their DOM order is loop order, so focus jumps all over the car. It's tolerable, but slow.
  - Fix: use a roving tabindex: one Tab stop into the badges, arrow keys or Home/End move in loop order, and it starts on the cause. Put the toolbar before the stage in the DOM, or add a "Jump to cause" button.
  - Evidence: s4.js output

- **minor: badges are numbers only, with no name on hover**
  - Where: badge template
  - Issue: the spec says hover or focus on a marker shows name, topic, value and age. In 3D, hovering shows nothing; you have to click and then read the panel below. To identify a number you have to look it up in the loop strip.
  - Fix: add a hover/focus tooltip with the label and state; a `title` would do at minimum. Always label the cause badge with its name.

- **minor: preset buttons show no state, and the toolbar groups have no visible labels**
  - Where: toolbar template
  - Issue: Side/Top/Iso have no `aria-pressed` and no visual active state. In the screenshots the only bold text is the hover. "CAD / Theme / Ghost" carries no visible label ("Model colours" is only in `aria-label`), and "CAD" means little to a trackside user.
  - Fix: add small visible labels ("View", "Model"). Mark the preset as pressed until the user orbits. Consider names like "Original / Solid / See-through".
  - Screenshot: `03-tsms-ghost-side.png`

- **minor: the colour mode and camera preset aren't remembered**
  - Where: `car-view-3d.component.ts` (`materialMode`, `view` signals); compare `readViewMode`/`writeViewMode`
  - Issue: the 2D/3D choice persists. Theme mode and the Top view reset to Ghost and Iso on reload and on every 2D→3D switch, and the GLB is fetched again (s8.js).
  - Fix: persist both with the same try/catch storage helper.

- **minor: the fallback notice is easy to miss and contradicts the toggle**
  - Where: template `.notice`, `FALLBACK_NOTICES`
  - Issue: it's plain body text with no icon and no warn styling, while the segmented control still shows **3D** pressed over a 2D drawing. The WebGL message says "which this browser has turned off", but the cause may be a GPU blocklist or lack of support. The model message names a file path that a trackside user can't act on.
  - Fix: style it as a callout with a warn icon. Show the 3D toggle as unavailable (disabled, with the reason as its description). Reword: "3D view unavailable (no WebGL), showing 2D." Keep the path for the console.
  - Screenshots: `08-fallback-404.png`, `08-fallback-disable-webgl.png`, `08-fallback-corrupt.png`

- **minor: selecting a node shifts the layout, and the loop strip is below the fold on laptops**
  - Where: `.detail`, `.stage` height `clamp(280px, 75vw, min(60vh, 520px))`
  - Issue: selecting a node grows the panel from 1 to 6 lines, which pushes the loop strip down; deselecting pulls it back up. At 1280x720 the 432 px stage pushes the loop strip, which the spec calls "the main diagnostic read", off screen.
  - Fix: reserve the panel's height, or float it inside the stage's corner. Cap the stage at about 50vh on short viewports.
  - Screenshots: `07-keyboard-tsms-selected.png`, `09-laptop-1280x720-fold.png`

- **minor: a selected marker turns white and loses its state colour**
  - Where: `car-scene.ts` `applySelection` (emissive set to `theme.selection`)
  - Issue: selecting the cause makes its red octahedron glow white.
  - Fix: show selection with a separate ring or halo mesh, or by scale alone, and keep the state colour.
  - Screenshot: `07-keyboard-tsms-selected.png`

- **minor: on phones the badges cover the car**
  - Where: `placeBadges` on narrow stages
  - Issue: at 326 px wide, 19 badges of 24 px cover most of the car, and fanning pushes some about 50 px from their markers (7, 8, 13).
  - Fix: below about 480 px, show badges only for suspect, mismatch and no-data nodes and leave closed ones as markers. Or collapse clusters. Default to the Side preset on phones.
  - Screenshots: `09-phone-390x844-iso.png`, `09-phone-390x844-side.png`, `09-phone-390x844-top.png`

- **minor: the wiring runs as straight lines through the car**
  - Where: `loopSegments` / `setStatuses`
  - Issue: segments go straight from node to node in series order. MC HVIL (rear) to BOTS (nose) cuts the whole length of the car through the cockpit. The two side BRBs overlap in Side view. On a physical model this reads as harness routing, which it isn't.
  - Fix: make closed segments thinner or translucent so the cause stretch dominates. Optionally support waypoint anchors (`shutdown-wire:<from>-<to>.<n>`) to route along the chassis.
  - Screenshots: `03-tsms-ghost-side.png`, `03-tsms-ghost-iso.png`

- **minor: with the placeholder model, 3D shouldn't be the default**
  - Where: `readViewMode` (defaults to `'3d'`)
  - Issue: the 2D fallback uses a real frame render, larger markers and no fanning, and it answers "where is the break" faster than the rough GLB. The placeholder reads as an open-wheel FSAE car in Theme/CAD (wings, wheels, hoops, sidepods), but in Ghost it's a vague grey cloud.
  - Fix: default to 2D until a real export lands, or make the default depend on whether the model is a placeholder (e.g. a `placeholder` flag in the glTF `extras`).
  - Screenshots: `08-fallback-404.png` vs `03-tsms-ghost-iso.png`

- **minor: no-data and downstream look almost the same**
  - Where: `shutdown-states.css` (`--sd-downstream #8a8a8a`, `--sd-no-data #8b93a1`), which the badges inherit
  - Issue: the two greys are nearly identical, so only the dashed border separates "open because of upstream" from "no data". When one board is stale and the other is downstream, the badges sit side by side and look the same.
  - Fix: give no-data a distinct treatment, such as a "?" glyph in the badge, a hatched or hollow fill, or a bluer hue.

- **minor: the README gives no way to check placement in the viewer**
  - Where: README, "Placing nodes"
  - Issue: a CAD person can't easily confirm their anchors worked. The only signs are a console warning for unknown ids and a per-node "Position: from the model" line you have to click through 19 times. Nothing reports the unit scale applied. The README also doesn't say a production deploy needs a rebuild, or warn about cached GLBs.
  - Fix: log a summary on load ("car.glb: 12/19 nodes from anchors, scale ×0.001, unknown: shutdown_tsm"). Add a dev-only `?debug3d` overlay with node names and axes. Add a short "Check it" section with the expected Side-view look, and a "Troubleshooting" table: car on its side means axes, nodes outside the car means units or origin, everything at the rear axle means anchor origins.

## Nit

- **nit: orbit damping ignores reduced motion**
  - Where: `car-scene.ts` `enableDamping = true`
  - Issue: with `prefers-reduced-motion: reduce`, the view keeps drifting after you release the mouse (badges moved 16 px after release, s10.js).
  - Fix: `controls.enableDamping = !matchMedia('(prefers-reduced-motion: reduce)').matches`.

- **nit: Ghost mode looks mottled**
  - Where: ghost material (`transparent`, `depthWrite:false`, DoubleSide, no sorting)
  - Issue: overlapping translucent panels show streaky bands, and the silhouette is soft.
  - Fix: add `EdgesGeometry` line overlays (theme muted colour, around 30° threshold) in Ghost mode for a crisp outline.
  - Screenshot: `03-tsms-ghost-side.png`

- **nit: the dev console is flooded by an unrelated error**
  - Where: the nav bar's `MessagesPerSecondComponent`, which this branch doesn't touch
  - Issue: `NG0100 ExpressionChangedAfterItHasBeenChecked` fires many times per minute in dev and buries the 3D view's own warnings about anchors and missing positions.
  - Fix: separate ticket.

- **nit: resizing doesn't refit the camera**
  - Where: `resize()`
  - Issue: rotating a phone to landscape keeps the old distance, so the car can end up small or cropped.
  - Fix: if the user hasn't orbited since the last preset, re-run `setView(currentPreset)` on resize.
  - Screenshot: `13-resize-landscape-phone.png`

- **nit: there's no keyboard orbit or zoom**
  - Where: OrbitControls
  - Issue: the presets cover the basic need, but fine adjustment is mouse-only.
  - Fix: `controls.listenToKeyEvents(stage)` while the stage has focus, with the keys explained in the hint.
