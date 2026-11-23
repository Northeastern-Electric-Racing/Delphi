# Round 2 review: `throwaway-shutdown-3d-gltf`, conventions, architecture and repo hygiene

Reviewer: gltf-spec (round 2). Code: `worktrees/argos/throwaway-shutdown-3d-gltf` at `40739def`. The diff reviewed is `origin/throwaway-shutdown-ui...HEAD` (34 files, +3957/−10). Procedural was compared at `4df0fb6b`. Scratch work is in `scratchpad/r2rev-gltf-spec/`. Nothing in the worktrees was edited.

Checks I ran:
- `ng build`, output to scratch;
- `ng test --watch=false`: 139 files, 1077/1077 pass;
- `prettier --check` (src, the generator, `car-model.md`, `nginx.conf`) and `ng lint`: both clean;
- `cmp` of every changed file against procedural;
- the generator rerun in scratch;
- nginx served the built `dist` from the `argos-client:develop` image (nginx 1.31.6) on a throwaway port, once with the branch's `nginx.conf` and once with the base's;
- Playwright on :4203 and :4202.

Screenshots are in `pictures/throwaway-shutdown-3d-gltf/review-r2/` (`spec-*`).

## Round-1 MUST status (items under this lens)

| Item | Status | Evidence |
|---|---|---|
| M1, styling and structure part: utilities only, delete `car-view-3d.component.css`, `segmentedClasses` for the model group, stage `h-[clamp(…)]`, "loop node" copy, switch owns storage (`argos.shutdown.carView`) | VERIFIED-FIXED | No `.css` in `car-view-3d/`. There is no `styleUrl`, and nothing matches `sd-color\|shutdown-states.css\|cssClass\|NgZone` in `car-view-3d/` or `car-view-mode/`. `segmentedClasses.list/item` is at `car-view-3d.component.ts:116-117`. The aria-label is "3D car view with shutdown loop nodes…" (`:121`). `car-view-mode.component.ts` (byte-identical to procedural) owns the key and the helpers, with storage-throws tests. The badge listbox part was superseded by the round-2 UI contract (pointer-only badges, the strip is the keyboard path). That is outside this lens. |
| M2: one shared positions frame and table, byte-identical | VERIFIED-FIXED | `shutdown-loop.positions-3d.{ts,spec.ts}` are identical (`cmp`) to procedural. Side view checked live (`spec-side-view-placeholder.png`). |
| M3, hygiene part: `CAR_MODEL_URL` token, Draco narrowed, Apache-2.0 licence, `.wasm` MIME checked, `dist/assets/draco` = wrapper + wasm + LICENSE | VERIFIED-FIXED (one nit, N7) | `angular.json` glob is `{draco_wasm_wrapper.js,draco_decoder.wasm}`. The built `dist/browser/assets/draco/` holds exactly `LICENSE`, `draco_decoder.wasm` and `draco_wasm_wrapper.js`. `LICENSE` has an attribution preamble plus the full Apache-2.0 text. A plain GLB loads no Draco file (network log: only `car-scene-*.js` and `car.glb`). The token sits in its own `car-model-url.token.ts`, not in `tokens.ts` as S7 said. That deviation is deliberate and justified (see A1). |
| M4: keep the placeholder and its generator, regenerate once in the new frame with 3 anchors, `.gitattributes *.glb binary`, header comment | VERIFIED-FIXED | Judge-gltf said KEEP (R1), and the branch followed it. `car.glb` has exactly two blobs in history (`e4609fca` from round 1, `bef9349f` from round 2). `git check-attr` gives `binary: set, diff/merge/text: unset`. The generator rerun in scratch is byte-identical to the committed 169 384-byte file, twice, so it is deterministic. Live console line: `car.glb: 3/19 loop nodes from anchors (side-brb-r, tsms, hvd), scale ×1, unknown: none`. The header reads "Stand-in for the throwaway only; … decided at adoption (ADR 0010)". |
| M5: `prepareModel` extracted and tested without WebGL; README moved out of `src/assets` to `docs/spec/shutdown-loop-page/car-model.md` and rewritten in Blender terms | PARTIAL | `car-model.ts` is three core only, and `car-model.spec.ts` covers mm plus a nested ×2 parent, a multi-material Group anchor, the mesh bbox centre, `Shutdown_Side_BRB_R.001`, `Shutdown_Button_Left` left alone, the `shutdown:tsm` typo, unnamed objects, origin warning and duplicates. `unitScaleFor` cases (114→0.0254, 2900→0.001 …) are at `car-view-3d.utils.spec.ts:87-100`. There is no `README.md` under `dist/assets/models`. **But** the acceptance "the doc's coordinate example round-trips the converter" fails: see F4. |
| S7: tokens file | VERIFIED-FIXED | `car-view-3d.tokens.ts` is byte-identical to procedural. |
| S8: drop NgZone, `DOCUMENT` from core, drop the static `class="badge"` | VERIFIED-FIXED | `component.ts:7`; none of the three remain. |
| S10: stage height `h-[clamp(240px,60vw,min(50vh,480px))]` | VERIFIED-FIXED | `component.html:3`. Allowed (see A2). Procedural uses different numbers (N4). |
| S11: nginx `/assets/` 404 | VERIFIED-FIXED | With the branch conf, a missing `/assets/models/nope.glb` returns **404**. With the base conf it returned **200 text/html**. `/`, `/shutdown` (SPA), `/assets/env.js`, `/maplibre-gl-worker.mjs` (`application/javascript`) and `car.glb` (with ETag) are unchanged. |
| R4: no ADR 0010 on this branch | Followed, but it conflicts with judge-proc S10 | See F3. |

## Answers to the questions asked

**A1. `car-model-url.token.ts` split out to keep `tokens.ts` byte-identical: good idea or smell?** It's a good idea. The judges disagreed on this point: judge-gltf S7 said "glTF adds `CAR_MODEL_URL` there", and judge-proc lists `tokens.ts` as byte-identical. A separate file is the cheapest way to honour both. A later combine then picks `tokens.ts` from either branch and keeps this file only if glTF survives. The naming follows the repo (`.token.ts`/`.tokens.ts` both describe the content).

The real smell is elsewhere. The byte-identical `tokens.ts` types `CAR_SCENE_LOADER` as `() => Promise<CarSceneFactory>`, and `CarSceneFactory` is declared in the **non-identical** `car-scene.types.ts`:
- glTF has `(o) => Promise<CarScene>` (`car-scene.types.ts:50`);
- procedural has `(o) => CarScene` (`procedural car-scene.types.ts:52`).

The file is identical, but its contract is not. The same goes for `isWebGLAvailable`, which `tokens.ts` imports from the non-identical `car-view-3d.utils.ts`. See F5.

**A2. Is `h-[clamp(240px,60vw,min(50vh,480px))]` allowed?** Yes, for two reasons:
- The CONTEXT.md sentence "an arbitrary size only when it must follow the viewport" is about **font sizes** ("Font sizes come from the type scale; …"). The arbitrary-value bans are on colours and `!`, not on layout lengths, and the repo already uses `h-[90vh]`, `w-[min(24rem,calc(100vw-32px))]` and `max-h-[90vh]`.
- Even read broadly, this height does follow the viewport (vw/vh).

The branch's real arbitrary-size violation is `text-[10px]` (F2).

**A3. Structure (`car-model.ts`, `car-scene.ts`, `loadCarModel`, `RenderScheduler`).** The structure is sound. Each pure piece can be tested without WebGL and is tested:
- `prepareModel` uses three core only;
- `loadCarModel` takes no three and an injected parser, and is tested with a fake fetch, covering 404, SPA 200, truncated GLB, a hung fetch, a hung parse, progress and abort;
- `RenderScheduler` takes an injected rAF.

`car-scene.ts` (543 lines) keeps only the renderer-bound code, behind `car-scene.types.ts`, so the component and its spec never import three. Two nits:
- `loadCarModel(url, parse, opts, onFail)` puts `onFail` positionally after an options bag. It belongs in `opts`.
- `RenderScheduler` duplicates procedural's `RenderLoop` (in its `utils.ts`) under a different name. That is a convergence candidate (N3).

**A4. Test quality.** Good:
- the behaviour-named cases map one-to-one to the judge's acceptance lists;
- fakes are used instead of WebGL;
- a test shows that a value- or age-only tick never reaches the scene;
- "reports no WebGL without loading three" guards the lazy boundary.

The gap: no test covers focus after a fallback (F1), and procedural's page spec has one.

**A5. Bundle.** Verified by a production build:
- three is only in the lazy `car-scene` chunk: **671.6 kB raw, 140.25 kB transfer**;
- no other emitted chunk contains `WebGLRenderer`, `OrbitControls` or `REVISION`;
- the initial total is 193.5 kB transfer;
- only `car-model.ts`, `car-scene.ts` and two specs import `three`.

The Draco decoder (192 kB wasm) is fetched only for a Draco GLB, and the placeholder isn't one. Procedural's ADR text says "about 125 kB", which is low for glTF (+GLTFLoader/DRACOLoader); see F3.

**A6. Repo hygiene.** `car.glb` is kept, regenerated once and reproducible (M4 above). `.gitattributes` works and is scoped to `angular-client/`, next to the only binary, which is fine. The Draco LICENSE and the angular.json glob are correct.

The **nginx.conf changes are in scope, not creep, but half is redundant**:
- the `/assets/` 404 was asked for (S11) and verified harmless to the SPA, env.js, worker and basemap paths (static files keep Range support);
- the `.wasm` block is a no-op, because nginx:alpine's `mime.types` already maps `application/wasm` (N7).

The `/assets/` rule changes production behaviour for every asset (for example a missing `basemap.pmtiles` now returns 404 instead of `index.html`), which is better but worth one line in the PR or ADR.

**A7. Docs placement.** `docs/spec/shutdown-loop-page/car-model.md` is right:
- it is feature-scoped, sits next to `spec.md` and is out of `dist`;
- the runtime warning (`car-scene.ts:396`), `car-model.ts:5` and the generator point at it.

It is not linked from `spec.md`, because `spec.md` is unchanged here (F3).

**A8. ADR.** See F3. My recommendation is to copy procedural's ADR 0010 and spec amendment into this branch byte for byte, after two edits to the shared text.

**A9. Better base if the team later combines them: glTF.** The reasons:
- It already has the generality a combined view needs:
  - the async `Promise<CarScene>` factory, which is judge-gltf's shared contract and which procedural never adopted;
  - `loadModel` with an explicit **absent** state that draws the wiring alone. That is exactly the slot where procedural's self-contained `buildCar(colours): CarModel` (`procedural-car.ts:114`) would go through `addModel(Object3D, name)` (`car-scene.ts:222`) as a `CarSource`;
  - the superset `FallbackReason` (`'model'`);
  - `CAR_MODEL_URL` with null meaning "no model";
  - the touch, camera-limit and resize work.
- Porting procedural into glTF is a few files: `procedural-car.ts` and its spec, the ADR and spec amendment, and the page focus fix (F1).
- The reverse, porting glTF into procedural, means re-plumbing the factory as async and adding model loading, the token, the absent and broken states, prepareModel, Draco, nginx, the GLB and the generator.
- Shared files are already identical: positions, projection, tokens, `car-view-mode`, package.json and the lockfile.

Caveat: if adoption drops glTF entirely, the GLB, generator, Draco, `.gitattributes` and nginx `.wasm` block go with it. Adoption is a squash, so history doesn't matter.

## New findings

### F1. minor: fallback from 3D drops keyboard focus to `<body>` (CONTEXT.md: "Move focus after an action with `injectFocusAfterRender` … so it never drops to `<body>`")
- **Where:** `shutdown-page.component.ts`, `onCarUnavailable`, and the `car` `<section>` in `shutdown-page.component.html`. Both are shared page files, and procedural has diverged from them to fix this.
- **Steps:** open http://localhost:4203/shutdown at 1280×800 with `argos.shutdown.carView=3d`, focus the 3D **Side** button, then run `WEBGL_lose_context.loseContext()` on the canvas. The same applies to a model that fails or times out while a toolbar button has focus, because the toolbar is enabled during loading.
- **Result:**
  - glTF: `document.activeElement` is `BODY` after the fallback.
  - procedural (:4202): `SECTION` (it keeps `#carSection tabindex="-1"` and uses `injectFocusAfterRender({ preventScroll: true })` when the section had focus).
  - Script: `r2rev-gltf-spec/focus.cjs`. Screenshot: `spec-focus-after-context-loss-4203.png`.
- **Fix:** take procedural's version of `shutdown-page.component.{ts,html}` as is (the diff is only this), plus its page-spec case. The page files then become byte-identical across the two branches.

### F2. minor: arbitrary font size, and a text "!" used as an icon, on the mismatch pip
- **Where:** `car-view-3d.component.html:38-41`: `<span class="… text-[10px] leading-none font-black …">!</span>`.
- **Issue:** the arbitrary size `text-[10px]` doesn't follow the viewport. CONTEXT.md says "Font sizes come from the type scale; an arbitrary size only when it must follow the viewport", and the scale has `text-badge` (0.7 rem) for this. The glyph is also a typed character where the convention is "Icons … `<ui-icon>` only". Procedural uses `<ui-icon name="priority_high" size="xs" />` for the same pip.
- **Fix:** use `<ui-icon name="priority_high" …/>` inside the `size-3.5` warn disc, as procedural does, which removes `text-[10px]` too. Better still, make the pip one shared snippet in both 3D branches.

### F3. minor (process): no ADR 0010 on glTF, while procedural's ADR claims to be on both branches; the judges conflict
- **Facts:**
  - judge-gltf R4 says no ADR or spec amendment on this branch, and the branch followed it.
  - judge-proc S10 says to write ADR 0010 (Proposed) and the spec amendment "byte-identical into both 3D branches … required before either branch becomes a ticket or PR". Procedural did that.
  - Its ADR's status line reads "written on the throwaway branches `throwaway-shutdown-3d-procedural` and `throwaway-shutdown-3d-gltf`". That is false today.
  - glTF's `car-model.md` says the GLB asset strategy (git, LFS or fetched) "is for ADR 0010", but procedural's 0010 text doesn't mention the asset question.
  - `spec.md` here still says "option A (chosen)" with no option D, so `car-model.md` isn't reachable from the spec.
- **Why the conflict resolves toward copying:** R4's concern was two branches each claiming 0010 and each pre-deciding the approach. Procedural's text is approach-neutral ("Where the car comes from: under evaluation … The adoption ticket picks one, or both behind one `CarSource` seam"). An identical copy in both claims nothing extra.
- **Recommendation:** copy `docs/adr/0010-angular-client-three-js-3d-car-view.md` and the one-line `spec.md` option D into glTF byte for byte, after two edits made in **both** branches:
  1. In Consequences, change "About 125 kB (transfer)" to "About 125–140 kB (transfer; the glTF source adds its loaders)". Measured here: 140.25 kB.
  2. Under "Where the car comes from", add one sentence: "For glTF, where the model file lives (git, LFS, or fetched like the basemap) and whether Draco ships are decided with the source; see `docs/spec/shutdown-loop-page/car-model.md` on the glTF branch."

  Also link `car-model.md` from the option D line, or leave it as the ADR's job.
- **Status:** Proposed, both branches. This needs the coordinator's ruling, since it overrides judge-gltf R4.

### F4. minor: `car-model.md`'s worked coordinate example doesn't match the table (fails M5's "round-trips the converter")
- **Where:** `docs/spec/shutdown-loop-page/car-model.md`, "The frame": "TSMS sits in Blender at X −0.20, Y −0.66, Z 0.75, which is the table's `tsms: [-0.2, 0.75, 0.66]`".
- **Issue:** the table holds `tsms: [-0.2, 0.75, 0.69]` (`shutdown-loop.positions-3d.ts:39`). A CAD author who checks the rule against the example finds the numbers don't agree. That undermines the one paragraph meant to stop the "car on its side" mistake.
- **Fix:** use Blender Y −0.69 and `[-0.2, 0.75, 0.69]`. Optionally match the example console line's anchor order to the real one, `(side-brb-r, tsms, hvd)`.

### F5. minor (convergence): the byte-identical `tokens.ts` sits on non-identical contracts
- **Where:**
  - `car-view-3d.tokens.ts`, identical in both, imports `CarSceneFactory` from `car-scene.types.ts`. That type is `Promise<CarScene>` here and synchronous `CarScene` in procedural.
  - It also imports `isWebGLAvailable` from `car-view-3d.utils.ts`. That function is identical in both (md5 match), but it lives in a non-shared file.
  - `dashPieces` is also identical but sits in each branch's own utils.
- **Failure scenario:** a combine that picks either branch's `tokens.ts` type-checks against whichever `car-scene.types.ts` comes with it. The "shared" seam hides the one contract difference the judges said to remove (judge-gltf Convergence 3: both use the async factory).
- **Fix:**
  - procedural adopts `Promise<CarScene>`. That is judge-proc's side, so flag it there.
  - Move `isWebGLAvailable` (and `dashPieces`) into a shared file, for example `car-view-3d.projection.ts` or `tokens.ts` itself, so every symbol a shared file imports is itself shared.

### Nits
- **N1. Diverging names for shared semantics.** These names differ between the two 3D branches and will collide when combined, and the page imports both through `car-view-3d.utils`:
  - `FallbackReason` is `'context'` here and `'context-lost'` in procedural, which also lacks `'model'`;
  - `MARKER_SHAPES` here, `MARKER_SHAPE` in procedural;
  - `RenderScheduler` here, `RenderLoop` in procedural.

  Pick glTF's `FallbackReason` (judge-proc: "port `FallbackReason` … from glTF").
- **N2. OrbitControls import path.** It is `three/examples/jsm/controls/OrbitControls.js` here (`car-scene.ts:28-30`) and `three/addons/controls/OrbitControls.js` in procedural. `three/addons/*` is three's documented alias. Use one, preferably `addons`, for all three examples imports.
- **N3. Badge glyph.** `<ui-icon [name]="b.icon">` with `BadgeModel.icon` re-implements the existing `<status-glyph [state] [size]>` (`components/status-glyph/`), which the strip, the 2D car and node-detail all use. Procedural does the same. Use `status-glyph` in both and drop `icon` from `BadgeModel`.
- **N4. Stage height.** It is `h-[clamp(240px,60vw,min(50vh,480px))]` with a border here, and `h-[clamp(240px,56vw,min(52vh,480px))]` without a border in procedural. The same component slot has two "one arbitrary size" values. Align them, glTF's numbers being S10's.
- **N5. Material-mode storage helpers.** `readMaterialMode/writeMaterialMode(storage: () => Storage)` take a thunk, while the switch's `readCarViewMode/writeCarViewMode(storage = globalThis.localStorage)` take the storage. S6 said to use the switch's helpers. Match the signature, or generalise the switch helper by key.
- **N6. Method call in the template.** `[class]="badgeClass(b)"` is called from the template for every badge on every check. Make it part of a `computed` badge list, as procedural precomputes `b.classes`.
- **N7. Redundant nginx `.wasm` block.** `nginx.conf` `location ~ \.wasm$ { types { application/wasm wasm; } }` does nothing: nginx 1.31.6 `mime.types:55` already has `application/wasm wasm;`, and the base conf serves `draco_decoder.wasm` as `application/wasm`. Drop it (judge M3: "If nginx:alpine's mime.types lacks it"). Keep the `/assets/` block.
- **N8. Draco never exercised.** Draco ships (wasm, LICENSE, glob) but nothing committed exercises it, since the placeholder isn't Draco-compressed. Either note it in `car-model.md` ("the stand-in is uncompressed; Draco is untested end to end") or leave the Draco decision to the ADR with the asset question (F3).
