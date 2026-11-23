# Round 2: `throwaway-shutdown-3d-procedural` (4df0fb6b), lens CONVENTIONS / ARCHITECTURE / DOCS

Delta reviewed: `origin/throwaway-shutdown-ui...4df0fb6b` (24 files). Sibling compared: `throwaway-shutdown-3d-gltf` at 40739def.
Paths below are relative to `angular-client/src/pages/shutdown-page/`, and `C3D/` stands for `components/car-view-3d/`.
My scratch files are in `/tmp/claude-0/-home-user/6e25b80b-05af-58e5-9050-4f2faa446aec/scratchpad/r2rev-proc-spec/`:
- `src/sep.ts` and `sep.mjs`: real `buildCar` plus the real `viewPose` fit, measuring the closest pair of markers per preset and stage size;
- `build-*.log`, `test.log`, `lint.log`, `prettier.log`.

Screenshots: `/home/user/Delphi/pictures/throwaway-shutdown-3d-procedural/review-r2/spec-{side,top,iso}-preset-1440.png`.

**Checks that pass:**
- `ng test` on `src/pages/shutdown-page/**`: 22 files, 319 tests pass.
- `ng lint` is clean, and `prettier --check` is clean.
- `ng build` passes, with no `anyComponentStyle` warning. The only warning is the old hammerjs one.

**Bundle:**
- three.js is only in the lazy `car-scene` chunk: 595.68 kB raw, 123.54 kB transfer. No initial chunk contains `WebGLRenderer` or `OrbitControls`.
- Initial total is 786.77 kB here against 785.29 kB on the UI branch (+1.48 kB). All of the growth is `styles` (93.78 → 95.26 kB), from the new Tailwind utilities. The initial JS is unchanged: chunks shifted by ±0.1 kB.
- `shutdown-page-component` (itself lazy) grew from 57.35 to 75.68 kB.

**Shared files, byte-identical with glTF (`cmp`):**
- `shutdown-loop.positions-3d{,.spec}.ts`
- `C3D/car-view-3d.projection{,.spec}.ts`
- `C3D/car-view-3d.tokens.ts`
- `car-view-mode.component.{ts,html,spec.ts}`
- `package.json` and `package-lock.json`

**Not identical, but meant to be or cheap to make so:**
- `docs/adr/0010-…` (procedural only);
- `docs/spec/shutdown-loop-page/spec.md` (option D on procedural only);
- `shutdown-page.component.{ts,html}`: they differ only by procedural's focus-after-fallback;
- the same-named helpers in `C3D/car-view-3d.utils.ts` and `C3D/car-scene.types.ts` (see N4).

## Round-1 MUST status (items under this lens)

| id | item (lens part) | status | evidence |
|---|---|---|---|
| M1 | Files and structure: sprites gone, HTML badge overlay, shared `car-view-3d.projection.ts` with spec | VERIFIED-FIXED | `C3D/car-scene.ts` has no sprite, label or ring textures. The overlay is in `C3D/car-view-3d.component.html:15-77`. `projection.ts` is pure (no three import) and byte-identical with glTF. The spec covers suspect-first placement, the halo rule, the 4 px cluster, constant size, hysteresis and leaders. |
| M2 | Screen-space picking, pure and tested | VERIFIED-FIXED | `nearestPoint` has the ±1 px depth tie-break (`projection.ts:104-118`). The raycaster and pick spheres are gone. `button===0 && isPrimary` plus a `pointerId` match is at `car-scene.ts:330-340`. `projection.spec.ts:120-126` projects the real table through a three `PerspectiveCamera` in every preset. |
| M3 | A pure render scheduler | VERIFIED-FIXED | `RenderLoop` has an injected `raf`/`caf` (`C3D/car-view-3d.utils.ts:205-232`), and its spec covers "stops with suspects present". The pulse is now the CSS halo `motion-safe:animate-ping`, 3 iterations. The doc comment matches the code (`car-scene.ts:59-64`). |
| M4 | One segment helper, owned by the UI | VERIFIED-FIXED | `buildLoopSegments` calls the UI's `segmentState` (`utils.ts:84`), and the local copy is gone. |
| M5 | Colour only from tokens; HV not danger | VERIFIED-FIXED | `readSceneColours` reads `SCENE_COLOR_TOKENS` plus `readStateColours`, with `hv: --color-secondary-border` (`utils.ts:170-186`). A grep for `#hex` in `C3D/` and `car-view-mode/` outside specs finds nothing. The only literal colours left are lights and the clear colour (`car-scene.ts:88,102-103`): 0x000000 with alpha 0, and white lights, which are not states. |
| M6 | Selection contract, one detail panel, utilities only, no `styleUrls` | PARTIAL | Done:<br>• inputs/outputs per `CarLoopView`; no local selection, toolbar, info overlay or nested `<car-view>`;<br>• `expectLoopViewContract` runs in `car-view-3d.component.spec.ts:70`;<br>• no `styleUrls`, and `car-view-3d.component.css` is gone.<br>Missing: the round-1 decision said "the preset buttons use `segmentedClasses` with `aria-pressed`". They use the recipe without any pressed state (N3). |
| M7 | Shared frame and table, wrapper transform, fitted camera, no `CAR_EXTENT_3D`, in-bounds spec | VERIFIED-FIXED (one PARTIAL point) | Done:<br>• the table is byte-identical with glTF, in glTF's frame;<br>• one wrapper (`procedural-car.ts:117-122`: `rotation.y = π/2`, `position.z = 2.15`), with the mapping documented;<br>• `CAMERA_PRESETS` and `CAR_EXTENT_3D` are gone, and `viewPose` fits the car's vertices;<br>• `em-interlock` carries a `TODO(electrical lead)`.<br>PARTIAL: the in-bounds test is weaker than it reads (N6). |
| M8 | Default view rule, and the switch spec cases | VERIFIED-FIXED | `CAR_VIEW_3D_QUERY = '(min-width: 1024px) and (pointer: fine)'`. The spec cases cover a phone with nothing stored, a wide screen with a fine pointer, a stored 3D choice on a phone, and storage that throws. The file is shared byte for byte with glTF. |
| S8 | Top view: latches and sense points ≥ 12 px apart | VERIFIED-FIXED (as specified) | `projection.spec.ts:128-140`, at 1000×560. With the real procedural fit, Top's closest pair is 36.9 px at 1000×560 and 20.9–30.8 px at the real stage sizes. Plausibility and the Iso caveat are in N2 and N7. |
| S9 | Renames, no NgZone, pixel ratio on resize, `three/addons` | VERIFIED-FIXED | Done:<br>• `procedural-car.ts`, `car-scene.ts`, `car-view-3d.utils.ts` and `car-scene.types.ts`;<br>• no `NgZone` or `runOutsideAngular`;<br>• `resize` resets the pixel ratio (`car-scene.ts:305-306`);<br>• `three/addons/controls/OrbitControls.js`.<br>The 3D/2D toggle sits in the card header (`car-view-mode`), not in the preset row. That is acceptable: the same component is shared with glTF. |
| S10 | ADR 0010 (Proposed) and spec option D, byte-identical in both 3D branches | PARTIAL | Both files exist on procedural only. The ADR's Status line claims both branches (N1). |

## New findings

### N1 (major, docs and convergence): ADR 0010 and spec option D exist on one branch, but the ADR says they're on both. The judges' conflict is unresolved.

- **Where:**
  - `docs/adr/0010-angular-client-three-js-3d-car-view.md:3`;
  - `docs/spec/shutdown-loop-page/spec.md:144`;
  - glTF's `docs/spec/shutdown-loop-page/car-model.md:3-5`.
- **Issue:**
  - The Status line reads "written on the throwaway branches `throwaway-shutdown-3d-procedural` and `throwaway-shutdown-3d-gltf`", but the glTF branch has no `docs/adr/0010-*`.
  - glTF's `spec.md` is byte-identical to the UI branch's, so it has no option D.
  - glTF's `car-model.md` still says "The spec still says option A, chosen; any adoption of a 3D view must amend it".
  - judge-proc S10 asked for a byte-identical ADR in both branches; judge-gltf R4 rejected an ADR on glTF.
  - The ADR's consequences are procedural-specific. "About 125 kB" is true for procedural only: glTF was 138 kB in round 1, plus the GLB and the Draco decoder assets. The fallback list also omits glTF's broken-model case and its absent-model state (wiring only).
  - Its "not yet supported on the pit laptops" (the alternative-library bullet) is unverified.
- **Failure scenario:** a reviewer of the glTF branch sees a 3D view that the spec calls unchosen, with no decision record. If the adoption ticket squashes the glTF branch, the ADR is lost. If it squashes procedural, the ADR misdescribes glTF.
- **Recommended resolution: adopt judge-proc S10 and reject R4.** One ADR 0010 with Status Proposed and an approach-neutral text, plus the option-D line, byte-identical in both branches. R4's three objections are met as follows:
  - "Each would claim 0010 and pre-decide the approach": a byte-identical file claims 0010 once, and the car source is left explicitly open.
  - "The record belongs to the adoption ticket": per CLAUDE.md, adoption is `merge --squash` of the throwaway into the ticket's worktree, so the Proposed ADR lands with it. The ticket then edits the Status line and the car-source bullet, instead of rewriting from memory.
  - The decisions the ADR records are already implemented identically in both branches:
    - three lazy and pinned;
    - the shared frame;
    - the default-view rule;
    - `CarLoopView`;
    - 2D as the fallback.

  Under CLAUDE.md's "explain reasoning before architectural changes" they need a record now.

  glTF's `car-model.md` stays glTF-only, as the source-specific input. Change its sentence at lines 3-5 to: "Status: throwaway (`throwaway-shutdown-3d-gltf`). The glTF input to ADR 0010 (Proposed), whose car-source choice is still open; the 3D view itself is the spec's option D."
- **Exact ADR text (both branches, byte for byte):**

```markdown
# Add an optional three.js 3D car view to the Shutdown Loop page

Status: Proposed. The throwaway branches `throwaway-shutdown-3d-procedural` and `throwaway-shutdown-3d-gltf` carry this file byte for byte; the adoption ticket decides it, picks the car source and removes this line.

The Shutdown Loop page may show the car in 3D as well as in 2D. The 3D view draws the car with three.js, each loop node where it sits on the car and the loop wire through them in series order. The 2D view stays the primary view and the accessible one: the loop strip is the keyboard and assistive-tech path in both, and the 2D car is the fallback whenever 3D can't draw. Both car views implement the page's `CarLoopView` contract, so selection, the detail panel and colours are the page's and never the view's.

## Considered Options

- **2D only** (the spec's option A). Kept as the default on phones and as the fallback, but a side view hides where loop nodes sit across the car (the side BRBs, the E-box latches against the accumulator sense row).
- **A 3D library other than three.js** (Babylon.js, a WebGPU-only renderer). Rejected: Babylon.js is a larger download for the same picture, and WebGPU-only would drop browsers and GPUs that only have WebGL. three.js is a renderer, not a UI kit, so ADR 0007 is untouched: every control around the canvas is still our Tailwind and Aria components.
- **Where the car comes from: open.** Two throwaway branches try the two sources:
  - procedural (`throwaway-shutdown-3d-procedural`): the car built from three.js primitives in code. Theme-native and no asset, but only as close to the real car as someone keeps the code.
  - glTF (`throwaway-shutdown-3d-gltf`): a model exported from CAD, whose `shutdown:<node id>` anchors may override the table. Real geometry, but a binary asset to keep in step with the car; with no model the view draws the loop wiring alone. That branch's `docs/spec/shutdown-loop-page/car-model.md` has the export rules.

  The adoption ticket picks one, or keeps both behind one `CarSource` seam. Everything below holds for either.

## Why this shape

- **three.js only in a lazy chunk, pinned exactly.** The scene module is imported on demand when 3D is shown, so the initial JavaScript doesn't grow. `three` and `@types/three` are pinned to the same exact version and move together.
- **One shared frame and table.** `shutdown-loop.positions-3d.ts` holds every loop node's position in metres: +Y up, +Z forward (glTF's native forward), +X to the driver's left, the origin on the ground under the rear-axle centre. Any car source is placed in that frame by one transform.
- **Shared seams.** The positions table, the projection helpers (`car-view-3d.projection.ts`), the tokens file and the 2D/3D switch (`car-view-mode`) are the same files in both branches; only the scene and the car differ.
- **Screen-space picking and HTML badges.** Markers are picked by their projected centre (nearest within 16 px, the nearer one on a tie). Badges and the suspect's halo are HTML over the canvas: a constant size at any zoom, never hidden by the scene, placed suspect-first so the cause is never covered.
- **Render on demand.** The scene renders only for a camera move, a resize, or a change of a loop node's state, mismatch or highlight; an idle page renders nothing, whatever the loop shows. The suspect's motion is a CSS animation on its halo, off under reduced motion.
- **Default view.** With no stored choice, 3D only when `(min-width: 1024px) and (pointer: fine)` matches; 2D otherwise. A stored choice (`argos.shutdown.carView`) always wins.
- **2D is the fallback.** No WebGL, a scene that fails to start, a car model that is present but unreadable, or a lost context shows the 2D car with a notice; the selection stays, because the page owns it. Choosing 3D again retries.

## Consequences

- three.js loads the first time 3D is shown: about 125 kB (transfer) with the procedural car. The glTF source adds about 13 kB of loader, the model file and, for a Draco-compressed model, the Draco decoder in `assets/draco/`.
- The global stylesheet grows by the view's utilities (about 1.5 kB raw).
- WebGL is needed for 3D; software rendering works but costs CPU while orbiting.
- The positions table is schematic until the electrical lead confirms placements (the energy meter interlock's side is open).
- Two views draw the car, so a new loop node needs a position in the 3D table as well as the 2D coordinates (and, with a glTF model, optionally an anchor); specs check both tables are complete.
```

- **Exact spec text** (`spec.md`, after option C, in both branches). Keep procedural's line 144 as it is: it is already approach-neutral and says "proposed, ADR 0010".
- **Evidence:**
  - `cmp` and `ls docs/adr` on both worktrees;
  - `diff` of the glTF spec against the UI branch's `HEAD:docs/spec/...` is empty;
  - chunk sizes from my builds and from round 1's `proc-spec.md:10-11`.

### N2 (minor, positions plausibility): the S8 spread put two of the four latches and three of the five sense points ahead of the main hoop, and the table comment says the opposite.

- **Where:**
  - `shutdown-loop.positions-3d.ts:28-32,43-48` (comment "E-box behind the main hoop");
  - `C3D/procedural-car.ts:210-211`.
- **What the spec asks:** its notes (`spec.md:154`) put the latches in the E-box, the sense points and AIRs in the accumulator, TSIP/HVD near the rear on the accumulator side, and the side BRBs on the main hoop.
- **Sideways offsets: plausible.**
  - The latch row is at X = +0.10 m (driver's left) and the sense row at X = −0.06 m (right).
  - That 16 cm sits well within the car's 0.6 m frame width.
  - Each row stays inside its own box: the E-box spans X −0.04…0.20, Y 0.44…0.64, Z 0.40…0.83; the accumulator spans X ±0.22, Y 0.09…0.33, Z 0.39…0.93 (measured with `Box3` on the built car).
  - The spec says nothing about sides, so this contradicts nothing.
- **Fore-aft spread: not plausible.**
  - The rows span 0.33 m (latches, 11 cm pitch) and 0.44 m (sense points) along Z. Round 1 used a 7 cm pitch, behind the hoop.
  - The main hoop sits at Z ≈ 0.58 (procedural, at latch height) and Z = 0.66 (glTF).
  - So `bms-latch` (0.78) and `imd-latch` (0.67), and `acc-sense` (0.88), `tsip-sense` (0.77) and `ts-minus` (0.66), sit in the driver's compartment. Against glTF's hoop, `ts-minus` is level with it.
  - To enclose them, round 2 moved procedural's boxes forward:
    - accumulator: Z 0.23–0.69 → 0.39–0.93;
    - E-box: Z 0.26–0.56 → 0.40–0.83.

    Both now straddle the main hoop. The E-box sits at seat-back height (Y 0.44–0.64, under the cockpit rim at Y ≈ 0.6). On a real FSAE EV, tractive-system parts stay behind the firewall at the main hoop.
  - The side BRBs (Z 0.68) sit about 14 cm ahead of procedural's hoop at head height (Z ≈ 0.54 at Y 0.92). They sit on glTF's hoop: the table follows glTF's car.

  The Side screenshot shows the accumulator box (cyan) mostly left of, that is ahead of, the main hoop: `review-r2/spec-side-preset-1440.png`.
- **Failure scenario:** a student checking placements against the car ("the latches are in the E-box behind the main hoop") finds the comment false. The procedural car reads as having its battery under the driver's back.
- **Fix (cheap, for the throwaway):** change the comment at `:28` to "E-box at the main hoop, straddling it (schematic spread so the rows separate in 3D)". Do the same at `:43`, and say in the header that fore-aft spacing is stretched for legibility.
- **Fix at adoption:** keep the sideways split, which is what Top needs: its closest pair has 25–37 px headroom. Then either:
  - move both cars' main hoops forward, so every row sits behind them; or
  - tighten the pitch to about 8 cm.

  I tried moving the latch row aft at 9 cm pitch with X 0.16. Side's closest pair then falls to 12.1 px at 1000×560 and 9.9 px at 974×468 (`can-latch`/`em-interlock`, `bspd-latch`/`em-interlock`). The rear 0.6 m is crowded, so a real fix also moves HVD and the energy meter interlock, or the hoop. That is an adoption job, not a throwaway one.

### N3 (minor, conventions and a11y): the camera preset buttons use the toggle recipe with no pressed state (M6 partial).

- **Where:** `C3D/car-view-3d.component.html:85-89`.
- **Issue:**
  - `src/ui/recipes/segmented.ts:8` documents `item` as "a segmented control of toggle buttons … (aria-pressed)", and its pressed look keys off `aria-pressed`.
  - The preset buttons never set `aria-pressed`. The view never tracks which preset is current (`car-scene.ts:214` keeps `preset` private).
  - So the control looks and reads as a toggle group with nothing selected. The round-1 M6 decision required `aria-pressed`.
  - glTF's preset markup has the same gap (no `aria-pressed` in its `Camera view` group).
- **Failure scenario:** a screen reader announces three plain buttons in a "Camera view" group. A sighted user can't tell which view they're in after clicking. A later student copies the pattern and assumes `segmented` doesn't need `aria-pressed`.
- **Fix:**
  1. Keep a `preset` signal in the component.
  2. Bind `[attr.aria-pressed]="preset() === p.id"`.
  3. Clear it when the user orbits: add `onOrbit` to `CarSceneOptions`, fired from the controls' `start` event, which `car-scene.ts:291` already handles.

  Do the same in glTF so the two `car-view-3d.component.html` files converge.

### N4 (minor, architecture and convergence): the "shared seams" diverge in same-named helpers and in the scene contract, so a later `CarSource` merge isn't a file copy.

- **Where:** `C3D/car-view-3d.utils.ts:234-250` and `C3D/car-scene.types.ts:20-52`, against glTF's `car-view-3d.utils.ts:16-27,108,159,249-279` and `car-scene.types.ts`.
- **Issue:** the same names have different shapes in the two branches:

  | Name | Procedural | glTF |
  |---|---|---|
  | `FallbackReason` | `'webgl'\|'init'\|'context-lost'` | `'webgl'\|'model'\|'init'\|'context'` |
  | `CarSceneError` constructor | `(options)` | `(kind, options)` |
  | `FALLBACK_NOTICES` `init` text | "The 3D view failed to start." | "3D view failed to start." |
  | `context` notice | (no retry hint) | carries the retry hint |
  | marker shapes | `MARKER_SHAPE` | `MARKER_SHAPES`, with the same values |
  | metres-per-SVG-unit constants | two: `WIRE_METRES_PER_PX = 0.0067`, `DASH_SCALE = 0.007` | one: `SVG_UNIT_M = 0.006` |
  | `SceneColours` | interface in `car-scene.types.ts` | type in `utils.ts` |
  | `CarSceneFactory` | synchronous | `Promise` |
  | picking | `onPick`/`onHover` callbacks | `pick()` method |

  judge-gltf's convergence item 3 asked for the async factory and `onFrame` in both. `car-view-3d.tokens.ts` is byte-identical yet types `CAR_SCENE_LOADER` against a `CarSceneFactory` that differs per branch. The ADR's "either drops in" is therefore optimistic.
- **Failure scenario:**
  - The adoption ticket keeps both behind a `CarSource` and has to reconcile two fallback vocabularies and two scene contracts.
  - Wire weight differs by about 10 % between the 3D views. Both claim to follow the 2D `WIRE_WIDTH`: a strong core of 5 px gives a 16.75 mm tube radius in procedural (33.5 mm diameter) and 15 mm in glTF.
  - Procedural's comment at `utils.ts:28` ("metres of 3D wire diameter per px … so the closed wire is a 1 cm tube") is also off. A normal 3 px core gives a 1 cm radius, a 2 cm diameter.
- **Fix (cheap):** move the source-independent parts into one more shared, byte-identical file, `C3D/car-view-3d.fallback.ts`:
  - `FallbackReason` as `'webgl'|'init'|'context-lost'|'model'`; procedural never emits `'model'`;
  - `CarSceneError(kind, options)`;
  - `FALLBACK_NOTICES`;
  - `fallbackReasonFor`.

  Also:
  - put `MarkerShape`/`MARKER_SHAPES` and a single `SVG_UNIT_M` in `projection.ts` (or a `car-view-3d.wire.ts`), and use it for both radius and dashes;
  - make procedural's factory `async`. That is a one-line change, since it already awaits the loader in the component. Accept the `pick()` against `onPick` difference, or settle it the same way.

### N5 (minor, convergence and convention): the page files differ between the 3D branches only by procedural's focus-after-fallback.

- **Where:** `shutdown-page.component.ts:77-88` and `shutdown-page.component.html:43-46` (procedural), against glTF's same files.
- **Issue:**
  - Procedural follows the CONTEXT.md convention "move focus after an action with `injectFocusAfterRender`, so it never drops to `<body>`": when 3D falls back while focus was inside the car section, focus moves to the section (`tabindex="-1"`).
  - glTF doesn't. That is the only difference between the two page files.
- **Failure scenario:** in glTF, a keyboard user on a 3D preset button when the context is lost ends up focused on `<body>`.
- **Fix:** port procedural's page lines to glTF verbatim. The page `.ts`/`.html` then become shared byte-identical files too.
  - Keep `outline-none` on the section only because it is a programmatic focus target (`tabindex="-1"`); a comment would help.

### N6 (minor, test quality): `procedural-car.spec`'s "contains every loop node" is nearly a duplicate of the envelope check.

- **Where:** `C3D/procedural-car.spec.ts:33-38`.
- **Question asked:** does it really check every loop node is inside the car's box? **Yes, literally.** It iterates every `NODE_POSITIONS_3D` entry, and the positions spec proves those are exactly the loop's ids, against `Box3.setFromObject(car.group)`.
- **Why that is weak:** that box is the whole car with wheels: X ±0.715, Y 0…1.22, Z −0.23…2.51. That is almost the positions spec's envelope (X ±0.75, Y 0…1.3, Z −0.5…2.6), so a node floating in the air beside the cockpit passes both.
- **What is good:** the accumulator test at `:40-45` is the strong kind.
- **Fix:** add the same containment for latches and the E-box (`bms-latch`, `imd-latch`, `bspd-latch`, `can-latch` in `e-box`) and for `mc-hvil` in `motor-controller`. I checked that both pass today: the latches sit inside the E-box bounds, and `mc-hvil` [0.12, 0.30, 0.10] inside the MC box (X ±0.14, Y 0.14…0.36, Z 0.02…0.19).
- **Better:** derive those boxes from the table (the bounds of the ids plus a margin) instead of hand-typing build-frame numbers. See complexity item 1.

### N7 (nit, test fidelity): the 12 px rule is checked on a 1000×560 envelope fit, not the real fit or stage, and the file header overclaims.

- **Where:** `projection.spec.ts:17-37,128-140`; `shutdown-loop.positions-3d.ts:13-15` ("at least 12 px apart in each camera preset").
- **Issue:** the spec fits `ENVELOPE_MIN/MAX` at 1000×560. The real view fits the car's vertices at the stage's own aspect, measured with Playwright:
  - 1024×768 → 558×399;
  - 1280×720 → 814×374;
  - 1440×900 → 974×468.

  Iso's closest pair, measured with the real `buildCar` and `viewPose` (`r2rev-proc-spec/sep.mjs`):

  | Stage | `mc-hvil`/`hvd` | Other pairs under 12 px |
  |---|---|---|
  | 1000×560 | 13.2 px | none |
  | 974×468 | 11.0 px | none |
  | 814×374 | 8.8 px | three: `bspd-latch`/`can-latch` and `ts-minus`/`ts-plus` 11.6 px, `ts-plus`/`airs` 11.3 px |
  | 558×399 | 9.4 px | none |

  Side's closest pair is at least 13.2 px and Top's at least 20.9 px at all of these. Picking still resolves each centre to itself, since `nearestPoint` takes the nearest, so this is not a correctness bug.
- **Failure scenario:** a student moves a node, the spec passes, and the live Iso view has overlapping markers at 1280×720.
- **Fix:** run the pair check at `[[1000,560],[814,374]]` and soften the header to "at 1000×560 and 814×374". Optionally nudge `mc-hvil` to Y 0.24.

### N8 (nit, conventions)

- **Arbitrary property.** `motion-safe:[animation-iteration-count:3]` (`C3D/car-view-3d.component.html:41`) is an arbitrary property. CONTEXT.md bans arbitrary colours and `!`, not properties, so it is allowed, but it is the only one in `src/`. A theme utility (`animate-ping-3`) would be clearer.
- **Re-key trick.** `@for (k of [pingKey()]; track k)` (`:39`) is a trick to restart the animation. The TS comment at `component.ts:131` explains it, but the template doesn't. Add an HTML comment, or use a keyed `@if` wrapper.
- **"Initial bundle doesn't grow."** The ADR's wording is right for JS. CSS grows by 1.48 kB, which N1's text states.

## Complexity a student team would struggle with

1. **Two frames in `procedural-car.ts`.**
   - Geometry is typed in a build frame (x aft of the bulkhead, z to the left) and rotated into the shared frame.
   - The boxes that must enclose shared-frame table entries are hand-typed in build-frame numbers: round 2 had to re-place them by hand (N2).
   - Deriving the accumulator, E-box and MC boxes from `NODE_POSITIONS_3D` (bounds plus margin, converted once) removes the two-frame bookkeeping where it matters.
2. **Duplicate-named helpers with different shapes across branches** (N4). The most likely source of "works on one branch" bugs at adoption.
3. **Magic wire scales:** `0.0067`, `0.007`, and glTF's `0.006`. Use one named constant shared by both.
4. **The `placeBadges` cost model:**
   - weights `1e9` and `1e4`;
   - a 24-spot ring;
   - hysteresis through `linkedSignal`'s `previous`.

   It is dense but well commented and well tested (8 cases), so it is maintainable. Leave it, but don't let it grow further.
5. **The 12 px spec's envelope pose** (N7) gives false confidence when editing positions.

Not a concern:
- the component's signal graph is small and conventional (`input`/`output`, `computed`, `effect`, `afterNextRender`, no NgZone);
- `RenderLoop` is small and injectable;
- `car-scene.ts` (390 lines) reads top to bottom.
