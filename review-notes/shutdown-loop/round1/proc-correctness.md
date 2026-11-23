# Round 1 review: `throwaway-shutdown-3d-procedural`, correctness and performance

Reviewer lens: correctness and performance. Diff `origin/shutdown-loop-page...HEAD` (3 commits, up to 78b75be2).
Paths below are relative to `angular-client/src/pages/shutdown-page/`.
Measurements: live client at :4202 (Calypso sim flapping), headless Chromium with SwiftShader (software WebGL), Playwright with an init script that counts WebGL create/delete calls, `gl.clear` (one per render), `requestAnimationFrame`, ResizeObserver observe/disconnect and context creations, plus CDP `Performance.getMetrics`, `DOMDebugger.getEventListeners` and heap snapshots. Scripts and raw output are in `scratchpad/r1-proc-correctness/` (`measure*.js/.out`, `pick*.mjs`, `pickclick.js`, `lost.js`, `retain.js`).

## Findings

- **major: picking selects the wrong node at its own marker's centre (oversized invisible pick spheres, and labels in the pick set)**
  - Where: `components/car-view-3d/car-scene.ts:111` (`pickGeo = new SphereGeometry(MARKER_R * 2.2, …)`, radius 0.066 m), `:174` (`pickables.push(pick, label)`), `:273-279` (`hit` takes the first ray intersection).
  - Issue: each pick proxy has radius 0.066 m, but neighbouring nodes sit 0.06–0.09 m apart (the latches are 0.07 m apart on x, the accumulator sense points 0.07 m apart, inertia and cockpit BRB 0.24 m apart on z but only 0.06 m apart on y, HVD near AIRs). So a closer neighbour's invisible sphere covers part of a visible marker. Labels are always drawn on top (`depthTest: false`) and are also pickable, so a label overlapping a marker takes the click.
  - Failure scenario: in the default Iso view, clicking the centre of the AIRs marker (node 19) opens **13. HVD**. In the Side view, clicking the centre of Cockpit BRB opens **10. Inertia switch**. The user gets another node's state, value and age.
  - Evidence: clicks in the live app with reduced motion, so the camera sits exactly on the preset. Pixel positions come from projecting `NODE_POSITIONS_3D` with the same camera:
    `iso click at centre of airs (791 620) -> 13. HVD`; `side click at centre of cockpit-brb (597 475) -> 10. Inertia switch`. Other nodes picked correctly (HVD, IMD latch, TSMS, GLVMS).
    An offline raycast with the same geometry, at each marker's projected centre: Iso gives 3/19 wrong (`can-latch->em-interlock(label), ts-plus->hvd, airs->hvd`); Side gives 1/19 (`cockpit-brb->inertia`). Repeating it with visual-size spheres (r = 0.0435) as occluders drops Side to 0/19 and Iso to 1/19. So the cockpit-brb and airs misses come from the proxies, not from real occlusion. (The 3 Top-view misses, ts-minus/ts-plus/airs under the latches, are genuine occlusion.)
  - Suggested fix: pick in screen space. Project each marker centre, take the nearest within about 12–16 px, and break ties by depth. This is also cheaper than raycasting on every `pointermove`. Failing that, raycast the visible marker meshes first and fall back to proxies only on a miss, shrink the proxies below half the nearest-neighbour spacing (≤ 0.03 m), and drop labels from `pickables` or give them lower priority than markers. Add a unit test for the pick function (see the test-coverage finding below).

- **major: render loop runs at the display rate for as long as any node is `suspect`, which is the normal state whenever the loop is open, including when the canvas is scrolled partly out of view**
  - Where: `components/car-view-3d/car-scene.ts:232-237` (`pulse` returns `true` whenever `suspects.length`), `:251` (`if (tweening || moving || pulsing) requestRender()`).
  - Issue: "render on demand" only holds while the loop is closed. A broken loop always has a suspect, so every animation frame re-renders the whole scene (~196 draw calls) just to scale one marker. There's no IntersectionObserver or visibility gate, and no frame-rate cap. On a real GPU that means 60 fps, or 120/144 on high-refresh screens, indefinitely on the pit laptop.
  - Evidence: steady state on the live sim (1–3 suspects present), 10 s windows:
    `reducedMotion: reduce -> rendersPerSec 1.8, cpuTaskPct 49.8` versus `no-preference (pulse on) -> rendersPerSec 7.2, cpuTaskPct 89.4`. SwiftShader caps the frame rate; the main thread is about 90 % busy. For comparison, 2D mode on the same sim runs at `cpuTaskPct 31.4`. `drawsPerFrame: 196`. With the canvas scrolled to `top:-260,bottom:100` (mostly off screen) it still did `94 renders in 5 s`.
  - Suggested fix: run the pulse at a low fixed rate, for example a `setTimeout` or rAF throttled to about 10–15 Hz, which is enough for a 1.2 s sine. Alternatively, drop the geometric pulse for a static highlight such as the emissive/halo ring that is already in the scene. Also pause rendering when the canvas isn't intersecting (IntersectionObserver), and render one frame when it comes back into view.

- **minor: high draw-call count makes every render expensive (multiplies the pulse cost)**
  - Where: `components/car-view-3d/car-model.ts:124-131` (one `Mesh` per frame tube or arm), `car-scene.ts:156-159` (one `Mesh` per dash piece), `:161-176` (marker, invisible pick and label per node).
  - Issue: 196 draw calls per frame for a static car and about 20 markers. Most of the car is static and uses a handful of materials.
  - Evidence: `drawsPerFrame: 196` (from the counters on `drawElements`/`drawArrays` and `clear`).
  - Suggested fix: merge the static car tubes per material (`BufferGeometryUtils.mergeGeometries`, or one `InstancedMesh` per material for the unit tube), and use an `InstancedMesh` per state material for the loop dashes. That should bring it to about 20–30 draws. It matters only while something forces continuous frames.

- **minor: `isWebGLAvailable` creates a WebGL context on every mount and never releases it**
  - Where: `components/car-view-3d/car-view-3d.model.ts:151-158`; called per component construction through `car-view-3d.tokens.ts:12` and `car-view-3d.component.ts:58`.
  - Issue: every 2D→3D toggle or navigation back to the page creates a throwaway `webgl2` context, as well as the real one, and leaves it for GC. Chrome warns and force-loses the oldest context past 16 live ones. The real view's context is always the newest so it survives, but GPU memory is held until GC.
  - Evidence: contexts created went from 4 to 54 over 25 toggles (2 per mount). No "Too many active WebGL contexts" warning appeared in these runs (GC kept up).
  - Suggested fix: memoise the result in the token factory (compute once) and call `gl.getExtension('WEBGL_lose_context')?.loseContext()` on the probe context.

- **minor: renderer leaks if `createCarScene` throws after creating it**
  - Where: `components/car-view-3d/car-scene.ts:75` versus `car-view-3d.component.ts:146-160`.
  - Issue: if anything after `new WebGLRenderer` throws (for example OrbitControls, `ResizeObserver` missing on an old WebView, or `getContext('2d')` returning null in `badgeTexture`), `start()` catches it and calls `fallBack()`. But `this.scene` is still undefined, so `stop()` disposes nothing and the context stays alive until GC.
  - Suggested fix: wrap the body of `createCarScene` after renderer creation in try/catch, then `renderer.dispose(); renderer.forceContextLoss(); throw err`.

- **minor: the tests mock the entire scene, so picking, dispose and the render loop are untested**
  - Where: `components/car-view-3d/car-view-3d.component.spec.ts:28-38` (the fake `CarScene`); no spec exists for `car-scene.ts` or `car-model.ts`.
  - Issue: both majors above, wrong-node picking and the continuous pulse loop, live in untested code. The context-loss test calls `options.onContextLost()` directly, so it would still pass if `car-scene.ts` stopped listening for `webglcontextlost`. `car-view-switcher.component.spec.ts` always provides `WEBGL_SUPPORT: () => false`, so toggling never exercises a 3D mount and dispose.
  - Suggested fix: move picking into a pure function (`pickNode(markers, camera, ndc)` or a screen-space nearest-marker function) and unit-test it against `NODE_POSITIONS_3D` and `CAMERA_PRESETS`, including the AIRs/HVD and Cockpit BRB/Inertia cases. Also test that `requestRender` stops once there's no suspect and no tween or damping. That can run with a stub renderer if render scheduling is pulled out of `createCarScene`.

- **nit: `forceContextLoss()` after a real context loss logs a warning**
  - Where: `components/car-view-3d/car-scene.ts:321`, reached from `onLost` → `onContextLost` → `fallBack()` → `dispose()`.
  - Evidence: after `WEBGL_lose_context.loseContext()` in the live page the 2D fallback appears correctly (`fallback 2D shown = 1, canvas present = 0`), but the console shows `THREE.WebGLRenderer: WEBGL_lose_context extension not supported.`
  - Suggested fix: `if (!renderer.getContext().isContextLost()) renderer.forceContextLoss();`.

- **nit: a right or middle click without movement counts as a pick**
  - Where: `components/car-view-3d/car-scene.ts:281-285`.
  - Issue: `onUp` doesn't check `e.button` or `e.isPrimary`. A right-click (which is the pan gesture) on empty space clears the selection, and on a marker it selects that node. During a two-finger pinch, the second `pointerdown` overwrites `down`.
  - Suggested fix: record `down` only for `e.button === 0 && e.isPrimary`, and in `onUp` match on `pointerId`.

- **nit: `NgZone.runOutsideAngular` calls do nothing in this app**
  - Where: `components/car-view-3d/car-view-3d.component.ts:86,90,99,146`.
  - Issue: the app is zoneless (Angular 22, no zone.js in `main.ts` or polyfills), so these wrappers have no effect and suggest a zone-storm safeguard that doesn't exist. They're harmless: signal writes from `onPick` and `onContextLost` schedule change detection correctly, as the live click tests confirm.
  - Suggested fix: remove them, or leave a one-line comment that they're no-ops here.

- **nit: device pixel ratio is read once**
  - Where: `components/car-view-3d/car-scene.ts:76`.
  - Issue: dragging the window between a 1x and a 2x monitor leaves the canvas blurry, or oversampled, until the next mount.
  - Suggested fix: call `setPixelRatio` again inside `resize`, or listen with `matchMedia('(resolution: …dppx)')`.

## Checked and found OK (no finding)

- **Lazy chunk:** `three.core.js`, `three.module.js`, `OrbitControls.js`, `car-model.ts` and `car-scene.ts` are only in the lazy `car-scene` chunk (605.9 kB raw, 125 kB transfer). `shutdown-page-component` is 35.5 kB and the initial total 777.8 kB, with no three in it (checked against `browser-stats.json`).
- **GPU and JS resources on unmount:** a heap snapshot after 8 toggles followed by 2D shows no `WebGLRenderer`, `OrbitControls`, `Scene` or `CanvasTexture` instances retained. The one `PerspectiveCamera` and `WebGL2RenderingContext` found are the `ArrayCamera.prototype` and the binding prototype. Geometries, materials and textures are disposed before `renderer.dispose()`. Contexts are force-lost on unmount.
- **Listeners:** document and window listener counts (CDP) didn't change after 10 navigations away and back plus 15 toggles. ResizeObserver observe/disconnect balanced at 27/26, with one live.
- **Heap:** 35.3 → 36.7 MB over 3 minutes in 3D on the flapping sim, with forced GC, so flat. +0.4 MB over 15 toggles.
- **Rebuilds:** the scene is rebuilt only when `sceneSignature` changes (state or mismatch), not on every message or age tick. Rebuilds reuse shared geometry and materials, so they cause no GPU uploads.
- **Context loss:** falls back to 2D with no page error.
- **Theme colours:** hex tokens, read after `await loadScene()`, so styles are applied. The `display:none` probes still resolve `--sd-color`. There is a single dark theme, so a one-time read is fine.
- **Badge font:** Roboto bold was already loaded when the badge textures were drawn (`document.fonts.check` returned true at `fillText`).
- **Checks:** `ng test` passes (810 tests) and `ng build` succeeds.
