# Judge, round 1: `throwaway-shutdown-3d-procedural`

Inputs: `proc-correctness.md`, `proc-live.md` and `proc-spec.md`; the integration sections of `gltf-spec.md` and `ui-spec.md` (including the proposed shared contract); the code at 78b75be2 compared with `origin/shutdown-loop-page`; the sibling `throwaway-shutdown-3d-gltf` at 69564d46; and `throwaway-shutdown-ui` at bf6f70ae (the 2D car view and the strip).
Spot checks are in `/tmp/claude-0/-home-user-Delphi/6e25b80b-05af-58e5-9050-4f2faa446aec/scratchpad/judge-proc/`: `pick.mjs` (picking), `cvd.py` (colour-vision simulation). No worktree was edited.
Paths below are relative to `angular-client/src/pages/shutdown-page/`, and `C3D/` stands for `components/car-view-3d/`.

## Verdict

**Needs work. Round 2 is required, and the approach is sound.** The foundations are good and stay:
- three ships only in the lazy chunk (125 kB transfer), and the initial bundle didn't grow;
- disposal is correct, and no heap or listener leaks were found;
- a lost WebGL context falls back to 2D;
- reduced motion is honoured;
- `sceneSignature` skips rebuilds when only ages tick;
- the procedural car is theme-native and reads as an FSAE car.

What fails is the page's one job. In some break locations and presets the culprit can't be seen (blocker): canvas labels drawn with `depthTest:false` cover the cause marker. The red wire also points away from the culprit, picking can open the wrong loop node, and the view burns CPU continuously whenever the loop is open (which is most of the time). Beyond that, the view ignores the UI branch's selection, colour and styling contract, so it won't compile once rebased on that branch.

The user's constraint holds: this branch stays a separate throwaway from the glTF one. Round 2 converges the two on shared pieces (frame, table shape, pure projection helpers, wire semantics, contract) without merging them.

### What I confirmed in code or scratch

- **Picking (confirmed).** Projecting `NODE_POSITIONS_3D` through `CAMERA_PRESETS` at 1000×560 and raycasting the branch's 0.066 m proxies gives these wrong picks:
  - Iso: `ts-plus→hvd`, `airs→hvd`;
  - Side: `cockpit-brb→inertia`;
  - Top: `ts-minus/ts-plus→bms-latch`, `airs→bspd-latch`.

  A screen-space nearest pick (glTF's `nearestPoint`, 16 px reach, depth tie-break) gets **0 wrong in all three presets**. The smallest on-screen separations are 11.2 px (hvd/ts-plus, Iso), 14.8 px (inertia/cockpit-brb, Side) and **4.1 px** (bspd-latch/airs, Top). Top is therefore close to coincident, and that is a positions problem (see S8).
- **Pulse loop (confirmed).** `car-scene.ts:232-237,251`: `pulse()` returns true whenever there is a suspect, so `tick` requests a frame every vsync. The doc comment at `:68-70` says the opposite.
- **Wire colouring (confirmed).** `car-view-3d.model.ts:75` sets `state: a.state`, so a segment takes the state of the node it leaves. glTF (`loopSegments`), the UI branch's 2D `car-view.component.ts:78-95` and the strip's `connector` all use the same "upstream" rule.
- **Colour-vision safety (confirmed).** Simulated deuteranopia, using CIELAB ΔE (the perceived colour difference; under about 10 the two colours look nearly the same):

  | Pair | Colours | ΔE, normal vision | ΔE, deuteranopia |
  |---|---|---|---|
  | This branch's closed / suspect | `#2fd35a` / `#ff4d4d` | 133 | **9.2** (near-identical) |
  | UI tokens success / danger | `#4ade80` / `#fb923c` | 97 | 31.6 (protanopia 21.5) |

  The UI tokens are better, but the luminance ratio stays at 1.1–1.7, so a non-colour cue is still required. Downstream (`#8a8a8a`) against no-data (`#a3a3a3`) is ΔE 9.5 under every simulation, so a dash pattern has to tell them apart.
- **WebGL probe (confirmed).** `WEBGL_SUPPORT`'s factory returns `() => isWebGLAvailable()`, so every component construction creates a new context and never releases it (`C3D/car-view-3d.tokens.ts:11-14`, `.model.ts:151-158`).

## Wire colouring: decision

`computeLoopStatus`'s own contract says "each reading is the loop voltage just after its node". The break node F (the last suspect) reads 0, so **the wire after F is dead by definition**. Under the current upstream rule, used by all three branches, the segment F→next is red. That is the long red line from Cockpit BRB to TSMS that the live review found, and it draws the eye downstream, which is the spec's anti-goal.

**Decision: colour each segment by its downstream end, with the suspect run kept continuous.** For segment i→i+1:
- it is `suspect` when node i+1 is in the stretch, that is lastClosedIdx < i+1 ≤ breakIdx (a no-data node inside the stretch doesn't break the red run);
- otherwise it takes the state of node i+1.

The red run is then exactly P→F: the hardware between the last voltage-present reading and the first voltage-absent one, which is where the break physically is. The wire into P is green, and the wire out of F is dashed downstream.

This must be **one pure helper owned by the UI branch** (proposed: `segmentStates(nodes): NodeState[]` in `shutdown-loop.display.ts` or `.utils.ts`, length n-1). The strip connectors, the 2D car view and both 3D views all consume it, so no view can drift.

**Dependency:** this is a contract addition for `judge-ui.md`. If the UI judge keeps the upstream rule, the 3D views follow the UI helper anyway: consistency across views beats either rule. Under no circumstances may 3D diverge from 2D.

## MUST FIX (round 2, in implementation order)

Phase A doesn't need the UI contract and can start now. Phase B needs this branch rebased onto `throwaway-shutdown-ui` after its contract commit lands (see the last section).

### M1 (blocker, phase A, then B for styling): the culprit is always visible; screen-space badges replace the sprite labels

- **Merged findings:**
  - proc-live blocker: culprit invisible in Top/Iso;
  - proc-live major: clustered labels;
  - proc-spec minor: sprite labels unreadable on a phone;
  - proc-live minor: zoom blows up labels.
- **Decision:**
  - Delete the canvas sprite labels and the ring sprite.
  - Port glTF's HTML badge overlay and `placeBadges` (constant CSS size, de-overlap), positioned from an `onFrame(projected points)` callback that runs only when a frame renders. Make two changes to `placeBadges`:
    - place **suspects first** (priority order, then loop order), so the culprit gets its preferred spot and the top z-order;
    - make a spot that covers **any suspect's projected marker centre** cost more than any overlap between badges, so no badge ever hides a suspect.
  - Each suspect gets an overlay **halo ring** (HTML/CSS, always above the canvas) and a status glyph in its badge.
  - Draw the suspect marker mesh last, with `depthTest:false`, so frame tubes and nearer markers can't hide it.
  - Badges are `pointer-events` targets for picking, and their keyboard semantics follow the contract (M6).
- **Acceptance:**
  - For each break location in {TS+ sense, IMD latch, AIRs, Cockpit BRB, TSMS} × {Iso, Side, Top}, at 1280×720 and 390×844, the suspect halo and badge are fully visible in a screenshot and no other badge overlaps the suspect marker's centre (`pictures/throwaway-shutdown-3d-procedural/r2/`).
  - Unit tests on `placeBadges`:
    - suspects are placed before other nodes;
    - no badge rectangle contains a suspect's projected point;
    - a 5-node cluster spaced 4 px apart fans out without overlap where room allows.
  - Badges stay 24 px at any zoom.
- **Files:**
  - `C3D/car-scene.ts` (remove `badgeTexture`, `ringTexture`, label and ring sprites; add an `onFrame` projection);
  - `C3D/car-view-3d.component.{ts,html}`;
  - a new shared `C3D/car-view-3d.projection.ts` with its spec (see convergence).

### M2 (major, phase A): screen-space picking, pure and tested

- **Merged findings:**
  - proc-correctness major: wrong-node picking;
  - proc-correctness nits: right/middle click picks, and multi-touch overwrites `down`;
  - the "tests mock the whole scene" finding (the picking part).
- **Decision:**
  - Delete the invisible pick spheres and the raycaster.
  - Pick with the shared `nearestPoint(points, x, y, reach)` over the projected marker centres from M1's `onFrame`. Port it from glTF and add a tie-break: equal distance (±1 px) goes to the smaller NDC z (nearer the camera).
  - Clicking a badge picks its node directly.
  - Record `down` only when `e.button === 0 && e.isPrimary`, and match on `pointerId` in `onUp`.
  - Hover reuses the same function (it later emits `nodePreview`, see M6).
- **Acceptance:**
  - A spec projects `NODE_POSITIONS_3D` through each view preset with a real three `PerspectiveCamera` (three's maths runs in jsdom, and the spec may import it), and asserts that each marker's centre picks that marker. It names the AIRs/HVD (Iso) and Cockpit BRB/Inertia (Side) cases. Top is exempt for pairs closer than 12 px until S8 lands.
  - A right-click or a two-finger gesture never changes the selection.
- **Files:** `C3D/car-scene.ts:111-112,165-174,270-288`, `C3D/car-view-3d.projection.ts` and its spec.

### M3 (major, phase A): truly render on demand; no WebGL pulse

- **Merged findings:**
  - proc-correctness major and proc-spec major: 60 fps while a node is suspect, even off screen;
  - proc-correctness minor: draw calls multiply that cost.
- **Decision:**
  - Remove the geometric pulse from the WebGL scene.
  - The suspect's "something's wrong here" motion moves to M1's HTML halo as a CSS animation gated by `motion-safe:` (no animation under reduced motion). It costs no WebGL frames and also works when the marker is occluded.
  - The scene renders only for a tween, damping, a resize, a state change (`sceneSignature`) or a selection change.
  - Pull frame scheduling out of `createCarScene` into a small pure scheduler: `needsFrame({tweening, damping})`, or a `RenderScheduler` taking an injected `raf`.
  - Fix the doc comment.
- **Acceptance:**
  - Live: with 1–3 suspects and no input, a `gl.clear` counter shows **0 renders over 5 s** once settled, with and without reduced motion.
  - The CDP main-thread busy share in 3D on the flapping sim stays within 10 points of 2D (31 % baseline).
  - A unit test: the scheduler stops requesting frames once the tween ends and damping settles, with suspects present.
- **Files:** `C3D/car-scene.ts:54,144,175,232-252`.

### M4 (major, phase A locally, B to switch to the UI helper): wire colouring by the downstream end

- **Merged findings:** proc-live major "the red wire points at the wrong place".
- **Decision:** see "Wire colouring: decision" above.
  - In phase A, implement `segmentStates` as a pure function with the proposed name and signature in `C3D/car-view-3d.utils.ts`, and make `buildLoopSegments` take segment states from it.
  - In phase B, delete the local copy and import the UI branch's helper.
  - Update the doc comment at `model.ts:59-62`.
- **Acceptance:** spec cases:
  - (a) single-suspect break (TSMS): P→TSMS is red and TSMS→HVD is dashed downstream;
  - (b) multi-suspect stretch P, S1, F: P→S1, S1→F red; F→next downstream;
  - (c) a no-data node inside the stretch: the red run stays continuous;
  - (d) a closed loop: all green, and a segment into a trailing no-data node is dotted.

  Live: with a Cockpit BRB break in Iso, no red segment connects Cockpit BRB to TSMS.
- **Files:** `C3D/car-view-3d.model.ts:59-81`, `C3D/car-view-3d.model.spec.ts`.

### M5 (major, phase A for the cues, B for tokens): colour from theme tokens, plus non-colour cues

- **Merged findings:**
  - proc-live major: colour-vision safety;
  - proc-spec blocker (the `cssClass`, `--sd-color` and `shutdown-states.css` parts) and the off-palette red minor;
  - ui-spec: `hv = --color-danger` would make HV parts look like faults;
  - proc-live nit: downstream and no-data look alike.
- **Decision:**
  - **Phase B, tokens:**
    - Use the contract's `readStateColours()` for the four state colours.
    - Delete the probe spans, `--sd-color`, the `shutdown-states.css` `styleUrls` entry, `cssClass` on `LoopSegment3d`/`Marker3d`, and `DEFAULT_SCENE_COLORS.states`. The only jsdom fallback is the contract's single copy of the `theme.css` values.
    - Move `SCENE_COLOR_TOKENS.hv` off `--color-danger` (the contract's reserved-colours rule; e.g. `--color-warn` or `--color-secondary-border`, whichever the UI judge names).
  - **Phase A, non-colour cues on every state:**
    - the suspect wire is drawn "strong", at 2× the normal wire radius;
    - downstream is dashed and no-data is **dotted**, with two clearly different patterns that follow the UI's `dash` values;
    - suspect badges carry the strip's glyph and the M1 halo;
    - the marker shapes stay.
- **Acceptance:**
  - Under feColorMatrix deuteranopia and protanopia, a TSMS break and a TS+ sense break in Iso can be identified with the colour removed (halo, glyph, thickness): screenshot pair in `pictures/.../r2/`.
  - `grep -rE '#[0-9a-f]{6}' C3D/` finds no state colours outside the one fallback.
  - The spec asserts that a dashed segment and a dotted segment have different piece lengths.
- **Files:** `C3D/car-view-3d.model.ts:160-202`, `C3D/car-view-3d.component.{ts,html}`, `C3D/car-scene.ts:113-121,156-159`.

### M6 (major, phase B): adopt the UI selection contract; one detail panel; utilities only

- **Merged findings:**
  - proc-spec major: the view owns selection, its own info overlay and the toolbar;
  - proc-spec major: hand-styled stylesheet;
  - proc-spec blocker (the `styleUrls` part);
  - proc-live minors: the toolbar keyboard model, `aria-live` floods, touch targets, the 2D/3D round trip dropping the selection, and context loss dropping the selection.
- **Decision:** `car-view-3d` implements the contract's view interface:
  - inputs `nodes`/`selectedId`/`previewId`, outputs `nodeSelect`/`nodePreview`;
  - it highlights `previewId ?? selectedId`;
  - a canvas or badge pick emits `nodeSelect`, a hover emits `nodePreview`, and Escape emits `nodeSelect(null)`.

  Delete:
  - the local `selectedId` signal, `toggle`, `onToolbarKey`/`tabStop`;
  - the node toolbar, `nodeInfo`/`NodeInfo` and the info overlay;
  - the nested `<car-view>` fallback inside `car-view-3d`. The switch renders the single 2D fallback and passes the contract through, and the 3D view emits an `unavailable` output.

  Badge keyboard semantics are whatever `judge-ui.md` sets for the 3D overlay (proposed: an `ngListbox` with selection following focus). The preset buttons use `segmentedClasses` with `aria-pressed`. The stage and overlay layout become utilities, and `C3D/car-view-3d.component.css` is removed.
- **File deletions need the user's explicit confirmation** (CLAUDE.md safety rule): `car-view-3d.component.css`. The toolbar and overlay are only markup.
- **Acceptance:**
  - Picking in 3D highlights the strip and opens the page's `node-detail`.
  - Selecting in the strip moves the 3D highlight.
  - The selection survives a 2D↔3D toggle and a context-loss fallback.
  - `C3D` has no `styleUrls`.
  - The shared `expectLoopViewContract` helper passes against `car-view-3d` with a fake scene.
  - `ng build` shows no `anyComponentStyle` warning.
- **Files:**
  - `C3D/car-view-3d.component.{ts,html,spec.ts}` (delete `.css`);
  - `components/car-view-switcher/*` (renamed to the contract's switch name, by default `car-view-switch`; keep the `argos.shutdown.carView` key and the storage-throws tests);
  - `shutdown-page.component.{html,ts}` (re-applied by hand onto the UI page).

### M7 (major, phase A): shared positions frame, table shape and camera fit

- **Merged findings:**
  - proc-spec major: private frame and hand-typed presets;
  - proc-live nit: Iso crops the rear tyre;
  - part of proc-live major: phone framing.
- **Decision:**
  - Use the glTF branch's frame and table shape:
    - `Vec3` tuples in metres;
    - +X forward, +Y up, +Z to the driver's right;
    - origin on the ground under the rear axle centre.
  - Convert this branch's table mechanically: X = 2.15 − x, Y = y, Z = −z (`REAR_AXLE_X = 2.15` in `car-model.ts:37`).
  - Put the procedural car into the frame with one wrapper transform on `buildCar`'s group (`rotation.y = π`, `position.x = 2.15`), not by rewriting `car-model.ts` numbers.
  - Replace `CAMERA_PRESETS` with glTF's `VIEW_DIRECTIONS` plus `fitDistanceToPoints`, fitted to the car's bounding box (`Box3.setFromObject`).
  - Delete `CAR_EXTENT_3D`. The positions spec instead asserts that every node lies inside the procedural car's bounding box (the spec may import three).
  - `em-interlock` is on opposite sides in the two tables. Use one side in both branches and mark it `TODO(electrical lead): confirm side`.
  - If `judge-gltf.md` moves the shared frame to glTF-native axes (+Z forward), follow it: only the wrapper transform and the mechanical conversion change.
- **Acceptance:**
  - `shutdown-loop.positions-3d.ts` has the same type, frame doc comment and keys as glTF's (identical values as well, if judge-gltf agrees).
  - Iso/Side/Top show the whole car, wheels included, at 1440×900, 1280×720 and 390×844.
  - The positions spec keeps the "no duplicates, both sides" checks and adds the in-bounds check.
- **Files:**
  - `shutdown-loop.positions-3d{,.spec}.ts`;
  - `C3D/car-view-3d.model.ts:10-23,227-239`;
  - `C3D/car-scene.ts:87,94-101,203-230`;
  - the wrapper in `car-scene.ts` or `car-model.ts`.

### M8 (major, phase A): phone default

- **Merged findings:**
  - proc-live major: phone layout unreadable, with 3D as the default;
  - proc-spec minor: 3D default on first visit.
- **Decision:** with no stored choice, start in **3D only when `(min-width: 1024px) and (pointer: fine)`** matches, else 2D. A stored choice always wins. This is the same rule in both 3D branches, and it is recorded in ADR 0010 (S10). On a phone, M1's fixed-size badges make 3D usable if the user opts in.
- **Acceptance:** switch spec cases:
  - no storage at 390 px gives 2D;
  - no storage on a wide screen with a fine pointer gives 3D;
  - stored `'3d'` on a phone gives 3D;
  - storage that throws gives the rule's default.
- **Files:** `components/car-view-switcher/car-view-switcher.component.{ts,spec.ts}` (`readCarViewMode` takes an injectable `matchMedia`).

## SHOULD FIX (round 2 if time allows; cheap ones first)

| id | finding (source) | decision and acceptance | files |
|---|---|---|---|
| S1 | WebGL probe context per mount (correctness minor; spec nit: global `document`) | Compute once in the `WEBGL_SUPPORT` factory with `inject(DOCUMENT)`, and release the probe with `getExtension('WEBGL_lose_context')?.loseContext()`. Acceptance: 25 toggles create 25 contexts plus 1 probe, not 50. | `C3D/car-view-3d.tokens.ts`, `.model.ts:151-158` |
| S2 | Renderer leaks if `createCarScene` throws; `forceContextLoss` warning after a real loss (correctness minor and nit) | Wrap the code after the renderer is created: on error, `dispose()` and `forceContextLoss()`, then rethrow. In `dispose`, call `forceContextLoss` only if `!isContextLost()`. Acceptance: no THREE warning after a simulated loss. | `C3D/car-scene.ts:75,320-321` |
| S3 | Fallback UX (live minor; spec minor: `start()` hangs on "Loading…") | A missing canvas or stage calls `fallBack('init')`. Port glTF's `FallbackReason`/`FALLBACK_NOTICES` and add `'context-lost'` with a "Retry 3D" button. In fallback the 3D option shows as unavailable, not pressed. Focus goes to the view container with `injectFocusAfterRender` (CONTEXT.md convention). | `C3D/car-view-3d.component.*`, the switch |
| S4 | Camera on select; zoom and pan limits (live minors) | An `effect` on `selectedId` tweens the target to the node and dollies in (a jump under reduced motion), with no other side effect (contract). `minDistance` comes from the fit (about 0.6× the fit distance) so the camera never enters the frame. Clamp `controls.target` to the car's bounding box on `change`. | `C3D/car-scene.ts` |
| S5 | Wire reads like frame (live minor, the cheap half) | The loop wire radius is clearly larger than the frame tubes', or the frame uses a dimmer token. Dead wire stays distinguishable from frame through its dashes. No routing (see Rejected). | `C3D/car-scene.ts:49`, `car-model.ts` |
| S6 | Mismatch is only "13!" (live minor) | The badge shows the UI's mismatch cue, and its accessible name comes from the UI's `nodeAriaLabel`, which includes the mismatch. | component html (phase B) |
| S7 | Number-only labels (live major, cluster part) | Suspect and selected badges show the number plus the short name ("18 TS+"), from `LoopNode.short` per the contract. | component html, `placeBadges` widths |
| S8 | Top-view coincidence: latches over sense points, 4.1 px apart (judge spot check) | Nudge the schematic latch and sense rows apart laterally so every pair is ≥ 12 px apart in all presets at 1000×560, and add that as a spec over the shared table. Coordinate with judge-gltf, because the table is shared. | `shutdown-loop.positions-3d{,.spec}.ts` |
| S9 | Layout and naming convergence (spec minors and nits) | Rename `car-model.ts` → `procedural-car.ts`, `car-view-3d.model.ts` → `car-view-3d.utils.ts`, and move the interfaces to `car-scene.types.ts` (the glTF layout). Remove the `NgZone` wrappers (the app is zoneless). Set the pixel ratio again in `resize`. Keep `three/addons/` imports. Put the 3D/2D toggle in the same overlay row as the presets. | `C3D/*` |
| S10 | No ADR or spec change for three and 3D (spec major) | Draft `docs/adr/0010-angular-client-three-js-3d-car-view.md`, Status: Proposed, and a spec amendment ("D. 3D car view: optional, 2D stays the primary and accessible fallback"). Write the text once and copy it **byte-identical into both 3D branches**. It covers: three lazy-only with an exact pin (`@types/three` in lockstep); the shared frame; the default-view rule (M8); the 2D view as fallback; car source "under evaluation: procedural vs glTF". No conflict with ADR 0007 (three is a renderer, not a UI kit). It is required before either branch becomes a ticket or PR. | `docs/adr/`, `docs/spec/shutdown-loop-page/spec.md` |
| S11 | Phone scroll trap (spec minor) | Under `(pointer: coarse)`, one finger scrolls the page (`touch-action: pan-y` after OrbitControls connects, `controls.touches.ONE` unmapped) and two fingers orbit and zoom. Acceptance: a Playwright `hasTouch` vertical swipe over the canvas scrolls the page. Verify that OrbitControls r187 honours the unmapped `ONE`. | `C3D/car-scene.ts` |

## REJECTED (with reasons)

| Finding | Reason |
|---|---|
| Merge the static car and dash meshes to cut 196 draw calls (correctness minor) | Deferred. After M3 the scene renders only on input or a state change. 196 draws during an orbit drag is trivial for any real GPU, and the 196 was measured on SwiftShader. Revisit only if a pit-laptop profile shows dropped frames while orbiting. M1 already removes the 19 label sprites. |
| IntersectionObserver or visibility gating (correctness, spec) | Unnecessary after M3. Off screen there is no input, and a state change costs one frame. |
| Route the harness along frame rails with waypoints (live minor) | Not now. Positions are schematic and the table is shared with glTF. Waypoints would add a per-segment table shape to both branches, plus CAD work, for a throwaway. S5 covers the readability half cheaply. |
| Auto-frame the suspect stretch when the verdict opens (live blocker fix list) | The sim and a real flapping loop would yank the camera away from the user. The camera moves only on an explicit selection (S4), and the banner's "select cause" gives one-click framing. |
| Keyboard orbit and zoom on a focusable canvas (live nit) | The strip and badges are the keyboard path, and the presets cover the views. Low value. |
| Toolbar keyboard model, Space toggle-off, `aria-live` flood, 28×24 targets (live minors) | Superseded: M6 deletes the toolbar and the overlay. Badge targets follow the contract (24 px; 44 px under coarse pointers if judge-ui adopts that). |
| Mock panel loses to the live sim (live minor) | Not this branch: the mock panel belongs to the UI and logic branches. Route it to judge-ui and judge-logic. |
| Red frame tubes in the 2D photo (live nit) | Not this branch: it's the 2D car art. Route it to judge-ui. |
| A "Where" row in words in the card (live minor) | It belongs to the page's single `node-detail` and the loop-node model (UI contract §3), not to the 3D view. Route it to judge-ui as an idea. |
| "Explode cluster" UI or an x-ray frame toggle (live) | Overkill for a throwaway. M1's de-overlap plus S8's spacing address the cause. |
| Camera reset to Iso on the 2D↔3D round trip (live nit) | Acceptable: a fresh mount fits the car. The selection part is fixed by M6. |
| One combined `car-view-3d` with a pluggable `CarSource` (both spec reviews' merge strategy) | Contradicts the user's constraint that the branches stay separate. Instead, keep the seams identical (frame, table, projection helpers, tokens file, switch, contract) so a later `CarSource` split is a file copy. |
| Keep the suspect pulse in WebGL (gltf-spec "keep from procedural") | Replaced: the motion moves to the CSS halo (M3), and glTF should do the same. |
| Badge font, radius fallback and dead `cssClass` nits (spec) | Moot once M1, M5 and M6 land. |

## CONVERGENCE WITH glTF

The two branches stay separate. These pieces should be **byte-identical files** in both, so either branch, or a later combined one, can take them as is:
- `shutdown-loop.positions-3d.ts` and its spec (M7, S8);
- a new `C3D/car-view-3d.projection.ts` and its spec: `nearestPoint` (with the depth tie-break), `placeBadges` (suspect-first, avoiding suspect points), `fitDistanceToPoints`, `VIEW_DIRECTIONS`;
- `C3D/car-view-3d.tokens.ts` (`CAR_SCENE_LOADER`, `WEBGL_SUPPORT` memoised with `inject(DOCUMENT)`);
- the switch component and storage key;
- ADR 0010 and the spec amendment text.

**Port from glTF into procedural:**
- `nearestPoint` (M2);
- `placeBadges` and the HTML badge overlay with `onFrame` projection (M1);
- `fitDistanceToPoints` and `VIEW_DIRECTIONS` (M7);
- the frame and `Vec3` table shape (M7);
- segment emphasis, thick for the cause (M5);
- `FallbackReason`, `FALLBACK_NOTICES`, `CarSceneError` and `fallBack('init')` (S3);
- the `car-scene.types.ts` file layout (S9).

Not ported: anchors and `resolveNodePositions`, `unitScaleFor`, material modes, GLB, Draco. These mean nothing without a model.

**glTF should port back from procedural** (recommendation to judge-gltf):
- the `webglcontextlost` → 2D fallback (glTF has none);
- reduced motion: no damping, preset jumps instead of tweens;
- `sceneSignature`, which skips rebuilds and re-renders on age ticks (glTF re-renders on every status tick);
- dashed and dotted dead wire (`dashPieces`), matching the UI `dash` language;
- tokens kept in their own file;
- the `argos.shutdown.carView` key with its storage-throws tests;
- the destroy-during-load guard;
- the renderer-leak and context-loss guards (S2);
- the memoised probe (S1).

**Same semantics in both, all from the UI contract:**
- the segment-state helper (M4);
- marker shape per state;
- the halo, glyph and thick-wire cues (M5);
- no WebGL pulse (M3);
- the default-view rule (M8);
- screen-space picking (M2);
- the selection I/O and the single `node-detail` (M6).

## Dependency on the UI contract (`judge-ui.md`)

- **Base.** This branch is based on `origin/shutdown-loop-page`, not on the UI branch. Phase B requires rebasing (or merging, since it's a throwaway) onto `throwaway-shutdown-ui` once its round-2 contract commit exists.
- **What phase B relies on from the UI branch:**
  - `ShutdownSelectionStore` and the view interface (`nodes`/`selectedId`/`previewId`/`nodeSelect`/`nodePreview`, plus `expectLoopViewContract`);
  - `readStateColours()` and the state tokens, plus the reserved-colours rule (the HV token is not danger);
  - `NODE_STATE_DISPLAY` `marker.*`, `dash` and `emphasis`;
  - `nodeAriaLabel`;
  - `LoopNode.short`;
  - the single `node-detail`;
  - the switch component's name.
- **Asks to judge-ui:**
  - add the shared `segmentStates` helper with the downstream-end rule (M4) and use it in the strip connectors and the 2D car view;
  - define the 3D badge overlay's keyboard role (listbox, or `aria-hidden` with the strip as the only keyboard path);
  - name the HV token.
- **Until the contract lands,** do phase A (M1 mechanics, M2, M3, M4 locally, M5 cues, M7, M8, S1–S2) and leave `cssClass` and the probes in place. Phase B (M5 tokens, M6, S6, S7, M4's switch to the UI helper) follows the rebase.
- **If judge-ui's contract differs from what is assumed here,** the contract wins and these items adapt. The 3D view must never keep its own selection, detail panel or colour source.
