# Judge, round 1: `throwaway-shutdown-3d-gltf`

Inputs: `gltf-correctness.md`, `gltf-live.md`, `gltf-spec.md`, with the integration sections of `proc-spec.md` and `ui-spec.md`. Code read at `worktrees/argos/throwaway-shutdown-3d-gltf` (HEAD `69564d46`, diff against `origin/shutdown-loop-page`) and the procedural sibling. Scratch checks are in `scratchpad/judge-gltf/`. No worktree was edited.

User constraint: both 3D approaches stay as **separate throwaway branches**. Nothing here merges them. Each converges on shared pieces only where that is cheap (see "Convergence with procedural").

## Verdict

**Continue to round 2. Not adoptable as it stands.** Taken alone, the branch has no blockers: it builds, 830/830 tests pass, toggles and route changes don't leak, and every fallback lands correctly. The reviewers' three "blockers" (`shutdown-states.css`/`cssClass`, positions frame, local selection) block a *merge with the UI branch*. Under the no-merge constraint they become contract-adoption MUSTs (M1, M2).

The branch's distinctive value is the CAD pipeline: the GLTFLoader path, `shutdown:<id>` anchors overriding the table, unit forgiveness, material modes and fit-to-bounds. Round 2 should make that pipeline trustworthy (M3–M5), fix the diagnostic read (M6–M8), and port procedural's robustness (M9–M10).

### What I spot-checked

| Claim | Result |
|---|---|
| Render thrash (125 renders/20 s) | **Confirmed by code.** `ShutdownLoopService.status` is a `computed` over a 1 Hz `now` (`shutdown-loop.service.ts:21-27`). `setStatuses` always mutates and calls `requestRender()` (`car-scene.ts:196-227`). |
| Anchor over-matching | **Confirmed** (`judge-gltf/anchor-check.mjs`). `Shutdown_Button_Left` parses to `button-left`, `SHUTDOWN_HARNESS` to `harness`, `shutdown_tsms_1` to `tsms-1`. `car-scene.ts:146-150` hides any parse hit, whether or not the id is a loop node. |
| **New:** the placeholder never exercises anchors | `car.glb` node names are only `car`, `body`, `wheel-*`, `wishbone-*` and similar, with **no** `shutdown:*` node. The headline feature (model overrides the table) is never demoed, and nothing tests it end to end. |
| "Missing model returns index.html with 200" | **Half right.** The `ng serve` dev server returns **404 `text/html`** for a missing `.glb` (curl on :4200–:4203). Production nginx (`try_files $uri $uri/ /index.html`) does return `index.html` with 200. The fix is needed either way, because a status check is not a presence check. |
| Inches give a 1.14 m car | **Confirmed** (`unitScaleFor(114)` = 0.01). |
| No Draco hang protection | **Confirmed.** `DRACOLoader.js` has no worker `onerror`. `GLTFLoader.parseAsync(data, path)` exists in 0.187, so fetch-then-parse is possible. |
| Draco licence | three's `libs/draco/gltf/` has **no licence file**. The parent README only links Apache-2.0. |
| Phone scroll capture: is the CSS fix enough? | **No.** `OrbitControls.connect()` sets an inline `domElement.style.touchAction = 'none'` (`OrbitControls.js:507`), which beats any stylesheet. The fix has to set it inline *after* constructing the controls. |
| README Blender axes | **Confirmed wrong.** The Blender exporter maps Blender (x, y, z) to glTF (x, z, −y), so "Y up in Blender" puts the car on its side. |
| Positions frames | Same data within about 0.15 m, **except `em-interlock`**: glTF has it on the driver's right, procedural on the left. The spec doesn't say which. |
| Binary already published? | **Yes.** `origin/throwaway-shutdown-3d-gltf` is at HEAD, so the 166 kB blob is already in the remote's history. Deleting it now removes nothing from history. |
| Zone, theme | No `zone.js` (zoneless, so `NgZone` is dead code). The app is dark-only, so reading tokens once at start is fine. `--color-danger` `#fb923c` and `--color-warn` `#fbbf24` are close in hue, so mismatch needs a glyph as well as a colour. |

## Decisions on the questions raised

- **Placeholder `car.glb` and generator: KEEP on this throwaway, and regenerate it with anchors (M4).**
  - Reasons:
    - The blob is already pushed, so dropping it gains nothing for history.
    - This branch exists to demo the *glTF* path, and only a real GLB exercises the loader, anchors and material modes.
    - Porting procedural's car as the stand-in would blur the two approaches the user wants kept apart.
    - Adoption is a squash into a ticket branch. The asset decision belongs there, in ADR 0010: LFS, a basemap-style fetch script, or no placeholder with procedural as the source.
  - What the reviewers wanted is still delivered: model presence is explicit (M3), an absent model has a defined 3D state (below), and nothing assumes the file exists.
- **No model, so what does the branch show?** Two cases (M3):
  - **Absent** (`CAR_MODEL_URL` is null, a 404, or the body isn't a GLB): a **wiring-only 3D scene** with markers, dashed or solid wires, grid and badges over the table positions, and no car body. A notice reads "No car model yet, showing the loop wiring only". This is the empty-`Object3D` case of the existing scene and costs almost nothing. It is also the seam a future procedural `CarSource` would plug into.
  - **Broken** (parse error, timeout, Draco failure): the **2D view** with a notice, as today. A file that is present but bad is an error, and a real 2D frame beats floating dots.
- **Model-presence detection:** `fetch` the URL. The model is present only if `response.ok` holds **and** the first 4 bytes are the GLB magic `glTF` (0x46546C67). HTML or JSON bodies count as absent. Never infer presence from the status alone.
- **Cache-busting:** `fetch(url, { cache: 'no-cache' })`, which revalidates against nginx's default ETag (304 when unchanged), then `GLTFLoader.parseAsync(buffer, baseUrl)`. A hashed import is rejected (see REJECTED).
- **Load timeout:** 20 s in total, covering fetch and parse, with an `AbortController` on the fetch and `Promise.race` on the parse. On timeout, raise `CarSceneError('model')` and `draco.dispose()` (which terminates the workers).
- **Draco: keep it,** because the README recommends it for real CAD. Narrow the copy to `draco_wasm_wrapper.js` and `draco_decoder.wasm`, commit the Apache-2.0 licence next to them, and verify that nginx serves `.wasm` as `application/wasm`.
- **ADR 0010 and spec amendment: not on this throwaway** (REJECTED R4). They come with the adoption ticket. 0010 stays reserved for the 3D decision (0009 is logic-scylla's).

---

## MUST FIX (in order; later items assume earlier ones)

### M1. Adopt the UI view contract: page-owned selection, one detail panel, token colours, listbox badges

- **Merged finding:**
  - gltf-spec blockers 1 and 3, and majors on the Tab stops and CSS recipe duplication;
  - gltf-spec minors on the nested `<car-view>` and the storage helpers;
  - gltf-live majors on live-region chatter, Tab order, no hover info, layout shift and `selected` whitening (the panel part);
  - ui-spec Integration §3.
- **Decision:** code against `judge-ui.md`'s contract (see "Dependency on the UI contract" for rebase or shim). The parts:
  - **Selection.**
    - `CarView3dComponent` implements `LoopView`: `nodes`, `selectedId = input<string|null>(null)`, `previewId = input<string|null>(null)`, `nodeSelect = output<string|null>()`, `nodePreview = output<string|null>()`.
    - Delete the local `selectedId` signal and `select()` toggle. Click selects without toggling, Escape emits `null`, and a canvas pick emits `nodeSelect(pick())`, so an empty canvas emits `null`.
    - Pointer hover over a badge or marker emits `nodePreview`; leaving emits `null`.
    - The scene highlights `previewId ?? selectedId` through `setHighlight(id)`, which renames `setSelected`.
  - **One detail panel.** Delete `.detail`, `nodeDetail`, `SOURCE_LABEL`, the `selected` computed and the in-view hint copy. The page's `node-detail` shows the active node.
    - This removes the `aria-live` age chatter from the 3D view. The obligation moves to judge-ui: node-detail must not announce ages.
    - "Position: from the model/table" leaves the UI and goes to the load summary log (M5).
  - **Colours.**
    - Delete the `#probes` block, `styleUrls: ['../../shutdown-states.css', …]`, `resolveStateColours` and `FALLBACK_STATE_COLOURS`, along with their spec at `utils.spec.ts:124`.
    - State colours come from `readStateColours()` and are injected into the scene.
    - Scene colours (body, ghost, grid, selection ring) come from one `SCENE_COLOR_TOKENS` map (procedural's pattern), read with the same helper.
    - A jsdom fallback copies `theme.css` exactly, in one place.
  - **Badges.**
    - The `.badges` overlay becomes an Aria `ngListbox` (`orientation="horizontal"`, `[wrap]="false"`, selection follows focus) with one `ngOption [value]=id [label]=label` per loop node.
    - One Tab stop; arrows move in loop order.
    - Labels come from `nodeAriaLabel(s)`; delete the local `ariaLabel` builder.
  - **Fallback ownership.**
    - Remove the nested `<car-view>` from `car-view-3d`. Add `unavailable = output<FallbackReason>()`.
    - `car-view-switch` (name per the UI contract) catches it and renders the notice plus its single `<car-view>`, with all five contract bindings forwarded. The 3D button then shows as unavailable, with the reason as its description.
    - The switch owns the storage helpers: move `readViewMode`/`writeViewMode` out of `car-view-3d.utils.ts` and use key `argos.shutdown.carView`, keeping procedural's storage-throws tests.
  - **Styling.** The template is being rebuilt anyway, so convert it to utilities: `segmentedClasses` for the model-colours group, `touch-none` replaced per M10, and the stage height as an arbitrary `h-[clamp(…)]`, the one viewport-following exception. Delete `car-view-3d.component.css` (CONTEXT.md: stylesheet or utilities, never both; a repeated look is a recipe).
  - **Copy.** Say "loop node" in visible and ARIA text, e.g. "3D car view with shutdown loop nodes" (the CONTEXT.md "Node" ambiguity).
- **Acceptance:**
  - Clicking a 3D badge or marker highlights the same loop node in the strip and the page's `node-detail`. Selecting in the strip highlights the 3D marker and badge.
  - Hovering a badge previews it in `node-detail`.
  - Escape clears the selection, and so does a click on empty canvas.
  - Exactly one detail panel on the page, and no `aria-live` region in the 3D component.
  - From the 2D/3D toggle, one Tab enters the badges and one more Tab reaches the next control.
  - `grep -r "sd-color\|shutdown-states.css\|cssClass" components/car-view-3d components/car-view-switch` is empty.
  - The contract spec helper (`expectLoopViewContract`), or equivalent cases, passes for the 3D view with a fake scene.
  - With WebGL disabled, the switch shows the notice and one 2D view whose selection stays linked.
- **Files:**
  - `car-view-3d.component.{ts,html,spec.ts}`; delete `car-view-3d.component.css`.
  - `car-view-3d.utils.{ts,spec.ts}`, `car-scene.types.ts`, `car-scene.ts` (`setHighlight`).
  - `car-view-switch.component.{ts,html,spec.ts}`, `shutdown-page.component.{ts,html}`.

### M2. One shared positions frame and table shape (glTF-native axes)

- **Merged finding:** gltf-spec blocker 2 and its frame recommendation; proc-spec Integration §2; gltf-live major "README turns the car on its side" (root cause: the frame needs a manual 90° turn).
- **Decision:** the frame is **metres, +Y up, +Z forward (towards the nose), +X to the driver's left, origin on the ground under the rear-axle centre**.
  - This is glTF's native frame, so a Blender model facing Blender's front (−Y) exports with **no rotation**.
  - Keep the `Vec3` tuple, `NODE_POSITIONS_3D: Readonly<Record<string, Vec3>>` and `NODE_ANCHOR_PREFIX`.
  - The values are this branch's current table converted as `x' = −z, y' = y, z' = x`. Example: `glvms [0.6,0.75,0.2]` becomes `[-0.2,0.75,0.6]`.
  - Mark `em-interlock` with `// side unconfirmed (spec silent)`.
  - Update `VIEW_DIRECTIONS`:
    - `side: [1, 0.05, 0]`: from the driver's left, nose pointing left as in 2D;
    - `top: [0.001, 1, 0]`;
    - `iso: [1, 0.7, 0.8]`.
  - Rotate the generator's output to the new frame (M4).
  - The procedural branch adopts the **same file byte for byte** (see Convergence).
- **Acceptance:**
  - In the Side preset the nose points left, as in the 2D view.
  - The car and markers coincide as before (screenshot comparison in Iso and Side).
  - The positions spec asserts:
    - every loop id has a position;
    - no two nodes share a position;
    - `side-brb-l.x > 0 > side-brb-r.x`;
    - every entry lies in `x∈[−0.75,0.75], y∈[0,1.3], z∈[−0.5,2.6]`.
  - The file header documents the frame in one table, and the same file appears in both branches.
- **Files:** `shutdown-loop.positions-3d.{ts,spec.ts}`, `car-view-3d.utils.ts` (`VIEW_DIRECTIONS`), `scripts/generate-placeholder-car.mjs`, the model doc (M5).

### M3. Model loading: explicit URL, presence by magic bytes, no-cache, timeout, absent vs broken, Draco hygiene

- **Merged finding:**
  - gltf-correctness: no load timeout; constructor errors reported as "model".
  - gltf-live: loading state blank or forever.
  - gltf-spec: the unhashed URL doubles as the presence signal; no Draco narrowing or licence.
  - gltf-correctness: optional nginx 404 for assets.
- **Decision:**
  - **URL.** Add `CAR_MODEL_URL = InjectionToken<string | null>` (default `'assets/models/car.glb'`) in `car-view-3d.tokens.ts` (S7). `null` means absent.
  - **Fetching.** `createCarScene` (or a small `loadCarModel(url, draco, signal)` helper) fetches with `{ cache: 'no-cache', signal }`.
    - `!ok`, or a body whose first 4 bytes aren't `glTF`, returns `{ kind: 'absent' }`.
    - Otherwise call `parseAsync(buffer, baseUrl)`. The whole fetch-and-parse is raced against a **20 s** timeout.
    - Timeout or parse failure throws `CarSceneError('model')` and calls `draco.dispose()`.
  - **Absent model.** The scene is built with an empty `Group`: wiring only, grid at y = 0, camera fitted to the markers. The material-mode control is hidden, and a notice says "No car model yet, showing the loop wiring only".
  - **Broken model.** `unavailable('model')` (M1), which shows 2D.
  - **Error kinds.** Only the load sits inside the `'model'` try. Constructor failures become `'init'`, and the partially built scene is disposed (controls, ResizeObserver).
  - **Loading UI.** Show "Loading car model… NN %" from the response stream when `Content-Length` is known, and disable the toolbar while loading.
  - **Draco.**
    - Narrow the `angular.json` glob to `{draco_wasm_wrapper.js,draco_decoder.wasm}`.
    - Commit the Apache-2.0 licence text next to the copied files: `src/assets/draco/LICENSE`, which `src/assets` copies into `assets/draco/`.
    - Check `application/wasm` in the `client-dev` container. If nginx:alpine's `mime.types` lacks it, add a `types` block like the existing `.mjs` one.
- **Acceptance:**
  - Five model cases are covered by unit tests with a fake fetch, and three are shown live:
    1. **Valid GLB:** the car loads.
    2. **404:** wiring-only 3D with the notice.
    3. **200 with an `index.html` body:** wiring-only 3D, not 2D and not a parse error.
    4. **Truncated GLB:** 2D with the model notice.
    5. **Hung request** (`page.route` never answers): 2D with the notice within **≤ 21 s**.
  - With Draco files served as HTML, a Draco GLB falls back within the timeout and the workers are terminated (no `Worker` alive in a heap snapshot).
  - A second load after a `car.glb` swap shows the new model without a hard reload (a 200 after a 304 is visible in the network log).
  - `dist/.../assets/draco/` holds exactly the wrapper, the wasm and `LICENSE`.
  - An exception thrown in the constructor shows the `init` notice, not `model`.
- **Files:** `car-scene.ts`, `car-scene.types.ts`, `car-view-3d.utils.ts` (error kinds, notices), new `car-view-3d.tokens.ts`, `car-view-3d.component.{ts,html,spec.ts}`, `angular.json`, `src/assets/draco/LICENSE`, possibly `nginx.conf`.

### M4. Placeholder: keep it, in the new frame, with real anchors

- **Merged finding:** gltf-spec major "drop car.glb + generator" and proc-spec "neither ships its placeholder" (re-decided, see Decisions); the new judge finding that the placeholder has no anchors.
- **Decision:**
  - Keep `scripts/generate-placeholder-car.mjs` and the committed `src/assets/models/car.glb`.
  - Regenerate in the M2 frame and add **three anchors**, each a few cm off its table entry so "from the model" is visible in the load log:
    - an empty `shutdown:tsms`;
    - an exporter-style empty `Shutdown_Side_BRB_R.001`;
    - a small two-material part `shutdown:hvd`, which exercises the Group-anchor path.
  - Add `angular-client/.gitattributes` with `*.glb binary`. Do not add LFS (R2).
  - Regenerate **once** in round 2 to keep history churn to one blob.
  - Header comment: "stand-in for the throwaway only; the asset strategy for real CAD is decided at adoption (ADR 0010)".
- **Acceptance:**
  - On load the console summary reads `car.glb: 3/19 loop nodes from anchors (tsms, side-brb-r, hvd), scale ×1, unknown: none`.
  - No anchor geometry is visible.
  - The `hvd` marker sits at the part's bounding-box centre.
  - Side view: nose to the left.
- **Files:** `scripts/generate-placeholder-car.mjs`, `src/assets/models/car.glb`, `angular-client/.gitattributes`.

### M5. Model preparation: correct anchors, units and logging, testable without WebGL; README corrected and moved

- **Merged finding:**
  - gltf-correctness: anchor over-matching, multi-material anchors, the `unitScaleFor` nit, no `car-scene` tests.
  - gltf-live majors: anchor at part origin, inches, Blender steps.
  - gltf-live minor: no way to check placement.
  - gltf-spec minors: Group anchor, inches, README shipped in `dist`.
- **Decision:**
  - **Extract `prepareModel(root: Object3D, nodeIds: ReadonlySet<string>): { anchors, meshes, scale, unknownAnchors }`.** It is plain three and needs no renderer: scale, then `updateMatrixWorld`, then traverse.
    - Read **only `userData.name`**, the authored name. A node without it is never an anchor; this ends the sanitised `obj.name` false positives (`_1`, whitespace).
    - It is an anchor **only when the parsed id is in `nodeIds`**. A name with the *exact* authored `shutdown:` prefix but an unknown id is reported in `unknownAnchors` (typo detection) and is **not hidden**. `Shutdown_Button_Left` and the like stay ordinary geometry.
    - On a match, set `obj.visible = false` on the anchor of **any type**, and skip its whole subtree when collecting `meshes`.
    - Anchor position:
      - an empty (no geometry in the subtree) uses its world origin;
      - a Mesh or Group uses the world `Box3` centre;
      - log a warning when it is within 1 cm of the model origin ("anchor at model origin: set origin to geometry").
    - **Units.** Choose from `{1, 0.01, 0.001, 0.0254}` the scale that brings the largest dimension closest to 3 m, accepting only results in [1.5, 6] m and otherwise keeping 1 with a warning. The chosen scale goes in the summary.
  - **One `console.info` summary per load:** nodes from anchors, the scale, unknown anchors, nodes placed from the table.
  - **README.** Move it out of `src/assets` (it currently ships at `/assets/models/README.md`) to `docs/spec/shutdown-loop-page/car-model.md`, the input for ADR 0010. Rewrite it in Blender's own terms:
    - under M2's frame: **nose along Blender −Y (towards the viewer in Blender's Front view), up +Z, driver's left along Blender +X** (Blender (x, y, z) exports as glTF (x, z, −y));
    - move the model so the ground point under the rear-axle centre is at the world origin, then Object ▸ Apply ▸ All Transforms;
    - export glTF Binary with "+Y Up" left on;
    - table entry = `[Blender X, Blender Z, −Blender Y]`;
    - prefer empties; a part anchor needs "origin to geometry" (the bounding-box centre is used anyway);
    - export in metres or mm (inches are guessed);
    - one SolidWorks/Fusion note;
    - a "Check it" section (Side view, nose left; the console summary);
    - a troubleshooting table: on its side means axes, outside the car means units or origin, all nodes at the rear axle means part origins;
    - the cache note is dropped, since M3 covers it.
- **Acceptance:** a new `car-model.spec.ts` (jsdom, three core, no WebGL) builds trees in code and asserts:
  - an mm Group with a nested anchor under a ×2-scaled parent gives metres positions;
  - a two-primitive `shutdown:glvms` Group is hidden as a whole and its children are not in `meshes`;
  - a `Shutdown_Button_Left` mesh stays visible and is not an anchor;
  - `shutdown:tsm` is in `unknownAnchors` and stays visible;
  - a mesh anchor uses its bounding-box centre;
  - a 114-unit model gets scale 0.0254, 2900 gets 0.001, 290 gets 0.01, 2.9 gets 1.

  The doc's coordinate example round-trips the converter. `dist/` contains no `README.md` under `assets/models`.
- **Files:** new `car-model.ts` (or `prepare-model.ts`) plus spec, `car-scene.ts`, `car-view-3d.utils.{ts,spec.ts}` (`unitScaleFor`, `parseNodeAnchorName`), delete `src/assets/models/README.md`, add `docs/spec/shutdown-loop-page/car-model.md`.

### M6. Render only on visual change

- **Merged finding:** gltf-correctness major (render-on-demand defeated); gltf-spec nit (`querySelector` per badge per frame); proc-spec comparison (port `sceneSignature`).
- **Decision:**
  - Feed the scene a `computed` of `{ id, state, measured, mismatch }[]` with an `equal` function, so value, age and `now` ticks never reach three.
  - In `setStatuses`, keep per-marker keys (`shape|colour|hollow|mismatch`) and per-segment keys (`colour|emphasis|dashed`), mutating and calling `requestRender()` only on change.
  - `placeBadges` writes to a `Map<id, HTMLElement>` built when the badge list changes (`viewChildren`), with no `querySelector` per frame.
- **Acceptance:**
  - Live with the sim (or the mock panel publishing every 1 s), no interaction, 20 s: the render count is at most the number of badge state changes plus 2.
  - With no data, 0 renders.
  - A unit test on the key logic shows that a status with only `ageMs`/`value` changed produces no mutation.
- **Files:** `car-view-3d.component.ts`, `car-scene.ts`, `car-view-3d.utils.ts` (key helpers plus spec).

### M7. Status without colour: culprit glyph and name, mismatch shown, dashed dead wires, selection keeps colour

- **Merged finding:**
  - gltf-live majors: culprit by colour only (CVD), mismatch not shown.
  - gltf-live minors: selected marker turns white; no-data and downstream greys nearly identical.
  - proc-spec: dashes for "no current".
  - Spec line 111 ("must not rely on colour alone") and §5 ("mismatch … shown on that node").
- **Decision (these are the shared marker and wire semantics, see Convergence):**
  - **Badges.** Each badge shows its state glyph (`StateDisplay.icon`) beside the order number. The **suspect** badge is larger (32 px) and shows `× 12 TSMS` (`StateDisplay.short` or `LoopNode.short`), and is always labelled.
  - **No-data** carries its own glyph (e.g. `?`), and downstream keeps the dashed border, so the two near-identical greys never stand alone.
  - **Mismatch.** A "!" pip at the badge's top-right plus a ring on the marker, in the UI's mismatch token (expected `--color-warn`; the glyph is required because warn and danger are close in hue).
  - **Wires.**
    - Port procedural's `dashPieces`: segments whose leaving node's `StateDisplay.dash` is non-null (downstream-open, no-data) are dashed tubes.
    - The suspect uses `emphasis: 'strong'`.
    - Emphasis comes from `StateDisplay.emphasis`; delete the local `EMPHASIS` map once the contract lands.
  - **Highlight.** Scale ×1.7 plus a ring in `--color-fg` (a small torus or sprite facing the camera). The marker keeps its state colour; drop the emissive-white swap.
- **Acceptance:**
  - Under greyscale and deuteranopia `feColorMatrix` filters (gltf-live `s7.js`), Break at TSMS, Iso: the cause badge can be told apart by its glyph and name.
  - The BMS-latch-open mismatch scenario (`s9.js`) shows "!" pips on every mismatched node that the banner lists.
  - Downstream wires render dashed.
  - The selected cause stays orange with a ring.
  - Unit tests cover the segment `dashed` flag and the badge model (glyph, name on suspect, mismatch pip).
- **Files:** `car-view-3d.component.{ts,html}`, `car-view-3d.utils.{ts,spec.ts}` (`loopSegments` + `dashPieces`, badge model), `car-scene.ts`.

### M8. Badges stay attached to their markers

- **Merged finding:** gltf-live major (no leader lines, badges hop while orbiting); gltf-correctness nit (an unplaced node's badge sits at the stage's top-left).
- **Decision:**
  - `placeBadges(points, previous?)`:
    - places **suspects first**, with offset 0 preferred;
    - **hysteresis**: keeps a badge's previous offset while it is still clear (overlap 0), and otherwise takes the first clear spot as now.
  - Draw a **leader line** (an SVG `<line>` in the badge overlay, `stroke-fg-muted`, 1 px) from marker to badge whenever the badge's nearest edge is more than 8 px from its marker.
  - Badges default to `visibility: hidden` until placed, which removes the top-left ghosts.
- **Acceptance:**
  - Pure tests:
    - an unchanged scene keeps the same placements;
    - a 3 px camera nudge keeps every previously clear badge's offset;
    - a suspect in a cluster gets offset 0.
  - Live: the gltf-live `s3`/`s3b` orbit hop metric (more than 20 px jumps against the median motion) is 0 for at least 17 of 19 nodes. Every displaced badge has a leader. A node removed from the table shows no badge.
- **Files:** `car-view-3d.utils.{ts,spec.ts}`, `car-view-3d.component.{ts,html}`.

### M9. Robustness ported from procedural: context loss, reduced motion, probe context

- **Merged finding:** gltf-spec major (no `webglcontextlost`) and minor (reduced motion); gltf-live nit (damping ignores reduced motion); gltf-correctness nit (probe context never released).
- **Decision:**
  - Port procedural's handler:
    - `canvas` `webglcontextlost` calls `preventDefault()` and then `options.onContextLost()`;
    - the component disposes the scene and emits `unavailable('context')`;
    - a new notice reads "3D view lost its graphics context (sleep or GPU reset). Showing 2D; switch to 3D to retry."
  - Add `reducedMotion: boolean` to `CarSceneOptions` (from `matchMedia`, read at start), with `controls.enableDamping = !reducedMotion`.
  - `isWebGLAvailable` calls `getExtension('WEBGL_lose_context')?.loseContext()` on its probe, and the result is cached per page load.
- **Acceptance:**
  - Playwright `WEBGL_lose_context.loseContext()` on the scene's context shows 2D with the notice within 1 s, with no console errors. The disposed scene has no rAF running.
  - Toggling back to 3D works.
  - With `prefers-reduced-motion: reduce`, badge motion after mouse release is 0 px.
  - After 20 toggles, created contexts minus lost contexts ≤ 1.
- **Files:** `car-scene.ts`, `car-scene.types.ts`, `car-view-3d.component.ts`, `car-view-3d.utils.ts` (`FallbackReason` + notice).

### M10. Touch: don't capture page scroll on phones

- **Merged finding:** gltf-live major (canvas traps scroll; the hint is mouse-only).
- **Decision:**
  - On `(pointer: coarse)`:
    - after constructing OrbitControls, set **`canvas.style.touchAction = 'pan-y'` inline**, since OrbitControls' own inline `none` beats CSS;
    - set `controls.touches = { ONE: null, TWO: TOUCH.DOLLY_ROTATE }`, so one finger scrolls the page and two fingers rotate and zoom.
  - Hint copy depends on the pointer type: "Two fingers to rotate and zoom" on touch, "Drag to orbit, scroll to zoom, right-drag to pan" on mouse. After M1 the hint lives in the stage or toolbar, not in a detail panel.
- **Acceptance:**
  - With Playwright `hasTouch`/`isMobile` at 390×844, `getComputedStyle(canvas).touchAction === 'pan-y'`, and a CDP `Input.dispatchTouchEvent` one-finger vertical swipe over the canvas changes `scrollY` and not the camera.
  - A two-finger pinch changes the camera distance.
  - On desktop, behaviour is unchanged.
- **Files:** `car-scene.ts`, `car-view-3d.component.{ts,html}`.

---

## SHOULD FIX (round 2 if time allows; otherwise carry to round 3)

- **S1. Resize and DPR.**
  - In `resize()`, re-run `setView(currentPreset)` unless the user has orbited since the last preset (track with OrbitControls `start`).
  - Re-read `devicePixelRatio`, capped at 2, and call `setPixelRatio` when it changed.
  - Acceptance: the Side-view 1360×520 → 360×280 corner test leaves 0 of 8 corners out (gltf-correctness).
- **S2. Progressive load.** Build the wiring-only scene immediately (the M3 absent path), then add the car and refit when parsing completes. This removes the blank loading box and unifies two code paths. If it is done, M3's percentage text can sit over the live wiring.
- **S3. Camera limits and toolbar.**
  - Limits: `maxPolarAngle ≈ 0.48π`, `controls.target` clamped to bounds, `minDistance ≈ 0.8·radius`, `maxDistance ≈ 2×` the fit distance.
  - Presets become momentary plain buttons (`buttonClasses`, no pressed state), and the hint says "pick a view to reset".
  - Visible group labels "View" and "Model".
  - Rename the modes CAD/Theme/Ghost to **Original / Solid / See-through**.
- **S4. Opaque modes.** In Original and Solid, draw markers and wires over the body (`depthTest: false`, `renderOrder` above the model) so the cause stays visible on a red CAD body. If that looks wrong, drop "Solid", since See-through does the job.
- **S5. Off-origin and framing.**
  - Grid at `bounds.min.y`.
  - When no anchors matched and more than half the table positions fall outside the model's bounds, log a warning naming `car-model.md`.
  - When a model is present, fit the camera to the model's bounds alone (markers are expected inside), which also tightens the Iso framing.
- **S6. Persist the model-colour mode** with the switch's storage helpers (key `argos.shutdown.carView.material`). The camera preset is not persisted, since it is momentary.
- **S7. `car-view-3d.tokens.ts`.** Move `CAR_SCENE_LOADER` and `WEBGL_SUPPORT` out of the component file (procedural's layout, so the switch spec doesn't import the component), and add `CAR_MODEL_URL` there.
- **S8. Cleanups.**
  - Remove `NgZone`/`runOutsideAngular` (the app is zoneless) and correct the "outside Angular" comments.
  - Import `DOCUMENT` from `@angular/core`.
  - Drop the redundant static `class="badge"`.
- **S9. Fallback notice as a callout.** Warn icon, `role="status"`. Copy: "3D view unavailable (no WebGL). Showing 2D." The file path goes in the console only.
- **S10. Stage height.** Cap it near 50vh on short viewports so the loop strip, "the main diagnostic read", stays above the fold at 1280×720: `h-[clamp(240px,60vw,min(50vh,480px))]`.
- **S11. nginx.** Add `location /assets/ { try_files $uri =404; }`, so a missing asset gives a 404 instead of `index.html`. It is defence in depth; M3 is the real check. Check it doesn't break the basemap or the worker served at `/`.
- **S12. One-shot suspect pulse.** Optional: about 1 s when a node *becomes* suspect, off under reduced motion, then render-on-demand resumes. Never procedural's continuous 60 fps pulse.

## REJECTED (with reason)

- **R1. "Drop `car.glb` and the generator now"** (gltf-spec, proc-spec).
  - The blob is already in `origin`'s history, so deleting it in a new commit frees nothing.
  - The branch's purpose is to demo the glTF path, which needs a real GLB.
  - Using procedural's car instead would merge the approaches against the user's constraint.
  - The underlying concerns are met by M3 (presence detection and the absent state) and M4 (the stand-in is labelled and anchored). The real asset strategy is an adoption and ADR 0010 decision.
- **R2. Git LFS or a basemap-style fetch script now.** CI, Docker and `run-local` would all need LFS or fetch steps for a 166 kB throwaway stand-in. Decide in ADR 0010 when real CAD exists. `.gitattributes *.glb binary` (M4) is the only change now.
- **R3. Hashed model URL** (an esbuild `.glb` file loader plus `import`). `no-cache` revalidation (M3) gives freshness with no build config change. Hashing would also bind the model to a code import, against the "save over `car.glb`" CAD workflow.
- **R4. ADR 0010 and a spec amendment on this branch.**
  - Two competing throwaways would each claim 0010 and each pre-decide the approach.
  - The decision record belongs to the adoption ticket. Its inputs are the round-2 `car-model.md` (M5) and the comparison tables in gltf-spec and proc-spec.
  - `CLAUDE.md`'s "explain reasoning before architectural changes" is met for a throwaway by its spike or PR notes.
  - Flagged: the spec still says "option A, chosen", and any adoption must amend it.
- **R5. Collapsing clustered badges ("15–19")** and **hiding closed badges on phones.** Both interact with the listbox (every loop node must stay an option). Do M8's leaders and hysteresis first, then re-measure at 390 px.
- **R6. Wire waypoint anchors** (`shutdown-wire:<from>-<to>.<n>`). YAGNI until a real CAD harness exists. M7's dashed and muted wires plus S4 handle the visual problem.
- **R7. Default to 2D while the placeholder is in place.** The default view is an adoption and ADR decision (the UI contract says so too). This throwaway exists to show 3D.
- **R8. Ghost-mode `EdgesGeometry` outlines.** Cosmetic, and a real CAD model changes the look entirely.
- **R9. Keyboard orbit (`listenToKeyEvents`).** It conflicts with the listbox's arrow keys. The presets cover keyboard users.
- **R10. The NG0100 console flood.** It comes from `MessagesPerSecondComponent` and predates this branch. Out of scope; offer it as a ticket via `create-ticket`.
- **R11. Linting or typing the generator.** It is a throwaway dev tool, and adoption decides whether it survives at all (likely replaced by a `CarSource`).
- **R12. Dependabot grouping of `three`/`@types/three`.** Do it with adoption, not on a throwaway.
- **R13. A special case for ground planes over 50 m.** M5's candidate-scale rule plus the summary log make it visible. No dedicated handling.
- **R14. Camera fly-to on selection.** Not requested and not needed for the diagnostic read.
- **R15. The "`ng serve` returns index.html 200" part of gltf-spec's finding.** It is incorrect (the dev server returns 404 `text/html`). The finding's fix still stands for nginx and is in M3.

---

## Convergence with procedural (the branches stay separate)

**Identical in both branches.** Byte-identical where noted, so a later adoption is a pick, not a merge:

1. **`shutdown-loop.positions-3d.ts`** (byte-identical, M2):
   - the frame: metres, +Y up, +Z forward, +X driver's left, origin under the rear-axle centre;
   - `Vec3` tuples, `NODE_POSITIONS_3D`, `NODE_ANCHOR_PREFIX` (unused by procedural but harmless);
   - this branch's converted values, with `em-interlock` flagged as unconfirmed;
   - the same positions-spec invariants.

   Procedural places its car group in this frame (`rotation.y`/`position`), adopts these values, and drops its `CarPoint3d` and private frame. **This needs judge-proc to agree.** If judge-proc picks a different frame, the coordinator resolves it once, and both branches use the result.
2. **Marker and wire semantics** (M7):
   - colour from `readStateColours()[state]`;
   - shapes `sphere|octahedron|cone|box` for closed, suspect, downstream and no-data (procedural renames `cube` to `box`);
   - wireframe means unmeasured;
   - a segment takes the state of the node it leaves; emphasis from `StateDisplay.emphasis`; dashed when `StateDisplay.dash` is set, using `dashPieces`;
   - highlight `previewId ?? selectedId` = scale plus a `--color-fg` ring, never recolouring;
   - mismatch = ring plus "!" pip;
   - the suspect badge shows glyph plus short name.
3. **Scene contract** `car-scene.types.ts` (this branch's, extended):
   - `createCarScene(options): Promise<CarScene>`;
   - options include `reducedMotion`, `onContextLost`, `onFrame(ScreenPoint[])`;
   - `CarScene` = `setStatuses`, `setView`, `setHighlight`, `pick`, `dispose`.

   Procedural moves to the async factory and `onFrame` so it can carry the HTML badge listbox.
4. **`car-view-3d.tokens.ts`** with `CAR_SCENE_LOADER` (returning the module) and `WEBGL_SUPPORT`; glTF adds `CAR_MODEL_URL`.
5. **Switch.** One name from the UI contract (`car-view-switch`), key `argos.shutdown.carView`, helpers in the switch, `unavailable(reason)` handling, and the single 2D fallback with all five bindings.
6. **Render-on-demand with change keys** (M6). Procedural keeps `sceneSignature` and drops its continuous pulse in favour of S12's one-shot.

**Port from procedural into glTF** (all in this round):
- context-loss fallback (M9);
- reduced motion (M9);
- dashed wires (M7);
- the theme-token map pattern for scene colours (M1);
- `sceneSignature`-style change detection (M6);
- the tokens-file layout (S7);
- the storage key, helpers and storage-throws tests (M1).

**Do not port:** the continuous pulse, canvas sprite labels, the ring sprite as the only highlight, raycast picking, fixed `CAMERA_PRESETS`, the info overlay, or the separate node toolbar.

**Recommend procedural ports from glTF** (for judge-proc):
- `fitDistanceToPoints` (auto-fit);
- screen-space `nearestPoint` picking (pure, tested);
- the HTML badge overlay with `placeBadges` (with M8's suspect-first, hysteresis and leaders) as the listbox carrier for 3D;
- the three-free `car-scene.types.ts` contract;
- reason-specific `FALLBACK_NOTICES`;
- the dispose discipline (verified leak-free here).

Not anchors, GLTFLoader, Draco or material modes: those are glTF's differentiator.

## Dependency on the UI contract (`judge-ui.md`)

M1 and M7 code against the contract judge-ui defines. I assumed:
- `ShutdownSelectionStore` (`selectedId`, `previewId`, `activeId`, `select`, `preview`), page-provided;
- a `LoopView` interface;
- `StateDisplay.{token, dash, emphasis, icon, short}`;
- `readStateColours()`, `nodeAriaLabel()`;
- `node-detail` as the only panel;
- the Aria `ngListbox` pattern;
- the `car-view-switch` name.

- **Sequencing:**
  - The first round-2 step is to rebase this branch onto `throwaway-shutdown-ui`'s contract commit, if it exists when round 2 starts. That is a rebase onto the UI branch, not a merge of the two 3D approaches.
  - If it doesn't exist yet, implement against **one shim file** (`components/car-view-3d/ui-contract.shim.ts`) that exports exactly the contract's names and signatures. Leave `shutdown-states.css` and `NODE_STATE_DISPLAY` untouched, and delete the shim at rebase.
  - M2–M6 and M8–M10 don't depend on the contract and can start immediately.
- **What I need from judge-ui** (flag if its contract differs):
  1. `node-detail` must not put the reading age in a live region. The 3D view's chatter finding moves there.
  2. The mismatch colour token used in 2D and the strip. I assumed `--color-warn`. If warn is mismatch, procedural's HV highlight must use another token (`--color-secondary-border`), not warn.
  3. `StateDisplay.icon` glyphs that work at 12–14 px in a 24 px badge, with no-data distinct from downstream.
  4. Whether `node-detail` takes an optional extra row. If not, "Position: from the model/table" stays console-only (M5 summary), which is my default.
  5. Contract output names (`nodeSelect` against `loopNodeSelect`, per ui-spec's naming major). M1 follows whatever judge-ui decides.
