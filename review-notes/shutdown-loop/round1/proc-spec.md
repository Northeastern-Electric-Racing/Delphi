# Review round 1: throwaway-shutdown-3d-procedural (conventions, architecture, integration)

Branch: `throwaway-shutdown-3d-procedural` (3 commits on `origin/shutdown-loop-page`, PR #1025 base).
Paths below are relative to `angular-client/src/pages/shutdown-page/` unless stated.

## What I checked

- I built a `git archive HEAD` copy of each 3D branch in the scratchpad, using the worktree's `node_modules`. The worktrees were not touched.
- **Production builds:**
  - procedural: initial bundle 777.78 kB. It adds a lazy `car-scene` chunk of 605.90 kB raw (125.09 kB transfer); the `shutdown-page-component` chunk is 35.50 kB.
  - glTF: initial bundle 777.54 kB. Its `car-scene` chunk is 663.91 kB raw (138.05 kB transfer), and it also ships `assets/models/car.glb` (166.5 kB) and `assets/draco/` (763 kB: decoder js, wasm and wrapper).
  - Neither build gave a budget warning. `car-view-3d.component.css` is 2237 B as source, but it falls under the 2 kB `anyComponentStyle` warning once minified.
- **Tests and lint:**
  - `ng test --include 'src/pages/shutdown-page/**'`: procedural 11 files and 90 tests pass; glTF 11 files and 110 tests pass.
  - `eslint src/pages/shutdown-page` and `prettier --check` are clean on procedural.
- **Lockfile and versions:** the lockfile diffs of the two 3D branches are byte-identical: `three` and `@types/three` at 0.187.0, plus `@dimforge/rapier3d-compat`, `@tweenjs/tween.js`, `@types/stats.js`, `@types/webxr` and `meshoptimizer` as transitive dependencies.
- **Angular setup:** the app runs Angular 22.2.3 with no `zone.js` in `package.json` or `main.ts`, so it is zoneless.
- **Screenshots:** I read `pictures/throwaway-shutdown-3d-*/` (iso view with the break at TSMS, phone at 390 px).

## Findings

- **blocker (once merged with throwaway-shutdown-ui)**: `components/car-view-3d/car-view-3d.component.ts:43`, `:68`, `:79`, `:175-185`; `car-view-3d.component.html:24,55,68-72`; `car-view-3d.component.css:62,74,113-120`; `car-view-3d.model.ts:76,93`
  - **Issue:** the 3D view depends on three things the UI branch deletes:
    - `styleUrls: ['../../shutdown-states.css', …]`
    - `NODE_STATE_DISPLAY[state].cssClass`
    - `--sd-color`, read through hidden probe spans
  - **Why:** throwaway-shutdown-ui deletes `shutdown-states.css` and replaces `cssClass` with Tailwind class lists (`text`, `marker.measured/unmeasured`, `stroke`, `dash`). A merge with that branch therefore fails to compile. The glTF branch has the same dependency (`car-view-3d.component.ts:81,114,250`).
  - **Fix:**
    - Add a token per state to `shutdown-loop.display.ts` in the UI branch, e.g. `STATE_COLOR_TOKEN: Record<NodeState, string> = { closed: '--color-success', suspect: '--color-danger', 'downstream-open': '--color-fg-dim', 'no-data': '--color-fg-muted' }`. These are the same tokens as its `stroke-*` utilities.
    - Read the tokens off `document.documentElement`. `theme.css` uses `@theme static`, so every token is emitted.
    - Delete the probes, `--sd-color` and the `shutdown-states.css` import.

- **major**: `components/car-view-3d/car-view-3d.component.ts:57,96-130`, `.html:20-66`
  - **Issue:** the view owns selection (`selectedId` signal), its own info overlay (`nodeInfo`) and a 19-button roving toolbar.
  - **Why:**
    - The UI branch's `ShutdownSelectionStore` contract says "A view never owns selection". It expects inputs `nodes`/`selectedId`/`previewId` and outputs `nodeSelect`/`nodePreview`.
    - The UI branch already has an accessible keyboard path (`loop-strip` with `rovingIndex`) and a detail panel (`node-detail`, `formatAge`/`formatValue`), so the toolbar, `onToolbarKey`/`tabStop` and `nodeInfo` repeat them.
    - Picking a node in 3D would not highlight the strip or the detail panel.
  - **Fix:**
    - Adopt the contract: `selectedId = input<string|null>(null)`, `previewId = input<string|null>(null)`, `nodeSelect = output<string|null>()`, `nodePreview = output<string|null>()`.
    - Have the scene highlight `previewId ?? selectedId`. Canvas pick emits `nodeSelect`; hover hit-test changes (car-scene.ts `onMove` already raycasts) emit `nodePreview`; Escape emits `nodeSelect(null)`.
    - Delete the toolbar, the info overlay and `nodeInfo` (about 60 lines of TS, 50 of HTML and 70 of CSS).

- **major**: `docs/spec/shutdown-loop-page/spec.md` (unchanged), `angular-client/package.json:42,50`
  - **Issue:** a 3D view and a new runtime dependency (three, a 126 kB-transfer lazy chunk) arrive with no spec change and no ADR.
  - **Why:**
    - The spec chose "A. Own simplified SVG car side view" and rejected "C. Photo/render" because it "ignores light/dark theme, redo when car changes".
    - CLAUDE.md asks for reasoning before architectural changes, and ADRs record decisions.
    - The procedural approach answers C's objections (it reads theme tokens and is rebuilt from code). glTF only partly answers them: it needs a re-export when the car changes, though its "Theme" and "Ghost" modes cover the theme concern.
  - **Fix:**
    - Amend the spec: add a "3D car view" option and record that the 2D SVG stays as the fallback.
    - Draft `docs/adr/0010-angular-client-three-js-3d-car-view.md`. 0009 is taken by throwaway-shutdown-logic-scylla. It should cover:
      - three as a lazy-only dependency;
      - an exact pin (three has no semver: every r-release may break, and `@types/three` must match);
      - the car-source decision (see "Recommended merge strategy").
    - It does not conflict with ADR 0007: three is a renderer, not a UI kit, and adds no CSS.

- **major**: `components/car-view-3d/car-scene.ts:232-237,251` (doc comment at `:68-70`)
  - **Issue:** `pulse()` returns true whenever any node is `suspect`, so `tick` asks for a new frame every vsync for as long as the loop is open.
  - **Why:**
    - The doc comment says it "never [renders] in an idle loop".
    - An open loop is the normal state while diagnosing a fault, and the sim shows "near-constant breaks" (spec). The result is 60 fps of WebGL with the GPU and battery busy on a trackside laptop, even with the canvas scrolled off-screen.
  - **Fix:** any one of these:
    - Pulse at a low rate (render about 10 fps with a `setTimeout` gate).
    - Pause with an `IntersectionObserver` and on `document.hidden`.
    - Drop the pulse: the octahedron shape and the danger colour already mark the cause, and the glTF branch has no pulse.

- **major**: `shutdown-loop.positions-3d.ts:1-45`, `car-view-3d.model.ts:18-23`, `car-model.ts:31-56`
  - **Issue:** the positions use a frame private to the procedural car (x aft of the front bulkhead, nose towards -x, +z = left). The camera presets (`CAMERA_PRESETS`) and `CAR_EXTENT_3D` are hand-typed numbers that only fit this car. `CAR_EXTENT_3D` duplicates the `P`/`WHEEL_R`/axle constants in `car-model.ts` and is used only by the spec.
  - **Why:**
    - The glTF branch uses the CAD/model frame instead: +X forward, +Y up, +Z to the driver's right, origin on the ground under the rear axle (README).
    - Its positions table has the same keys and different numbers. Converted with x' = 2.15 - x and z' = -z, the two tables disagree by 0.09–0.37 m per node; most of that is an x offset of about 0.2 m from the two cars' proportions.
    - `em-interlock` sits on opposite sides of the car in the two tables (procedural left, z = +0.12; glTF right, Z = +0.18).
    - A real CAD model would not fit the procedural presets.
  - **Fix:**
    - Use one table in the CAD frame (keep glTF's `Vec3` tuples and `NODE_ANCHOR_PREFIX`). Put the procedural car into that frame by wrapping `buildCar`'s group (`rotation.y = Math.PI`, `position.x = REAR_AXLE_X`).
    - Replace `CAMERA_PRESETS` with glTF's `VIEW_DIRECTIONS` and `fitDistanceToPoints`, which are pure and tested.
    - Derive the extent check from the scene bounds (or delete it).
    - Ask the electrical lead which side the EM interlock is on.

- **major**: `components/car-view-3d/car-view-3d.component.css:33-56` (`.btn`, `.close`, `.node`) and `.html:17-19`
  - **Issue:** the preset, close and node buttons are hand-styled in a component stylesheet. Meanwhile the 2D/3D switcher in the same branch uses `segmentedClasses`. The page ends up with two different segmented-control looks stacked in one corner (the screenshot shows the 3D/2D pill above Iso/Side/Top bordered buttons).
  - **Why:**
    - CONTEXT.md says "A look used in more than one place is a recipe in `src/ui/recipes/`".
    - A stylesheet-only component is allowed (all CSS, no utilities), but the UI branch turns every shutdown component into utilities-only. This would be the last stylesheet on the page.
  - **Fix:**
    - Remove the stylesheet.
    - Presets get `segmentedClasses` (`list`/`item`, `aria-pressed` on the active view, which also fixes the missing pressed state on the presets) and close gets the button recipe.
    - Stage and overlay layout become utilities.
    - With the toolbar and info panel gone (finding 2), only about 10 classes remain.

- **minor**: `components/car-view-3d/car-scene.ts:124-133,168-172,327-349`
  - **Issue:** node numbers are canvas sprites sized in world units. They overlap when nodes cluster (15–19 in the accumulator: "1", "19" are cut off in `car-3d-break-at-tsms-iso.png`) and become about 6 px tall at 390 px wide (`car-3d-phone-390.png`).
  - **Why:** the labels are unreadable, and canvas text gets no AXE contrast or zoom.
  - **Fix:** use glTF's HTML badge overlay with `placeBadges` (declutter, unit-tested). Make the badges `aria-hidden`, `pointer-events-none` spans styled with the UI branch's `NODE_STATE_DISPLAY[state].marker.*` classes, so they match the 2D markers and the strip. Picking goes through the canvas.

- **minor**: `components/car-view-3d/car-view-3d.model.ts:171-186`
  - **Issue:** the `DEFAULT_SCENE_COLORS.states` hex values (`#2fd35a`, `#ff4d4d`, …) are off-palette. The suspect colour is red, while the theme says "NER red is the accent, so danger takes orange" (`--color-danger: #fb923c`).
  - **Why:** these values are inherited from the base branch's `shutdown-states.css`. The UI branch moves to tokens, so the 3D cause marker would be red next to an orange 2D, strip and banner.
  - **Fix:** fall back to the token values (`#4ade80`, `#fb923c`, `#8a8a8a`, `#a3a3a3`), or drop the fallback and read tokens only (see the blocker).

- **minor**: `components/car-view-3d/car-view-3d.component.ts:135-138`
  - **Issue:** `start()` returns early when `canvas` or `stage` is missing, which leaves `mode` at `'loading'` for good.
  - **Why:** the view hangs on "Loading 3D view…".
  - **Fix:** call `fallBack()` instead, as glTF does with `fallBack('init')`. Also give a reason for the fallback text, as glTF's `FALLBACK_NOTICES` do.

- **minor**: `components/car-view-switcher/car-view-switcher.component.ts:15`
  - **Issue:** 3D is the default on a first visit.
  - **Why:**
    - The spec's primary view is the 2D SVG, and the UI branch audited it for AA at 390 and 1440 px.
    - 3D costs 125 kB transfer plus a GPU context on every visit to the page, and it still needs the selection wiring.
  - **Fix:** this is a product call. Either default to `'2d'`, or default to 3D only when `matchMedia('(min-width: 1024px)')` matches. State the choice in the ADR.

- **minor**: `components/car-view-3d/car-view-3d.component.css:14` and OrbitControls (`three/examples/jsm/controls/OrbitControls.js:507`; glTF css `:20`)
  - **Issue:** with `touch-action: none` on a canvas that takes up most of a phone screen, a swipe over the car can't scroll the page.
  - **Why:** it is a scroll trap on phones; both branches have it.
  - **Fix:** below `md`, leave the canvas inert until the user taps it (an "Interact" toggle), or orbit with two fingers only (`controls.touches.ONE = null`).

- **minor**: naming. `car-model.ts` (three.js geometry) and `car-view-3d.model.ts` (pure logic, the scene contract, colours and WebGL detection)
  - **Issue:** in this folder `*.model.ts` already means domain constants (`shutdown-loop.model.ts`), and pure helpers are `*.utils.ts`.
  - **Fix:** rename `car-model.ts` to `procedural-car.ts` and `car-view-3d.model.ts` to `car-view-3d.utils.ts`, and move the interfaces into `car-scene.types.ts`. This is the glTF layout.

- **nit**: `car-view-3d.model.ts:42,51,76,93`
  - **Issue:** `cssClass` on `LoopSegment3d` and `Marker3d` is never read by `car-scene.ts`, so it is dead.
  - **Fix:** remove it.

- **nit**: `car-view-3d.component.ts:11,49,86,90,99,151`
  - **Issue:** `NgZone.runOutsideAngular` does nothing in this zoneless app (no zone.js). The glTF branch has the same calls.
  - **Fix:** remove them.

- **nit**: `car-scene.ts:342`
  - **Issue:** the badge font is hard-coded as `Roboto, sans-serif`.
  - **Fix:** read `--font-sans`, or drop it if you move to HTML badges.

- **nit**: `car-view-3d.component.css:40`
  - **Issue:** `var(--radius-sm, 4px)` has a fallback that disagrees with the token (6px).
  - **Fix:** drop the fallback.

- **nit**: `car-view-3d.tokens.ts:13`
  - **Issue:** `WEBGL_SUPPORT` uses the global `document`.
  - **Fix:** use `inject(DOCUMENT)` as glTF does.
  - The tokens are not overkill: two root-provided tokens are the least intrusive way to keep three out of jsdom. Keeping them in their own file, as here, is better than glTF's component-file tokens, because the switcher spec imports them without pulling the component in.

- **nit**: `car-scene.ts:31` uses `three/addons/controls/OrbitControls.js`, while glTF uses `three/examples/jsm/...`. Both resolve, since `package.json` exports `./addons/*`. Standardize on `three/addons/`.

- **positive**:
  - three and `@types/three` are pinned exactly and kept in lockstep. That is right for three, so keep it.
  - three only loads in the lazy chunk; the initial bundle didn't grow.
  - The context-lost fallback, disposal (`forceContextLoss`) and destroy-during-load guard are correct.
  - `sceneSignature` stops the scene rebuilding when only ages tick. glTF mutates and re-renders on every status tick.
  - The storage key `argos.shutdown.carView` follows `argos.graphPresets`.
  - Storage failures are handled and have tests.

## Procedural vs glTF comparison

| | Procedural (this branch) | glTF (throwaway-shutdown-3d-gltf) |
|---|---|---|
| Code (non-spec lines added, excluding lockfile) | 1378 (`car-model` 267, `car-scene` 366, `model` 223, component 188+72+133, tokens 14, switcher 64, positions 45) | 1619, of which 278 are the placeholder generator script and README; about 1341 of app code (`car-scene` 360, `utils` 347, types 47, component 267+85+138, switch 45, positions 44) |
| Binary or asset weight | none | `car.glb` 166.5 kB in git and dist; Draco decoder 763 kB copied into dist (fetched only for a Draco model); `README.md` shipped into `dist/assets/models` (minor: move it out of `src/assets`) |
| Lazy chunk | 605.9 kB raw / 125.1 kB transfer | 663.9 kB raw / 138.1 kB transfer, plus the model fetch |
| Time to first frame | geometry built in memory, no network | waits on the GLB fetch (a real CAD export could be several MB) and, when used, the Draco wasm |
| Steady-state rendering | on demand, except 60 fps while a node is suspect (pulse) | on demand; projects 19 points and runs 19 `querySelector` calls plus style writes per frame while orbiting; re-renders on every status tick |
| Visual fidelity today | a recognisable FSAE space frame: hoops, braces, wheels, see-through accumulator, E-box and MC; theme colours by construction | the placeholder GLB is a vaguer body shell (ghost by default); fidelity is unbounded once the real CAD lands |
| Fidelity later | capped: the car must be re-modelled in code each season (`P`, `SIDE_TUBES`, box extents) | the CAD team re-exports; "CAD/Theme/Ghost" modes deal with clashing CAD colours |
| Keeping node positions accurate | hand-edit `NODE_POSITIONS_3D` in a private frame, and the procedural geometry as well | `shutdown:<id>` empties in the CAD file override the table (`resolveNodePositions`); the detail panel says "from the model" or "from the position table"; tolerant names (`shutdown_side_brb_r`, `.001`); mm/cm auto-scale |
| Camera framing | hard-coded presets for this car | `fitDistanceToPoints` fits any model to the canvas (tested) |
| Labels | canvas sprites; overlap, unreadable on phone; separate 19-button toolbar | HTML badges with a declutter step (`placeBadges`); focusable over the canvas |
| Picking | raycast on invisible spheres (three-bound, not unit-testable) | screen-space `nearestPoint` (pure, tested) |
| Loop "no current" style | dashed tubes (`dashPieces`), close to the 2D view's dash language | tube thickness (strong/normal/muted) |
| Tests (it blocks added) | 40 (`model` 17, component 11, switcher 7, positions 6); scene and car not testable | 60 (`utils` 41, component 12, switch 3, positions 5); scene not testable |
| Failure modes covered | no WebGL, chunk load failure, context lost | no WebGL, chunk load failure, model missing or corrupt, init; reason-specific notices (no context-lost handler: add it) |

**Verdict:**
- Procedural is better as the default/fallback car today: there is no asset pipeline, it is theme-native, it renders quickly, and it looks more like a car than the placeholder GLB.
- glTF has the better architecture for the long term and for node accuracy: anchors in CAD, auto-fit, pure picking and decluttering, more tests.
- Neither should ship its placeholder: the procedural car makes `car.glb` and its generator redundant.

## Integration conflicts

1. **throwaway-shutdown-ui:**
   - `shutdown-states.css`, `cssClass` and `--sd-color` are deleted, which breaks the build (blocker above). Both 3D branches are affected.
   - `shutdown-page.component.html` is rewritten as a grid with `<car-view [selectedId] [previewId] (nodeSelect) (nodePreview)>` inside `section[aria-label="Car side view"]`. Both 3D branches' four-line edit of the old template conflicts textually. Re-apply it by hand, and rename the section label to "Car view".
   - Selection contract: both 3D views own selection, and both 2D fallbacks (`<car-view [nodes]>`) drop the UI's selection bindings.
   - Detail UI is duplicated: `nodeInfo` (procedural) and `nodeDetail` (glTF) against `node-detail`, `formatAge` and `formatValue` (UI).
   - Colours: the off-token red cause against the UI's orange `danger`.
2. **throwaway-shutdown-3d-gltf:**
   - Same file paths with different content: `car-view-3d.component.{ts,html,css,spec.ts}`, `car-scene.ts` and `shutdown-loop.positions-3d{,.spec}.ts`.
   - Different coordinate frames (above).
   - Both define `CAR_SCENE_LOADER` and `WEBGL_SUPPORT` (in the tokens file here, in the component file there), `isWebGLAvailable`, `ViewPreset`, the marker shape table, `CLICK_SLOP`, and two switchers (`car-view-switcher`, selector `car-view-switcher`, against `car-view-switch`) with two storage keys (`argos.shutdown.carView`, `shutdown-car-view`).
   - `package.json` and `package-lock.json` are identical, so they merge cleanly.
3. **throwaway-shutdown-logic-scylla:**
   - No conflict. Both 3D views read only `NodeStatus` fields (`node`, `state`, `value`, `ageMs`, `mismatch`), which that branch leaves alone.
   - Its `computeLoopStatus(nodes, readings, now)` signature and the new `LoopStatus.source` aren't used by the 3D code.
   - Its ADR is numbered 0009, so the 3D ADR is 0010.

## Recommended merge strategy

Land order: base PR #1025, then throwaway-shutdown-ui (tokens and the selection store), then a single 3D branch built from both 3D branches, then logic-scylla, which is independent and can go in any order. Make the combined 3D work a fresh `throwaway-shutdown-3d` branch (or a ticket branch) from the UI branch, and bring files in by hand rather than merging either 3D branch.

**One `car-view-3d` with a pluggable car source:**

```ts
// car-scene.types.ts  (from gltf, extended)
export interface CarSource { load(): Promise<{ object: Object3D; anchors: NodeAnchor[]; kind: 'procedural' | 'gltf' }> }
```

The chain is glTF when `assets/models/car.glb` loads (or when a `MODEL_URL` token or environment flag is set), else procedural, else the 2D view. There is no placeholder GLB until the real CAD exists. The fallback notice says which car is shown.

**Keep from the glTF branch:**
- `car-scene.types.ts`, extended with `CarSource`.
- From `car-view-3d.utils.ts` and its spec: `parseNodeAnchorName`, `resolveNodePositions`, `unitScaleFor`, `fitDistanceToPoints`, `VIEW_DIRECTIONS`, `placeBadges`, `nearestPoint`, `CarSceneError`, `FallbackReason` and `FALLBACK_NOTICES`.
- Drop `resolveStateColours` (it reads the probe), `readViewMode`/`writeViewMode` (procedural's are kept instead) and `nodeDetail` (the UI's `node-detail` replaces it).
- The `ThreeCarScene` class in `car-scene.ts`: mutate-in-place markers and segments, material modes, auto-fit, screen-space pick, `onFrame` projection. Split its GLTFLoader and Draco code into `gltf-car.ts` (a `CarSource`).
- `src/assets/models/README.md`. Move it to `angular-client/docs/` or `scripts/` so it doesn't ship.
- The `shutdown-loop.positions-3d.ts` frame, `Vec3` and `NODE_ANCHOR_PREFIX`.
- The component's badge overlay and phase/notice handling, rewritten as utilities.
- Draco: defer the `angular.json` asset copy until a real model needs it (YAGNI), or keep it and record the choice in the ADR.

**Keep from the procedural branch:**
- `car-model.ts`, renamed `procedural-car.ts`, as a `CarSource` with its group put into the CAD frame (`rotation.y = π`, `position.x = 2.15`).
- `dashPieces` and the dashed "no current" segments, which match the 2D/strip dash language, plus their spec cases. Combine them with glTF's emphasis for the cause.
- `sceneSignature`, to skip work when only ages change.
- `car-view-3d.tokens.ts` (both tokens, with `inject(DOCUMENT)`).
- The webglcontextlost to 2D fallback (glTF lacks it) and the destroy-during-load guard.
- `readCarViewMode`/`writeCarViewMode` and the storage key `argos.shutdown.carView`, with their tests.
- The positions-spec checks for no duplicates and both sides. Express them in the CAD frame; for the numbers, start from procedural's converted with x' = 2.15 - x and z' = -z, and confirm `em-interlock`.

**Take from the UI branch, as is:**
- The `ShutdownSelectionStore` contract on `car-view-3d`: inputs `nodes`/`selectedId`/`previewId`, outputs `nodeSelect`/`nodePreview`.
- A token per state from `shutdown-loop.display.ts` for scene colours, and the `marker.*` class lists for the HTML badges.
- `node-detail` for details and `loop-strip` for keyboard navigation.

**Drop:**
- Procedural's info overlay, node toolbar, `CAMERA_PRESETS`, `CAR_EXTENT_3D`, canvas sprite labels, ring sprite (use glTF's emissive and scale highlight), pulse, raycast picking and `car-view-3d.component.css`.
- glTF's `car.glb`, `generate-placeholder-car.mjs`, `car-view-switch` and the `shutdown-car-view` key.

**Single switcher:**
- Put a segmented 2D/3D control (`segmentedClasses`) in the page's car section header. The simplest shape is a tiny `car-view-mode` component with `mode = model<CarViewMode>()` plus procedural's storage helpers.
- The page then renders `@if (mode() === '3d') <car-view-3d …contract… /> @else <car-view …contract… />`, so the contract bindings aren't forwarded through a wrapper.
- Decide the default view (2D, or 3D on wide screens) in the ADR.

**Docs:** amend the spec with a 3D option and add ADR `0010-angular-client-three-js-3d-car-view.md`. It covers:
- the lazy three dependency and the exact pin;
- the car-source chain;
- the CAD anchor convention;
- the 2D view as the accessible primary or fallback.
