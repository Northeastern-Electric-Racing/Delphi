# Round-2 review: `throwaway-shutdown-ui`, the shared contract, conventions and integration

Reviewer lens: SHARED CONTRACT, CONVENTIONS, INTEGRATION. Scratch dir: `/tmp/claude-0/-home-user-Delphi/6e25b80b-05af-58e5-9050-4f2faa446aec/scratchpad/r2rev-ui-spec/` (the round-1 records' scratchpad tree).

What I looked at:
- **Code.** ui `6bde6a19` (diffed against `origin/throwaway-shutdown-logic-scylla`), procedural `4df0fb6b` and gltf `40739def` (each diffed against `origin/throwaway-shutdown-ui`).
- **Context.** Round-1 `judge-ui.md` (M1–M12, SHARED CONTRACT §1–§5, ROUND-2 SEQUENCING), plus the convergence sections of `judge-proc.md` and `judge-gltf.md`. Also ADR 0007 and `docs/CONTEXT.md` (Conventions, glossary).

Paths are relative to `angular-client/src/pages/shutdown-page/` unless stated. C3D = `components/car-view-3d/`.

## Checks run

| Check | ui | procedural | gltf |
|---|---|---|---|
| `npx eslint src/pages/shutdown-page` | clean | clean | clean |
| Prettier `--check` on the shutdown page | clean | clean | clean |
| `ng test --include=src/pages/shutdown-page/**` | 16 files, 243 pass | 22 files, 319 pass | 25 files, 357 pass |
| `.css` files and `styleUrls` under the shutdown page | none | none | none |
| Removed names (`cssClass`, `--sd-*`, `resolveStateColours`, `FALLBACK_STATE_COLOURS`, `DEFAULT_SCENE_COLORS`, `shutdown-states`, `rovingIndex`, `STALE_AFTER_MS`/`isLive`/`computeLoopStatus` in UI code) | none | none | none |
| Hex colours | only `MISSING_THEME_COLOUR` | plus the three.js light and clear colours | plus the light and clear colours |
| `dark:`, `::ng-deep`, `!` modifier, palette classes | none | none | none |

**Byte-identical between procedural and gltf** (checked with md5):
- `shutdown-loop.positions-3d.ts` and its spec
- `C3D/car-view-3d.projection.ts` and its spec
- `C3D/car-view-3d.tokens.ts`
- `components/car-view-mode/*` (ts, html, spec)
- `package.json` and `package-lock.json` (`three`/`@types/three` 0.187.0, exact pins)

Neither 3D branch touches any shared UI file. Their delta is only `car-view-3d/`, `car-view-mode/`, the positions file, the page component, packages and docs.

**Different between the two**, all in places the "keep the seams identical" plan covers:
- `C3D/car-scene.types.ts`, `C3D/car-view-3d.utils.ts`, the component files and `car-scene.ts`;
- `shutdown-page.component.{html,ts,spec.ts}`.

The two arbitrary values the prompt names appear only in 3D: `h-[clamp(…)]` in both 3D stages, and `text-[10px]` in gltf.

Arbitrary values in the ui branch are all non-colour layout values, which the lint config and CONTEXT.md allow:
- `grid-cols-[…]`, `min-w-[7ch]`;
- translate `calc()`s, `w-[calc(100%+4px)]`;
- `animate-[ping…_3]`.

## Trial merge of the two 3D branches

I made a scratch worktree from the shared store at `/tmp/claude-0/-home-user-Delphi/6e25b80b-05af-58e5-9050-4f2faa446aec/scratchpad/r2rev-ui-spec/merge`: procedural checked out, then `git merge --no-commit origin/throwaway-shutdown-3d-gltf`. The real worktrees were untouched.

- **What merges cleanly:** everything shared, including the contract, positions, projection, tokens, car-view-mode, packages, `angular.json`, `nginx.conf` and docs. `shutdown-page.component.html` auto-merges too.
- **Conflicts:** 8 files, 24 hunks.
  - 7 are add/add files in `car-view-3d/`: `car-scene.ts` (3 hunks), `car-scene.types.ts` (1), `component.html` (1), `component.ts` (3), `component.spec.ts` (3), `utils.ts` (7) and `utils.spec.ts` (3).
  - The eighth is `shutdown-page.component.ts`, with 3 hunks. Procedural moves focus on fallback and gltf does not (N6).
- **Taking one side wholesale for the conflicted files does not compile.** `tsc -p tsconfig.spec.json` fails either way.
  - **gltf side: 5 errors.** `procedural-car.ts`/`.spec.ts` import `SceneColours` from `car-scene.types`. Procedural's page spec uses a sync `CarScene` with `focus`.
  - **procedural side: 4 errors.** `car-model.ts` needs `parseNodeAnchorName`, `hasExactAnchorPrefix` and `unitScaleFor` from utils. `load-car-model.ts` calls `new CarSceneError('model', {cause})`.
- **Verdict.** The page-level seams (contract, frame, projection, tokens, switch) combine mechanically.
  - The scene seam does not. `car-scene.types.ts` and the shared pure helpers in `car-view-3d.utils.ts` still have two shapes and two sets of names (N3).
  - A later combined branch needs roughly a half-day `CarSource` refactor, not a file copy.

## Round-1 MUST status (items under this lens)

| Item | Status | Evidence |
|---|---|---|
| **M1** Shared contract lands first | **VERIFIED-FIXED** | Contract commit `c27fbe3f` comes before the rest of round 2. The details follow the table. |
| **M3** (contract part) Listbox bridge | **VERIFIED-FIXED** (structure) | `loop-view/loop-node-listbox.directive.ts` exists. Strip and car use `ngListbox selectionMode="explicit" orientation="horizontal" [wrap]="false"`. `rovingIndex` is gone. `onKeydown` exists only in the directive, by design. `store.select()` clears the preview. Interaction behaviour is left to the other lenses. |
| **M9** (contract part) `segmentState` | **VERIFIED-FIXED** | `display.ts:126`. Used by the strip, the 2D car, procedural (`buildLoopSegments`, utils.ts:84) and gltf (`sceneStatus`, utils.ts:132). Label specs exist (display.spec:194-228). |
| **M10** (contract part) Distinct `(icon, dash, emphasis)` | **VERIFIED-FIXED** (spec) | display.spec:111. Both 3D branches derive tube radius from `WIRE_WIDTH` and dashes from `StateDisplay.dash`. The visual check is left to the other lenses. |
| **M12** Tests that prove the contract | **VERIFIED-FIXED** for strip, 2D car and page; **PARTIAL** for 3D | `loop-view.contract.ts` runs from the strip and car specs. The bracket test asserts "Broke the loop"/"Suspect stretch". The page spec covers the banner chip reaching all views. The 3D specs run it with `options:false`, which leaves 4 checks and none of rule 4 (N8). |
| **SEQ §3** procedural adopts the contract | **VERIFIED-FIXED** | See the procedural details after the table. |
| **SEQ §3** gltf adopts the contract | **PARTIAL** | See the gltf details after the table. |
| M2, M4–M8, M11 | out of lens | — |

**M1 acceptance in detail:**
- `StateDisplay` has `token`, `dash` and `emphasis` (`display.ts:19-39`).
- `shutdown-loop.theme.ts` exists with `cssVarReader`, `readThemeColour` and `MISSING_THEME_COLOUR`.
- `readStateColours` is at `display.ts:115`.
- `loop-view.ts` exports `LoopView` and `CarLoopView`, matching §3 member for member. `LoopStripComponent implements LoopView` and `CarViewComponent implements CarLoopView`.
- `loop-node-detail`/`LoopNodeDetailComponent` exists.
- `NodeStatus.staleAfterMs` is in logic's `utils.ts:23,160`, and ui adds a utils spec for it.
- The token/class spec is at display.spec:80-88. The `SHORT_LABEL` completeness spec is at :66.
- The glossary has "Loop node" (CONTEXT.md:45) and the Node ambiguity entry (:104).

**The deviations the contract agent listed:**
- `LoopStretch` narrows the types, and `loopOf(nodes)` is added. Both are acceptable. `loopOf` wraps logic's `summarizeLoop`, the same function `resolveLoopStatus` uses, so a view's summary always equals the page's.
- The contract helper's options are optional. Acceptable.
- The 2D car's `ngOption [label]` uses the full label where the contract says `SHORT_LABEL` (N12).

**Procedural adoption (SEQ §3):**
- `CarView3dComponent implements CarLoopView`, with no local selection, no detail panel and no loop-node toolbar.
- Colours come only from `readSceneColours` → `readThemeColour` + `readStateColours`. HV is `--color-secondary-border`.
- Wires use `segmentState`, with `WIRE_RADIUS` from `WIRE_WIDTH` and dashes from `StateDisplay.dash`.
- The stage is `role="img"` with `loopSummary`. Badges are `aria-hidden` and pointer-only.
- The camera `effect` follows `selectedId` only.
- With `interactive=false` it shows only `highlight ?? break` and doesn't pick (verified live at 390, screenshot below).
- The spec runs `expectLoopViewContract(…, {options:false})` and the token spec.
- `unavailable` feeds the page's 2D `@else`. There are no `styleUrls`.

**gltf adoption (SEQ §3):** the same items hold, with three gaps:
- **No camera effect.** judge-gltf R14 rejected the fly-to, so this is accepted. Note that it contradicts contract §3 rule 4's wording.
- **The `interactive=false` rule is broken live (N1).**
- **No focus handling on fallback (N6).**

## New findings

### N1 · major · gltf: in the phone overview (`interactive=false`) every one of the 19 badges still shows

- **Where:** `C3D/car-view-3d.component.ts:60-61` (`BADGE_BASE` contains `inline-flex`) and `:167` (adds `tw('hidden')`).
- **Issue.** The class list ends up with both `hidden` and `inline-flex`. Tailwind emits `.inline-flex` after `.hidden`, so `display: inline-flex` wins.
  - `placeBadges` then sets `visibility: visible`, so every badge is drawn.
  - Contract §3 rule 4 ("only the active loop node's badge shows") fails. Procedural shows one badge.
  - The badges can't be clicked (`interactive() && toggle`), but they cover the car at 390 px, which is the clutter the overview exists to remove.
  - This is exactly the class-order coin toss that ADR 0007 and `typography.ts` warn about: two classes from the same family on one element.
- **Steps:** `localStorage['argos.shutdown.carView']='3d'`, open http://localhost:4203/shutdown at 390×844, wait 5 s.
- **Evidence:**
  - Computed `display:flex; visibility:visible` on a badge whose class list contains `hidden`. The sheet order is `.hidden{display:none}` then `.inline-flex{display:inline-flex}`.
  - 19 of 19 badges are visible, against 1 of 1 on :4202.
  - Screenshots: `pictures/throwaway-shutdown-3d-gltf/review-r2/overview-390-stored-3d.png` and `pictures/throwaway-shutdown-3d-procedural/review-r2/overview-390-stored-3d.png`.
- **Why the spec misses it.** Spec :309-322 asserts `classList.toContain('hidden')`, which jsdom accepts without applying any styling.
- **Fix.** Filter in the `badges` computed, as procedural does (`interactive() ? all : all.filter(id === active ?? break)`). Alternatively, make display a single family: `interactive() || active ? 'inline-flex' : 'hidden'`, and drop `inline-flex` from `BADGE_BASE`. Change the spec to count the rendered badges.

### N2 · minor · the shared `car-view-mode.component.ts` reads `localStorage` outside its try/catch

- **Where:** `components/car-view-mode/car-view-mode.component.ts:25` and `:40`. This file is byte-identical in both 3D branches.
- **Issue.** `readCarViewMode` and `writeCarViewMode` default `storage = globalThis.localStorage` in the parameter list. That runs before the `try`, so in a browser where touching `localStorage` throws, the page's field initializer `signal(readCarViewMode())` throws.
  - The doc comment says it handles blocked storage, and judge-ui §3 rule 6 asked for try/catch.
  - The spec only covers a `getItem` that throws, not the getter.
- **Steps:**
  1. Load each client at `/`.
  2. In the page, redefine `window.localStorage` as a throwing getter.
  3. Navigate in-app to `/shutdown` (`pushState` + `popstate`).
- **Evidence:**
  - ui (:4201) renders the page.
  - procedural (:4202) and gltf (:4203) log `ERROR SecurityError: The operation is insecure.`, and the router ends on `/graph` with no `shutdown-page`.
  - A fresh load with storage blocked already fails in the app shell on every branch, so this is reachable only mid-session. That is why it is minor.
- **Fix.** Make `storage` optional, resolve `storage ?? globalThis.localStorage` inside the `try` in both helpers, and add a "getter throws" spec. Apply it byte-identically in both branches.

### N3 · minor · integration: the scene seam and the shared pure helpers diverge, so the branches don't combine mechanically

- **Where:** `C3D/car-scene.types.ts` and `C3D/car-view-3d.utils.ts` in each branch.
- **Issue.** The two branches disagree on:
  - **The factory.** Procedural's `CarSceneFactory` is sync, with `onPick`/`onHover` callbacks plus `focus` and `setInteractive`. gltf's is async, with `pick()`, `loadModel` and `setMaterialMode`. judge-gltf's convergence §3 asked for one async factory with `pick`. The byte-identical `car-view-3d.tokens.ts` therefore types `CAR_SCENE_LOADER` against two different `CarSceneFactory`s.
  - **The fallback names.** `FallbackReason` is `'context-lost'` in procedural and `'context'`/`'model'` in gltf. `CarSceneError` takes no reason in procedural and `(reason, {cause})` in gltf.
  - **Duplicated helpers.** `MARKER_SHAPE` and `MARKER_SHAPES` hold the same map. `dashPieces` and `isWebGLAvailable` are copied in both. The metres-per-px constants differ: `WIRE_METRES_PER_PX 0.0067`/`DASH_SCALE 0.007` against `SVG_UNIT_M 0.006`.
  - **Scene colours.** `SceneColours` lives in `car-scene.types.ts` in procedural and in `utils.ts` in gltf.
- **Failure scenario.** The trial merge above: 7 add/add conflicts, and either side fails `tsc` (5 or 4 errors).
- **Fix.**
  - Move the source-independent parts into one byte-identical file, for example `C3D/car-view-3d.common.ts` with its spec: `MarkerShape` and its map, `dashPieces`, `isWebGLAvailable`, the wire radius and dash maths from `WIRE_WIDTH`, and `FallbackReason`/`CarSceneError`/`FALLBACK_NOTICES` with a superset of reasons.
  - Agree on one `CarScene` interface. Car-source-specific methods (`loadModel`, `setMaterialMode`, `focus`) can be optional members.

### N4 · minor · gltf: the mismatch pip breaks the type-scale rule and diverges from every other view

- **Where:** `C3D/car-view-3d.component.html:349-353`: `text-[10px] font-black` with a literal "!".
- **Issue.** CONTEXT.md says "Font sizes come from the type scale; an arbitrary size only when it must follow the viewport". This one does not follow the viewport.
  - The strip, the 2D car and procedural's 3D badge all draw `<ui-icon name="priority_high" size="xs">` in a `bg-warn text-on-status` pip (judge-ui S4).
  - The lint passes only because arbitrary non-colour values are allowed.
- **Fix.** Use procedural's pip markup (`grid size-3.5 place-items-center rounded-full bg-warn text-on-status` + `<ui-icon name="priority_high" size="xs" />`). Update the spec's `toContain('!')` to check the icon.

### N5 · minor · gltf: when nothing is active, the overview shows no badge; procedural and 2D show the break

- **Where:** `C3D/car-view-3d.component.ts:161-167`. `active` is only `previewId ?? selectedId`.
- **Issue.** Once N1 is fixed, a phone with 3D stored and no pin shows no badge at all. The 2D overview (M5: "the highlighted loop node, or else the break") and procedural (`highlightId() ?? breakId()`) both name the break.
  - Contract §3 rule 4 literally says "only the active loop node's badge", so both readings are defensible, but they differ.
- **Fix.** Use `active() ?? break` for the overview in gltf, and reword rule 4 in `loop-view.ts` to "the active loop node's, else the break's".

### N6 · minor · the fallback's focus handling differs; gltf drops focus to `<body>`, and procedural's target has no visible focus

- **Where:** gltf `shutdown-page.component.ts:68-72`, procedural `shutdown-page.component.ts:73-88` and `.html:43-46`.
- **gltf.** When 3D falls back while focus is inside it (on a View or Model button, for example a model that times out after 20 s while the user presses "Side"), the `@if` swap removes the focused element. Focus lands on `<body>`, which breaks the CONTEXT.md rule "Move focus after an action with `injectFocusAfterRender`, so it never drops to `<body>`".
- **Procedural.** It moves focus to the `<section tabindex="-1">`, which has `outline-none`, so a keyboard user sees no focus.
- **Effect.** This is also the only `shutdown-page.component.ts` conflict in the trial merge.
- **Fix.** Write one byte-identical `onCarUnavailable` in both branches. Focus the `car-view-mode` "2D" button through `injectFocusAfterRender`, or keep the section target and give it `focus-visible:focus-ring`.

### N7 · minor · docs: ADR 0010 and the spec amendment exist only on procedural, but claim to cover both

- **Where:** procedural `docs/adr/0010-angular-client-three-js-3d-car-view.md:3` and `docs/spec/shutdown-loop-page/spec.md:144`; gltf `docs/spec/shutdown-loop-page/car-model.md:3`.
- **Issue.** judge-proc S10 asked for the ADR and the spec line to be byte-identical in both branches. judge-gltf R4 rejected them for gltf. The round-2 result contradicts itself:
  - The ADR's status line says "written on the throwaway branches `…-procedural` and `…-gltf`", but gltf doesn't have it.
  - The ADR's "Why this shape" describes "HTML badges and the suspect's halo … a CSS animation on its halo". gltf has no halo or ping.
  - gltf's `car-model.md` says "The spec still says option A, chosen", but after a merge it would sit next to procedural's amendment.
- **Fix.** The coordinator decides once, between two options:
  - keep the ADR procedural-only, drop "and `throwaway-shutdown-3d-gltf`", and mark the halo bullet as procedural's;
  - or copy the ADR and spec line into gltf, and make the halo bullet source-neutral.

### N8 · minor · test quality: the 3D half of the contract is tested ad hoc, and differently in each branch

- **Where:** `loop-view/loop-view.contract.ts:142` (`if (!domOptions) return;`). Procedural `car-view-3d.component.spec.ts:87-93,152-162`, gltf `:235-241,309-322`.
- **Issue.** With `options:false`, the shared helper runs 4 checks: no emit on load, click toggles, hover/leave, and highlight. Nothing shared covers contract rule 4:
  - `role="img"` labelled with `loopSummary`;
  - `aria-hidden` badges and no tab stops;
  - `interactive=false`: no picks or previews, and only the active badge (or the break's).
- **How the branches differ.** Each 3D spec asserts rule 4 its own way. Procedural counts `[role="option"], [tabindex="0"]`. gltf counts `[data-node-id][tabindex], [aria-live]` and checks for a `hidden` class, which is how N1 got through.
- **Fix.** Add a `canvasView` section to `expectLoopViewContract` that runs when `options:false`. It needs a `shownBadges(fixture): string[]` hook and an `interactive` setter, and it asserts the image role and label, zero tab stops, no emits while `interactive=false`, and the overview badge set. Both 3D specs then share one definition. Visual properties still need the Playwright check.

### N9 · nit · gltf re-implements the shared `viewPose` inline

- **Where:** gltf `C3D/car-scene.ts:268-300` (`setView`) against the shared `car-view-3d.projection.ts:70` (`viewPose`).
- **Issue.** gltf rebuilds the camera axes and corner fit by hand. The byte-identical `viewPose` is used only by procedural and the projection spec, so in gltf it is dead code that duplicates logic.
- **Fix.** Call `viewPose(...)` for the initial fit and keep the re-centring passes as gltf's refinement, or move the refinement into the shared file.

### N10 · nit · the two 3D stages differ in size and frame, and the 3-ping halo is spelled two ways

- **Stage height.** Procedural uses `h-[clamp(240px,56vw,min(52vh,480px))]` with no border. gltf uses `h-[clamp(240px,60vw,min(50vh,480px))]` with `rounded-md border border-border`. The above-the-fold budget (M6) is a page decision, so the two should match, ideally as one recipe or constant.
- **The ping.** The 2D car uses `motion-safe:animate-[ping_1s_cubic-bezier(0,0,0.2,1)_3]`. Procedural's halo uses `motion-safe:animate-ping motion-safe:[animation-iteration-count:3]`. Pick one spelling.

### N11 · nit · camera presets: the contract says `aria-pressed`, neither branch has it, and the two differ

- **Where:**
  - procedural `car-view-3d.component.html:85-91`: `segmentedClasses`, no `aria-pressed`, order Iso/Side/Top;
  - gltf `:372-378`: `buttonClass('neutral','sm')`, no `aria-pressed`, order Side/Top/Iso.
- **Issue.** The presets are momentary actions (the user can orbit away), so leaving out `aria-pressed` is right. The contract text (judge-ui §3 rule 5) should say "segmented `aria-pressed` for persistent modes (CAD/Theme/Ghost), plain buttons for presets". The branches should also agree on the order and the recipe.

### N12 · nit · the 2D car's `ngOption [label]` is the full label; the contract says `SHORT_LABEL`

- **Where:** `components/car-view/car-view.component.html:89`. The strip (`loop-strip.component.html:28`) uses `short[...]`.
- **Issue.** Typeahead differs between the two listboxes. Either align the car to `SHORT_LABEL`, or record the deviation in `loop-view.ts`.

### N13 · nit · terminology: the mock panel's group label says "per node"

- **Where:** `components/mock-panel/mock-panel.component.html:22`: `aria-label="Reading per node: …"`.
- **Fix.** §5 copy rule: "Reading per loop node: pressed = 1 (closed)". This is the last user-facing unqualified "node" I found on the page.

### N14 · nit · the comment calls `MISSING_THEME_COLOUR` "the one hex value in shutdown code"

- **Where:** `shutdown-loop.theme.ts:27`.
- **Issue.** Both scenes also hard-code light colours. Procedural uses `HemisphereLight(0xffffff, 0x202020)` (`car-scene.ts:102`) and gltf `0x303030` (`:176`). Both also have `setClearColor(0x000000, 0)`.
- **Fix.** These are lighting, not theme colours, which is fine. Reword the comment ("the one hex colour drawn as a theme colour") and pick one ground-light value.

### N15 · nit · each branch puts its page-level 3D specs somewhere different, under the same name

- **Where:** procedural adds `describe('ShutdownPageComponent car view mode')` to `shutdown-page.component.spec.ts`. gltf adds the same describe in a new `shutdown-page.car-mode.spec.ts`.
- **Issue.** A combined branch carries both copies. Use the separate file in both branches, byte-identical.

### N16 · nit · a display spec's title claims more than it checks

- **Where:** `shutdown-loop.display.spec.ts:95`, "danger only for the cause, never the accent".
- **Issue.** It asserts the four tokens but nothing about `--color-accent`.
- **Fix.** Add `expect(Object.values(NODE_STATE_DISPLAY).map(d => d.token)).not.toContain('--color-accent')`, plus a `stateColoursIn`-style scan that `accent` appears in no class list.

## Counts

Blocker 0 · major 1 · minor 7 · nit 8.

Of the round-1 MUSTs under this lens: 5 are VERIFIED-FIXED (M1, M3 contract part, M9, M10 spec part, procedural's SEQ §3 adoption) and 2 are PARTIAL (M12 for 3D, gltf's SEQ §3 adoption).

## Artefacts

- Screenshots in `/home/user/Delphi/pictures/throwaway-shutdown-3d-{procedural,gltf}/review-r2/`:
  - `overview-390-stored-3d.png` is the N1 evidence.
  - `blocked-storage-1280.png` is blank. It shows that a fresh load with storage blocked fails on every branch, the app-shell baseline for N2. It is not N2 itself.
- Scripts in `/tmp/claude-0/-home-user-Delphi/6e25b80b-05af-58e5-9050-4f2faa446aec/scratchpad/r2rev-ui-spec/`: `overview.js`, `overview2.js`, `blocked.js` and `blocked2.js`.
- The trial-merge worktree is `/tmp/claude-0/-home-user-Delphi/6e25b80b-05af-58e5-9050-4f2faa446aec/scratchpad/r2rev-ui-spec/merge`. It is detached, with an uncommitted merge, and has a `node_modules` symlink to gltf's. Remove it with `git -C /home/user/Delphi/worktrees/argos/.bare worktree remove --force <path>` when it is no longer needed.
