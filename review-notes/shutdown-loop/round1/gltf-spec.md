# Round 1 review: `throwaway-shutdown-3d-gltf` (conventions, architecture, integration)

Diff: `origin/shutdown-loop-page...HEAD` (2 commits, 21 files, +2285/-5). Paths below are relative to `angular-client/` unless they start with `docs/`. `C3D` = `src/pages/shutdown-page/components/car-view-3d/`.

Checked against: `docs/CONTEXT.md` Conventions, ADR 0007, Argos `CLAUDE.md`, `docs/spec/shutdown-loop-page/spec.md`, `package.json`/lockfile, `angular.json`, `nginx.conf`, `Dockerfile`, and the built `dist/` in both 3D worktrees. Sibling diffs read only.

## Findings

### Blockers (for merging with the sibling branches)

- **blocker**: `C3D/car-view-3d.component.ts:81`, `:114`, `:120`, `:138`, `:244-255`, `C3D/car-view-3d.component.html:1-6`, `C3D/car-view-3d.component.css:48,55,57,111`, `C3D/car-view-3d.utils.ts:68-87`
  - **Issue:** The colours depend on `../../shutdown-states.css`, the `--sd-color` custom property (read through hidden "probe" spans), and `NODE_STATE_DISPLAY[state].cssClass`.
  - **Why:** `throwaway-shutdown-ui` deletes `shutdown-states.css` and `--sd-color`, and rewrites `NODE_STATE_DISPLAY` with no `cssClass` field (it now has `text`/`marker`/`stroke`/`connector` Tailwind class lists). With both branches merged, the build fails: there is a missing stylesheet and `cssClass` does not exist on `StateDisplay`. The procedural branch has the same dependency.
  - **Fix:** Read the state colours straight from theme tokens. Add one map next to `NODE_STATE_DISPLAY` in the UI branch's `shutdown-loop.display.ts`, e.g. `STATE_COLOR_TOKEN: Record<NodeState, string> = { closed: '--color-success', suspect: '--color-danger', 'downstream-open': '--color-fg-dim', 'no-data': '--color-fg-muted' }`, matching the UI branch's `marker`/`stroke` choices. Then call `getComputedStyle(documentElement).getPropertyValue(token)`, as `themeColours()` (`:257-266`) already does. Delete the probes, `resolveStateColours`, and the hard-coded hex `FALLBACK_STATE_COLOURS` (those hex values duplicate the deleted stylesheet and drift from the AA-vetted tokens). Badges take `NODE_STATE_DISPLAY[state].marker.measured|unmeasured`.

- **blocker**: `src/pages/shutdown-page/shutdown-loop.positions-3d.ts:1-44` (vs procedural's file at the same path)
  - **Issue:** Both 3D branches add the same file with the same export name `NODE_POSITIONS_3D`, but with incompatible types and coordinate frames.
    - glTF: `Vec3` tuple, origin on the ground under the rear axle, +X forward, +Z to the driver's right.
    - Procedural: `CarPoint3d {x,y,z}`, origin at the front bulkhead, +x aft (nose at −x), +z to the driver's left.
  - **Why:** This is a guaranteed textual and semantic conflict, and the merge picks one frame silently. The data is actually the same in both. Converting procedural with `x_g ≈ 2.24 − x_p` and `z_g = −z_p` reproduces glTF's table to within about 0.15 m (BOTS 2.04 vs 2.03, MC 0.20 vs 0.20, AIRs 0.42 vs 0.45, HVD z −0.20 vs −0.22). So unifying them is mechanical.
  - **Fix:** One table, one frame, one `Vec3` type. See "Recommended merge strategy" for which frame.

- **blocker**: `C3D/car-view-3d.component.ts:108`, `:177-191`, html `:21-35`, `:56-84`
  - **Issue:** The 3D view owns its selection (`selectedId` signal) and renders its own detail panel.
  - **Why:** The UI branch's `ShutdownSelectionStore` contract says "A view never owns selection". It specifies inputs `nodes`/`selectedId`/`previewId` and outputs `nodeSelect`/`nodePreview`, and has a page-level `<node-detail>` driven by `selection.activeId()`. As written, picking a node in 3D won't highlight it in the strip or show it in `node-detail`. The page would also show two detail panels.
  - **Fix:**
    - Adopt the contract: `selectedId = input<string|null>(null)`, `previewId = input<string|null>(null)`, `nodeSelect = output<string|null>()`, `nodePreview = output<string|null>()`. The scene highlights `previewId ?? selectedId`.
    - Delete the 3D detail panel and `nodeDetail()`. The UI branch's `formatValue`/`formatAge`/`nodeNotes` cover it.
    - Surface "Position: from the model/table" in `node-detail` behind an optional input, or only in dev mode.

### Major

- **major**: `docs/spec/shutdown-loop-page/spec.md:9,15,109,115` (unchanged by the branch)
  - **Issue:** The spec chose "A. Own simplified SVG car side view" and never mentions 3D.
  - **Why:** This branch adds:
    - a runtime dependency (three: about 167 kB gz in a lazy chunk, plus 756 kB of decoder assets in `dist`);
    - an asset pipeline (`angular.json` Draco copy, a committed binary, a generator script);
    - a cross-team CAD export convention.

    That is an architectural change with no recorded decision. `CLAUDE.md` says "Explain reasoning before making architectural changes", and ADR 0007's "Packages" section shows dependency choices get ADRs.
  - **Fix:** Before merging, amend the spec (add a 3D car view, glTF/procedural considered options, and fallbacks). Add `docs/adr/0010-angular-client-three-js-3d-car-view.md`; 0009 is taken by logic-scylla. It should cover three vs alternatives, lazy loading, the model convention, binary storage, and the procedural fallback.

- **major**: `src/assets/models/car.glb` (166,548 B), `scripts/generate-placeholder-car.mjs` (220 lines)
  - **Issue:** A generated binary is committed together with the script that generates it.
  - **Why:**
    - The placeholder is just a procedurally built car, frozen into a binary: the same idea as the sibling's `car-model.ts`, but untyped, unlinted (ESLint only matches `**/*.ts`, and Prettier's ignore covers `*.js`), untested, and unthemed.
    - Every CAD revision of the real model ("a few MB", README `:31`) adds a new blob to git history forever. There is no `.gitattributes` and no LFS.
    - The repo already has a precedent for large assets: `basemap.pmtiles` is git-ignored and fetched by `utils/fetch-basemap.sh` in CI.
  - **Fix:**
    - Drop the generator and the placeholder GLB. The procedural car is the no-model fallback.
    - When a real CAD export exists, either track `*.glb` with Git LFS (`.gitattributes`: `*.glb filter=lfs diff=lfs merge=lfs -text`; check that CI and Docker builds fetch LFS) or fetch it like the basemap (`utils/fetch-car-model.sh` from a release asset).
    - Decide this in the ADR.

- **major**: `C3D/car-view-3d.component.ts:51`, `nginx.conf:4-6`
  - **Issue:** `assets/models/car.glb` is unhashed, and it is the "is a model present?" signal.
  - **Why:**
    - nginx's `try_files $uri $uri/ /index.html` returns `index.html` with status 200 for a missing GLB, and `ng serve` behaves the same way. "Missing" therefore shows up as a JSON parse error from GLTFLoader, not a 404. Any future "use glTF if present" probe that checks `response.ok` will be wrong.
    - Assets are not covered by `outputHashing`, and nginx sends no `Cache-Control`. After a CAD swap, browsers can keep serving the old model under heuristic freshness.
  - **Fix:**
    - Make the model URL an explicit config: an `InjectionToken<string | null>` (or `window.__env` in `env.js`). `null` means procedural.
    - If you do probe, check the `glTF` magic bytes in the first 4 bytes.
    - For cache-busting, import the model through the build (`"loader": { ".glb": "file" }` in `angular.json` plus `import carUrl from './car.glb'` gives a hashed URL), or add `location /assets/models/ { add_header Cache-Control "no-cache"; }`.

- **major**: `C3D/car-scene.ts:70-89`, `:185-193`
  - **Issue:** There is no `webglcontextlost` handling.
  - **Why:** GPUs drop contexts (laptop sleep, backgrounded mobile tabs, driver resets). The canvas then goes blank with no fallback, on a page whose job is trackside diagnosis. The procedural branch handles this (`car-scene.ts:296-305`, `onContextLost` leads to the fallback).
  - **Fix:** Port procedural's `onContextLost` hook into the shared scene contract (`car-scene.types.ts`).

- **major**: `C3D/car-view-3d.component.css:1-138` (whole file), especially `:78-102`
  - **Issue:** This is a hand-written stylesheet in a page that the UI branch makes utilities-only. The `.seg` rules re-implement `src/ui/recipes/segmented.ts` (`segmentedClasses`), which the same branch's `car-view-switch.component.ts:27-28` already uses.
  - **Why:** The conventions say "a look used in more than one place is a recipe … never built from fragments". Two copies of the segmented look will drift: the hand-rolled copy lacks the recipe's hover tint and transition. The stylesheet-or-utilities split is technically allowed, but after the UI merge this is the page's only stylesheet. Minified, it is about 1.9 kB, near the 2 kB `anyComponentStyle` warning.
  - **Fix:**
    - Convert to utilities: `segmentedClasses.list/item` for both toolbars, badge classes from `NODE_STATE_DISPLAY[...].marker`, `focus-visible:focus-ring`.
    - The only non-utility needs are `touch-action: none` (`touch-none`) and the stage height clamp. Use an arbitrary `h-[clamp(...)]`, which the conventions allow only because it follows the viewport.
    - Delete the CSS file.

- **major**: `C3D/car-view-3d.component.html:21-35`
  - **Issue:** There are 19 badge buttons, each its own Tab stop, with `aria-pressed`.
  - **Why:** The UI branch's 2D view and strip use a `listbox`/`option` pattern with roving tabindex (`rovingIndex()` in `shutdown-selection.store.ts`). One Tab stop per view, and arrows move between nodes. Here, 3D needs 19 Tabs to get past the view, and its ARIA differs from the other two views of the same data.
  - **Fix:** `role="listbox"` on `.badges`, `role="option"` plus `aria-selected` plus `tabindex` from `selectedId ?? first` on each badge, and `(keydown)` going through `rovingIndex`. Emit `nodeSelect` on focus or click and `nodePreview` on mouseenter/leave, exactly like the UI branch's `car-view.component.html`.

### Minor

- **minor**: `angular.json:32`
  - **Issue:** It copies all of `three/examples/jsm/libs/draco/gltf/*` (`draco_decoder.js` 512 kB asm.js plus `.wasm` 192 kB plus the wrapper) into every build. The placeholder GLB uses no extensions (`extensionsUsed` is absent), so the decoder is dead weight today. The folder also leaves out Draco's Apache-2.0 license, which redistribution requires.
  - **Fix:** Add the Draco copy only when a real model is Draco-compressed. Narrow the glob to `draco_wasm_wrapper.js` and `draco_decoder.wasm` (the WASM path is default everywhere we support), and ship the license file next to them (or rely on a `3rdpartylicenses` entry). Also confirm that the nginx:alpine `mime.types` serves `.wasm` as `application/wasm`, which streaming compile needs.

- **minor**: `C3D/car-scene.ts:143-155`
  - **Issue:** Anchor detection only hides an anchor that is itself a `Mesh`.
  - **Why:** For a multi-primitive part (common for CAD parts with several materials), GLTFLoader makes the named node a `Group` with child Meshes. The anchor is found, but its children are kept as car meshes and drawn. Children of an anchor are also traversed as car geometry.
  - **Fix:** On a match, set `obj.visible = false` (any `Object3D`) and skip its subtree.

- **minor**: `C3D/car-view-3d.utils.ts:180-185`
  - **Issue:** `unitScaleFor` handles only mm and cm. A model in inches (SolidWorks/US CAD; car about 115 in) reads as centimetres, which gives a 1.15 m car.
  - **Why:** glTF mandates metres, so a correct exporter is fine. But this heuristic exists precisely to forgive bad exports.
  - **Fix:** Drop the heuristic and document "export in metres", or `console.warn` when it rescales so the CAD team notices.

- **minor**: `src/assets/models/README.md` (whole file)
  - **Issue:** Everything under `src/assets` is copied to `dist`. The README ships publicly at `/assets/models/README.md` (verified in `dist/angular-client/browser/assets/models/`).
  - **Fix:** Move the model and anchor convention to `docs/` (e.g. a section of the spec or ADR 0010) or next to the component.

- **minor**: `C3D/car-view-3d.component.html:8-10`, `C3D/car-view-3d.component.ts:19,83`
  - **Issue:** The 3D component embeds `<car-view>` as its own fallback, and the switcher (`car-view-switch.component.html:8-12`) also renders `<car-view>`.
  - **Why:** It duplicates the 2D wiring. After the UI merge, the nested copy must also forward all five selection bindings, or it silently loses linked selection.
  - **Fix:** Have `car-view-3d` emit `unavailable = output<FallbackReason>()`. The switcher shows the notice and the single 2D `<car-view>`, and could disable the 3D button.

- **minor**: `C3D/car-view-3d.component.ts:12,90,153,158,163,201`
  - **Issue:** It uses `NgZone`/`runOutsideAngular`, but the app is zoneless: there is no `zone.js` in `package.json`.
  - **Why:** Dead ceremony, and the comment at `:76` ("three.js runs outside Angular") misleads.
  - **Fix:** Remove `NgZone`. Render-on-demand already keeps Angular out of the frame loop.

- **minor**: `C3D/car-scene.ts:186`
  - **Issue:** Damping is always on. There is no `prefers-reduced-motion`.
  - **Fix:** Pass `reducedMotion` as procedural does (`enableDamping = !reducedMotion`).

- **minor**: `C3D/car-view-3d.utils.ts:329-347`, `car-view-switch.component.ts:7`
  - **Issue:** The switcher's 2D/3D storage helpers live in the 3D view's utils.
  - **Fix:** Move them into the switcher (procedural does). Use procedural's key `argos.shutdown.carView`, which matches `argos.graphPresets`.

- **minor**: `C3D/car-view-3d.component.html:42-46`
  - **Issue:** The camera preset buttons have no pressed state, while the "Model colours" group next to them does. The `view` signal (`.ts:106`) is set but never read by the template.
  - **Fix:** These are momentary actions (a camera that is then orbited is no longer "Side"), so make them plain buttons styled with `buttonClasses`, not a segmented control. Otherwise add `aria-pressed` and clear it on orbit.

### Nits

- **nit**: `C3D/car-view-3d.component.ts:238`
  - **Issue:** `querySelector` runs once per badge per frame during orbit.
  - **Fix:** Use `viewChildren('badge')` and a `Map<id, HTMLElement>` built when `badges()` changes.

- **nit**: `C3D/car-view-3d.component.html:23-25`
  - **Issue:** The static `class="badge"` plus `[class]="'badge ' + …"` is redundant. Moot once utilities replace it.

- **nit**: `C3D/car-view-3d.component.ts:16`
  - **Issue:** `DOCUMENT` is imported from `@angular/common`. The repo imports it from `@angular/core` (`src/ui/focus/restore-focus.ts:2`).

- **nit**: `C3D/car-view-3d.component.ts:116-127`
  - **Issue:** It builds its own ARIA label. The UI branch has `nodeAriaLabel(s)` in `shutdown-loop.display.ts`.
  - **Fix:** Reuse it so all three views announce nodes identically.

- **nit**: `package.json:42,50`
  - **Issue:** The exact pins `three`/`@types/three` `0.187.0` are right, because three's minor versions break. But add both to any Dependabot group or ignore rule so they move together.
  - **Also:** No `engines` concern. three declares none, the repo requires Node ≥24, and the generator's `FileReader` shim works on Node 24.

## glTF vs procedural comparison

| | glTF (`throwaway-shutdown-3d-gltf`) | Procedural (`throwaway-shutdown-3d-procedural`) |
|---|---|---|
| Source added (non-spec, `car-view-3d/` + switch + positions) | about 1,290 lines: scene 360, types 47, utils 347, component 267, html 85, css 138, switch 33, positions 44; plus a 220-line generator and a 58-line README | about 1,310 lines: car-model 267, scene 366, model 223, component 188, html 72, css 133, tokens 14, switcher 50, positions 45 |
| Binary or extra assets | `car.glb` 166 kB committed (26 kB gz); 756 kB Draco copied into `dist` (unused by the placeholder) | none |
| Lazy three chunk (built `dist`) | 664 kB raw / 167 kB gz (adds GLTFLoader and DRACOLoader) | 606 kB raw / 151 kB gz |
| First paint of 3D | chunk, then GLB fetch and parse (a second round trip), then scene | chunk, then a synchronous build |
| Visual fidelity (placeholder) | bodywork car in "CAD" colours that clash, so "Ghost" is the default; with a real CAD export it is far ahead (true geometry, real component placement) | themed space frame, with accumulator, E-box and MC as see-through boxes; reads cleanly on the dark theme; never more than a diagram |
| Node position workflow for CAD | **strong**: named anchors `shutdown:<id>` in CAD override the table, with tolerant parsing (`_`, case, `.001`), unknown-anchor warnings, and "position from the model/table" shown per node. CAD can move nodes without a code PR (but a GLB commit is still a PR). Weakness: the frame needs a manual 90° rotation (+X forward is not glTF's +Z forward) | **weak**: positions are hand-typed in a TS table tied to the hand-made car's proportions (`CAR_EXTENT_3D`). Any CAD change means a code edit by someone who reads coordinates off CAD |
| Robustness | fallback for no WebGL, a failed three load, or a bad model; **no context-loss handling**; no reduced-motion support | fallback for no WebGL or a failed load; **context-loss to 2D**; reduced motion (no damping, no pulse) |
| Keyboard and a11y | on-canvas badges next to markers (good spatial link), but 19 Tab stops | separate roving toolbar (1 Tab stop, arrows, Home/End, Esc), but detached from the canvas: the number is not shown at the marker |
| Testability | three-free `car-scene.types.ts` contract plus injectable loader; 39 pure-util tests (anchors, resolution, fit, badge layout, picking, units), 13 component, 5 positions, 3 switch. `car-scene.ts` untested | three-free model plus tokens; 16 model, 11 component, 6 positions, 7 switcher (including storage-throws). `car-scene.ts` and `car-model.ts` untested |
| Maintainability | clean split (types / utils / scene); the generator script is a second, unlinted car builder | clean split; car geometry is typed TS under lint and Prettier |
| Untested contract risk | nothing checks that a real GLB matches the convention (axes, units, anchor ids). Suggest a spec that `GLTFLoader.parse`s the committed model (no WebGL needed) and asserts its bounds against the table's extents, with `unknownAnchors` empty | n/a |

**Verdict:** glTF wins on long-term fidelity and on the CAD team's workflow (the anchor override is the most valuable idea across both branches). Procedural wins today: no binaries, a smaller chunk, an on-brand look, and context-loss and reduced-motion handling. They complement each other. The scene layers (camera fit, markers, tubes, picking, render-on-demand) are about 80% the same code written twice.

## Integration conflicts

1. **Same paths, different content** (glTF vs procedural): `C3D/car-scene.ts`, `C3D/car-view-3d.component.{ts,html,css,spec.ts}`, `shutdown-loop.positions-3d.ts` + `.spec.ts`, `package.json`/`package-lock.json` (identical additions, so trivial), `shutdown-page.component.{html,ts}`.
2. **Two switchers:** `car-view-switch` (glTF; key `shutdown-car-view`) vs `car-view-switcher` (procedural; key `argos.shutdown.carView`). Keep one.
3. **Two pure-logic modules:** `car-view-3d.utils.ts` (glTF) vs `car-view-3d.model.ts` (procedural) cover overlapping ground: segments, marker shapes (`box` vs `cube` for no-data), view presets with different orders and default camera logic (glTF fits the bounds; procedural uses fixed `CAMERA_PRESETS`), and node-detail text.
4. **Two injection-token homes:** glTF's tokens are in `car-view-3d.component.ts:37-49` (`CAR_SCENE_LOADER` returns a module), procedural's in `car-view-3d.tokens.ts` (`CAR_SCENE_LOADER` returns a factory). Same name, different type.
5. **vs `throwaway-shutdown-ui`:**
   - `shutdown-states.css`, `--sd-color` and `NODE_STATE_DISPLAY.cssClass` are removed, which breaks both 3D branches at compile time.
   - `shutdown-page.component.html` is rewritten: the `<car-view>` section with selection bindings in a grid beside `<node-detail>`, aria-label "Car side view". Both 3D branches edit the old `.panel` markup.
   - The selection store contract is unmet by both 3D views. Both have a local `selectedId` and their own detail panels, which duplicate `node-detail`.
   - `formatValue`/`formatAge`/`nodeAriaLabel` duplicate the 3D `nodeDetail`/aria code.
6. **vs `throwaway-shutdown-logic-scylla`:** `computeLoopStatus(nodes, readings, now)` drops `boardLastSeen`, and `LoopStatus` gains `source`. The 3D branches consume only `NodeStatus` (shape unchanged) and `status().nodes`, so there is no direct break. Only the spec files conflict: logic amends `docs/spec/shutdown-loop-page/spec.md` and adds ADR 0009, and the 3D spec amendment must rebase on it and use ADR 0010.

## Recommended merge strategy

**Order:** Merge `throwaway-shutdown-logic-scylla`, then `throwaway-shutdown-ui`, into `shutdown-loop-page` first. Then build one 3D change on top, as a ticket branch per `CLAUDE.md` (the `merge --squash` throwaway flow), with the spec amendment and ADR 0010 in the same PR.

**Target shape:** a single `car-view-3d` with a pluggable car source.

```
components/car-view-3d/
  car-scene.types.ts        (glTF's, extended)  CarScene + CarSource + SceneOptions{onContextLost, reducedMotion}
  car-scene.ts              (merge)  renderer/camera/OrbitControls/markers/tubes/pick/render-on-demand
  car-source.gltf.ts        (from glTF car-scene.ts:70-155)  GLTFLoader (+DRACO only if needed), unit scale, anchor scan
  car-source.procedural.ts  (procedural car-model.ts, re-framed)  returns { object, anchors: [], kind: 'procedural' }
  car-view-3d.utils.ts      (glTF's, trimmed)  anchors, resolveNodePositions, fitDistanceToPoints, placeBadges,
                            nearestPoint, unitScaleFor, CarSceneError; + procedural's buildLoopSegments dashed flag
  car-view-3d.tokens.ts     (procedural's file)  CAR_SCENE_LOADER, WEBGL_SUPPORT, + CAR_MODEL_URL: string | null
  car-view-3d.component.*   utilities only, no .css; selection-store contract; listbox badges
components/car-view-switcher/  (procedural's, keep the storage-throws test)  renders the notice + the single 2D fallback
shutdown-loop.positions-3d.ts  one table, one frame, Vec3 tuples; NODE_ANCHOR_PREFIX (glTF)
```

**Car source selection:**
- If `CAR_MODEL_URL` is non-null (default `null` until CAD delivers), load glTF. If that fails, log it and use **procedural**, not 2D.
- Fall back to 2D only for no WebGL, a failed chunk load, or context loss (`unavailable` output, then the switcher).
- Never infer "model present" from an HTTP status, because the SPA fallback returns 200. Show "Model colours" (CAD/Theme/Ghost) only when `kind === 'cad'`.

**Positions:**
- Keep one table plus glTF's anchor override (`resolveNodePositions`), so CAD anchors win when a real model exists.
- Pick the frame once and document it in ADR 0010. Recommendation:
  - origin on the ground under the rear axle centre (glTF branch: a stable CAD datum);
  - **glTF-native axes**: +Y up, +Z forward, +X to the driver's left. A Blender model facing its default front exports with no manual rotation, which removes the README's error-prone "turn it 90° about Y" step.
- Build `car-source.procedural.ts` in the same frame. Mechanical conversion from procedural: `x = z_p`, `y = y_p`, `z = 2.15 − x_p` (procedural `REAR_AXLE_X = 2.15`).
- Keep both positions specs' invariants, plus a "table entries lie inside the procedural car's extent" check.

**Keep from glTF:**
- `car-scene.types.ts` (the three-free contract);
- `parseNodeAnchorName`/`resolveNodePositions`/`unitScaleFor` (with a rescale warning)/`fitDistanceToPoints`/`placeBadges`/`nearestPoint`/`CarSceneError` and their 39 tests;
- the on-canvas badge overlay (converted to listbox/roving);
- camera fit to bounds (better than fixed presets for an arbitrary CAD model);
- the README's export and anchor guidance, moved to `docs/`.

**Keep from procedural:**
- `car-model.ts` (as the procedural source);
- context-loss and reduced-motion handling in `car-scene.ts`;
- the suspect pulse (reduced-motion aware);
- `car-view-3d.tokens.ts`;
- `car-view-switcher` with its tests and storage key;
- the dashed-segment idea for downstream and no-data states, matching the UI branch's `dash`.

**Keep from UI:**
- the `ShutdownSelectionStore` contract and `rovingIndex`;
- `NODE_STATE_DISPLAY` marker classes for badges;
- `node-detail` as the only detail panel;
- `nodeAriaLabel`, `formatValue`, `formatAge`;
- add a `STATE_COLOR_TOKEN` map in `shutdown-loop.display.ts` for the WebGL colours.

**Drop:**
- `scripts/generate-placeholder-car.mjs` and `src/assets/models/car.glb`. Add a real GLB later via LFS or a fetch script, per the ADR.
- `src/assets/models/README.md`, moved to `docs/`.
- The Draco `angular.json` entry until a Draco model exists.
- Both `car-view-3d.component.css` files, the probes, `FALLBACK_STATE_COLOURS`, `resolveStateColours`, both 3D detail panels, `nodeDetail`/`nodeInfo`, `NgZone`, the nested `<car-view>` inside `car-view-3d`, glTF's `car-view-switch/`, and procedural's separate node toolbar (superseded by listbox badges at the markers).

**Tests to add in the merged branch:**
- source selection: URL null gives procedural; glTF failure gives procedural; context loss gives the `unavailable` output;
- selection contract I/O on the 3D view (mirroring the UI branch's `car-view.component.spec.ts`);
- once a real model lands, a GLB contract spec (parse, bounds vs table extents, no unknown anchors).
