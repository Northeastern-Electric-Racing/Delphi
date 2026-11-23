# Round 1 — CORRECTNESS & PERFORMANCE — `throwaway-shutdown-3d-gltf` (PR #1025 base `origin/shutdown-loop-page`)

Paths are relative to `angular-client/src/pages/shutdown-page/components/car-view-3d/` unless given in full.
Evidence comes from: (a) the live client on :4203 (Playwright, SwiftShader WebGL); (b) a harness that bundles the real
`car-scene.ts` with esbuild (`scratchpad/r1-gltf-correctness/www/harness.js`), so the private scene state can be inspected;
(c) test GLBs made with gltf-transform (`scratchpad/r1-gltf-correctness/gen.mjs`): m / cm / mm / Draco-mm models with nested,
scaled, duplicated and mesh anchors, plus an off-origin model, an inch-scale model, a truncated GLB and an HTML body;
(d) `ng test` (830/830 pass) and `ng build` (three ends up in the lazy `car-scene` chunk, 664 kB raw; the Draco files are in `assets/draco/`).

## Findings

- **major — `car-scene.ts:196-227` (`setStatuses`, `requestRender` at :226), driven by `car-view-3d.component.ts:150-154`. Render-on-demand doesn't work while data is flowing.**
  - Issue: `ShutdownLoopService.status` is a `computed` over `now` (1 Hz `setInterval`) and every shutdown-topic reading/`lastSeen`. Each recompute makes a new `nodes()` array, so the effect calls `setStatuses`. That always re-sets every marker and segment and calls `requestRender()`, which does a full render, `project()`, and 19 `querySelector` + style writes, even when no state changed.
  - Failure scenario: with the sim running (or the real car on the pit laptop), the 3D view renders all the time at the message rate. The cost grows with the real CAD model (Ghost mode is transparent and DoubleSide), so it drains battery and GPU on low-power laptops. It defeats the "renders only on change" design.
  - Evidence: live, 3D, no interaction: **125 renders in 20 s while badge state classes changed 13 times** (about 90 % redundant). 6.4 renders/s. Main-thread TaskDuration was 22.5 s per 30 s in 3D vs 8.8 s per 30 s in 2D (SwiftShader inflates the absolute number; the ratio is the point). With no data arriving, idle is 0 frames.
  - Fix: in `setStatuses`, build a per-marker key (`shape|colour|hollow`) and a per-segment key (`colour|emphasis`). Mutate and `requestRender()` only when a key changed. Alternatively, have the component feed the scene a `computed` of `{id,state,topic}` with an `equal` function, so ticks of `ageMs`, `value` and `now` don't reach three at all.

- **minor — `car-scene.ts:143-155` + `car-view-3d.utils.ts:28,35-38`. Anchor detection hides real CAD geometry and treats unrelated parts as anchors.**
  - Issue: any name matching `^shutdown[:_]…` (any case) counts as an anchor, even when the id is not a loop node. A matching `Mesh` then gets `visible = false`, which hides its whole subtree. It is also left out of `meshes`, so material modes skip it. The `obj.name` fallback reads GLTFLoader's *sanitised* name: whitespace becomes `_`, `:` is stripped, and duplicates get `_1`. So a mesh-level name `Shutdown Panel` becomes `Shutdown_Panel` and matches, and a second `shutdown_tsms` becomes `shutdown_tsms_1`, which parses as id `tsms-1`.
  - Failure scenario: a real CAD export with a part called `Shutdown_Button_Left`, `SHUTDOWN_HARNESS` or `Shutdown Switch` (natural names on an FSAE car) makes that part vanish from the 3D view. The only trace is a console warning about an "unknown node anchor". Naming the real TSMS part or assembly `shutdown:tsms` (instead of an empty) hides the whole part or assembly.
  - Evidence: harness on `metres-anchors.glb` / `mm-anchors.glb` / `draco-mm-anchors.glb`: `hidden: ["shutdownhvd","Shutdown_Button_Left"]` (the latter is a 0.3 m box), and the console shows `unknown node anchors [Shutdown_Button_Left]`.
  - Fix: count a node as an anchor (and hide it) only when the parsed id is in `options.nodes`. Read only `userData.name` (the authored name); don't fall back to the sanitised `obj.name`, or apply the same rules to it. Hide only childless meshes, or meshes whose world bounding box is tiny (for example a diagonal under 5 cm).

- **minor — `car-scene.ts:150`. A multi-material anchor part is not hidden, despite the README ("A tiny part used as an anchor is hidden").**
  - Issue: GLTFLoader turns a node whose mesh has more than one primitive into a `Group` holding one `Mesh` per primitive. Only `obj instanceof Mesh` is hidden, so the Group is used as the anchor, and its child meshes stay visible and go into `meshes`, where they get repainted.
  - Failure scenario: a small marker part with two materials, exported as the anchor, shows up as a stray blob at the node.
  - Evidence: harness: the `shutdown:glvms` node with 2 primitives gives `visibleMeshes: ["body","glvms-part","glvms-part_1"]`, and the position is correctly taken from the model.
  - Fix: hide the anchor object itself, whatever its type (`obj.visible = false`). Skip its descendants when collecting `meshes`, subject to the size and child guard in the finding above.

- **minor — `car-scene.ts:78-88` (`createCarScene`) / `car-view-3d.component.ts:193-225`. No load timeout: a hung model request or a broken Draco decoder leaves "Loading car model…" up forever, with no fallback.**
  - Issue: `loader.loadAsync` has no timeout or abort. `DRACOLoader` sets no `onerror` on its workers. If `draco_wasm_wrapper.js` comes back as HTML, the worker fails to evaluate and the decode promise never settles. nginx (`nginx.conf`, `try_files $uri $uri/ /index.html`) returns `index.html` with status 200 for any missing asset.
  - Failure scenario: a deploy that misses `assets/draco/` (for example a custom `Dockerfile.prebuilt` staging step), or a stalled proxy or Wi-Fi in the pits. A Draco-compressed `car.glb`, which the README recommends, then never loads and never falls back to 2D.
  - Evidence: live with `page.route` never answering `car.glb`: still `loading: true`, no notice, after 20 s. Production build served under `/argos/` with the draco files answered by `index.html`: still loading after 12 s. The same page with a non-Draco model loads fine. `DRACOLoader.js` has no worker error handler (grep).
  - Fix: `Promise.race` the load against a timeout (say 30 s) that rejects with `CarSceneError('model')`, and dispose the Draco loader so its workers are terminated. Optionally add an nginx `location /assets/ { try_files $uri =404; }` so a missing asset gives a 404 instead of HTML.

- **minor — `car-scene.ts:328-335` (`resize`). Resizing doesn't refit the camera, so the car is clipped after the stage narrows.**
  - Issue: `resize()` updates `camera.aspect` but keeps the distance that `setView` fitted for the old aspect.
  - Failure scenario: rotating a tablet, splitting the screen, or narrowing the window while in Side view. A long, low car cut off at both ends until the user presses "Side" again.
  - Evidence: harness, Side view, stage 1360×520 → 360×280: **4 of 8 bounding-box corners outside the frustum**. After `setView('side')` again: 0. (Iso happens to survive this resize.)
  - Fix: in `resize()`, call `setView(currentPreset)` again unless the user has orbited since the last preset. Track that with OrbitControls' `start` event.

- **minor — `car-scene.ts:122` (`setPixelRatio` only in the constructor). A device-pixel-ratio change is ignored.**
  - Issue: the pixel ratio is read once. Moving the window to a HiDPI monitor, or zooming the browser, keeps the old backing-store ratio. Zoom does fire the ResizeObserver, but `resize()` doesn't re-read `devicePixelRatio`.
  - Failure scenario: a blurry 3D view on the second monitor, or oversized buffers after moving back. Badges don't drift, because projection uses CSS pixels.
  - Evidence: harness after CDP `deviceScaleFactor` 1 → 2: `pr: 1, dpr: 2`, with the canvas backing store at 500×450 for a 500×450 CSS box. The badge projection is unchanged (`[204,189]`), so there is no drift.
  - Fix: in `resize()`, call `renderer.setPixelRatio(Math.min(devicePixelRatio, MAX_PIXEL_RATIO))` when the ratio changed. Optionally also listen to `matchMedia('(resolution: Xdppx)')` changes.

- **minor — `car-scene.ts:176-183, 237-262`. Off-origin models: no centring, the grid is fixed at y = 0, and the camera fits the union of the model and the table markers.**
  - Issue: the README says the viewer "fits the camera to whatever it loads". For a model not exported to the convention (its origin away from the rear axle, which is common in raw CAD), the table markers stay near the origin while the car is elsewhere. Bounds then cover both, and the grid sits at y = 0 with nothing on it.
  - Failure scenario: the first real CAD drop (with the CAD origin 40 m away) shows a tiny car and a tiny cluster of markers far apart, with no hint why.
  - Evidence: harness `offorigin-m.glb` (car at (40, 5, −25)): bounds `[0.2,0.22,-25.6]..[42.5,6,0.33]`, camera at `[54.6,32.2,-54.2]`, far 856.
  - Fix: when no anchors were found and the table positions fall outside the model's bounds, log a clear warning naming the README convention. Place the grid at `bounds.min.y`. Consider fitting to the model only.

- **minor — `car-scene.ts:80-88`. Errors inside the constructor are reported as "model missing or could not be read", and the half-built scene isn't cleaned up.**
  - Issue: the `try` wraps both `loadAsync` and `new ThreeCarScene(...)`. Any bug in setup (resolving positions, building markers, OrbitControls, ResizeObserver) maps to `CarSceneError('model')`. Only the renderer and Draco loader are disposed; controls listeners and the ResizeObserver that already exist are not.
  - Failure scenario: a code regression sends people hunting for a "missing car.glb" when the file is fine.
  - Evidence: code reading only, not reproduced at runtime.
  - Fix: put the `try` around `loadAsync` alone. Wrap constructor failures as `'init'`, and make the constructor's partial state disposable, or build it in a `try` that calls `dispose()`.

- **minor — tests: `car-view-3d.component.spec.ts:17-27` fakes the whole scene, and `car-scene.ts` (360 lines) has no tests.**
  - Issue: unit scaling, anchor reading via `userData.name`, hiding, material swaps, dispose and the render loop run only in the browser. The utils specs test `parseNodeAnchorName` and `unitScaleFor` on their own, not how they are wired (for example, that anchors are read *after* scaling, or that sanitised names are handled).
  - Failure scenario: the bugs above (false-positive hiding, the Group anchor) pass CI, and so would a regression that reads anchors before scaling.
  - Evidence: `ng test` passes 830/830. `grep car-scene` in the specs matches only types and the fake.
  - Fix: pull the model preparation (`scale → updateMatrixWorld → traverse anchors/meshes`) out into a function that takes an `Object3D` and needs no WebGL. Test it with three objects built in the spec (an mm group with a nested, scaled anchor, a multi-primitive anchor, and a `Shutdown_Button` part).

- **nit — `car-view-3d.utils.ts:180-185` (`unitScaleFor`). The heuristic misreads some exports.**
  - Issue and evidence: an inch export of a 2.9 m car (max dimension 114) is treated as centimetres and comes out 1.14 m long (harness `inches.glb`: scale 0.01, bounds 2.19 m including markers). A model in metres that includes a ground plane or environment larger than 50 m shrinks 100×. A millimetre export exactly 1000 long counts as centimetres.
  - Fix: pick the scale from {1, 0.01, 0.001, 0.0254} that brings the largest dimension closest to a car's 1.5–6 m. Log the chosen scale so a CAD drop can be checked.

- **nit — `car-view-3d.component.ts:43-49` + `car-view-3d.utils.ts:297-304`. The WebGL probe creates a throwaway WebGL context on every 3D mount and never releases it.**
  - Evidence: live, counting contexts: 2 created and 1 lost per 2D→3D toggle (42 created / 20 lost after 20 toggles; 82 / 40 after 20 more fast toggles). GC reclaims them, and I saw no "Too many active WebGL contexts" warning, but each probe creates a full context.
  - Fix: cache the result in a module-level `let`, or call `getExtension('WEBGL_lose_context')?.loseContext()` on the probe context.

- **nit — `car-view-3d.component.html:288-301` / `car-view-3d.component.ts:234-243`. A node with no position gets a badge that is never placed, so it shows at the stage's top-left.**
  - Issue: buttons are rendered for every node, but `placeBadges` only touches nodes in `points`, which are the placed markers. A node with neither an anchor nor a table entry keeps no transform and stays `visibility: visible`, at (0, 0). Today `shutdown-loop.positions-3d.spec.ts` ensures the table is complete, so this needs a table edit to happen.
  - Fix: default `.badge { visibility: hidden }` and let `placeBadges` reveal placed ones, or don't render badges for ids missing from `positionSources`.

## Verified OK (no finding)

- **No GPU or heap leak across toggles and route changes.** Heap-snapshot instance counts while 3D is shown: `ThreeCarScene` 1, `WebGLRenderer` 1, `OrbitControls` 1, `DRACOLoader` 1, `Mesh` 71, both before and after 12 toggles. After switching to 2D, all of these drop to 0. `dispose()` removes every canvas and document listener (CDP `getEventListeners`), no rAF fires after dispose, and each renderer's context is lost (20 of 20). Fast toggles while loading dispose the late scene. The heap growth seen with plain `getHeapUsage` came from console retention: the app's NG0100 errors from `MessagesPerSecondComponent` / `CurrentRunDisplayComponent`, which also occur in 2D and before this branch.
- **3-minute soak, live sim, heap after forced GC at 0/60/120/180 s.** 3D: 23.5 / 24.4 / 25.5 / 25.9 MB (+2.4 MB). 2D in parallel: 16.0 / 16.6 / 19.0 / 20.0 MB (+4.0 MB). That is the app's own baseline growth (console retention of the NG0100 errors); the 3D view adds nothing on top.
- **Material modes.** 60 CAD/Theme/Ghost cycles add no geometries, textures or programs (`programs: 4`). CAD materials come back by identity, and no shared material is changed.
- **Units and anchors.** m, cm, mm and Draco-mm models all give the same metres positions (`bots` from a nested anchor under a ×2-scaled parent → `[2.2,0.3,0]`). Anchors are read after scaling and use world transforms. The first duplicate wins, and the `Shutdown_Side_BRB_R.001` and `shutdown:` forms parse.
- **Draco under a non-root base href.** The production build served at `/argos/` with `<base href="/argos/">` loads `/argos/assets/draco/*` and the model. The module-level `new URL(..., import.meta.url)` defaults in DRACOLoader are overridden by `setDecoderPath`.
- **Fallbacks.** Truncated GLB, HTML body, aborted request and 404 all show the 2D view with the model notice, and the context is released.
- **Picking.** Live: a click on a marker selects it, a drag that starts on a marker doesn't change the selection, a 3 px jitter still counts as a click, and a click on empty canvas clears the selection.
- **Damping and idle.** Damping settles and rendering stops. With no data, 0 frames per 3 s. Badge projection follows resizes (uses the new aspect and CSS size).
