# Round 1 review: live UX, visual design, accessibility (`throwaway-shutdown-ui`)

Tested at http://localhost:4201/shutdown with the live Calypso sim, and with the socket blocked (`page.route('**/socket.io/**')`) so the dev mock presets could be seen without the sim overwriting them. Viewports: 1440x900, 1280x720, 390x844 (isMobile). Compared against /efuses and /charging. axe-core 4.10.2 found one violation on every state: `page-has-heading-one`. eFuses and Charging fail the same rule, so the whole app has it. Contrast checks all passed. Reduced motion is honoured: `animate-ping` computes to `none` under `prefers-reduced-motion: reduce`. The keyboard focus ring shows clearly (2px #d4d4d4, offset 2px). Scripts are in `scratchpad/r1-ui-live/`.

Counts: **0 blocker · 7 major · 12 minor · 8 nit**

## Major

- **major — The loop strip (the spec's "main diagnostic read") is below the fold on desktop and laptop**
  - Where: `shutdown-page.component.html` grid; 1440x900 and 1280x720.
  - Issue: the car view takes the first row (538px tall at 1440, 453px at 1280), with the strip in row 2. The strip starts at y=897 at 1440x900 (y=941 when a warning row shows) and at y=812 at 1280x720. You can't see it on either screen without scrolling. The spec calls the strip "the main diagnostic read" and the car "where it sits", but the car gets the space.
  - Steps: open /shutdown at 1440x900 without scrolling.
  - Fix: put the strip in row 1, full width (`lg:row-start-1 lg:col-span-2`), with car and detail below it. Or cap the car: `max-h-[42vh]` on the `aspect-[1000/535]` box (with `w-auto mx-auto`), so banner, strip and car fit in 900px.
  - Screenshots: `pictures/throwaway-shutdown-ui/review-r1/desktop-1440-live-sim.png`, `laptop-1280-break-bms-latch.png`

- **major — The culprit's name is the smallest text in the verdict, so it fails the 2-second, arm's-length read**
  - Where: `loop-banner.component.html` / `chipBase`; all viewports.
  - Issue: size order is page title 40px > "LOOP OPEN" 34px > culprit chip 16px (`text-base`), which is no bigger than the "Cause:" label. In a zoomed-out view (simulating arm's length) "LOOP OPEN" reads easily but "TSMS" is hard to make out, and naming the culprit is the page's whole job.
  - Steps: Mock → Publish → Break at TSMS, then step back from the screen.
  - Fix: put the culprit in the title for a single suspect ("LOOP OPEN · TSMS", same `text-xl font-black`). For several suspects, make the chips `text-lg`/`text-title` with `min-h-10`. Drop the page title to `text-title` on this page so it doesn't outrank the verdict.
  - Screenshots: `desktop-1440-arms-length-sim-mismatch.png`, `desktop-1440-mismatch-hvd-full.png`

- **major — The live region speaks constantly with live data: 45 announcements in 20 s**
  - Where: `loop-banner.component.html` `role="status" aria-live="polite"`, the `announcement()` computed; live sim, 1440.
  - Issue: the code comment says it is "not re-announced every tick", but the text includes the suspect list and the mismatch list. Both change whenever a bit flips, so a screen reader is interrupted about twice a second ("LOOP OPEN — cause: IMD latch" / "…one of: Side BRB R, Side BRB L, BMS latch" / "…Sensor mismatch: MC HVIL…"). A bouncing connector on the real car would do the same.
  - Steps: load /shutdown with the sim running and watch mutations of `[role=status]` (`s3.js` logs them).
  - Fix: update the live text only after the verdict and suspect set have been stable for about 2–3 s (debounce signal), and rate-limit to one announcement per about 5 s. Or announce only verdict changes (open/closed/unknown) and leave suspect detail to the banner text, which can be read on demand. Keep the mismatch out of the polite region, or announce it once per episode.
  - Screenshot: `flap-1440-t0.png` / `flap-1440-t1.png` (same second, different culprit)

- **major — The page jumps 44px whenever the mismatch or silent-board row appears or disappears (CLS 0.29 in 20 s)**
  - Where: `loop-banner.component.html` `<ul>` of warnings; all viewports, live sim.
  - Issue: with flapping data the mismatch `<li>` mounts and unmounts. The banner host's height goes 150 ↔ 194px, which moves the car, strip and detail panel up and down by 44px (24 layout-shift entries, cumulative 0.293; Google's "poor" threshold is 0.25). Anyone reading the strip or about to click a marker loses their place. The detail `<dl>` and the callout add smaller shifts.
  - Steps: `s3.js` runs a PerformanceObserver for `layout-shift`. The banner height samples are 150 and 194.
  - Fix: always render the warning slot with a fixed `min-h-10`, showing a quiet "No sensor warnings" line when empty. Or move the warnings into the banner box as a second row that's always present. Or show them as a badge in the header row. Also hold a mismatch warning for at least 3 s once shown.
  - Screenshots: `desktop-1440-live-sim-full.png` (with row), `desktop-1440-break-acc-sense-full.png` (without)

- **major — No hold or hysteresis on the verdict: with flapping inputs the culprit, callout, strip bracket and detail panel change several times a second**
  - Where: banner, `car-view` callout, `loop-strip` brackets, `node-detail`; live sim at every viewport.
  - Issue: with the sim, the culprit cycles through BMS latch → IMD latch → BSPD latch every 0.2–1 s. An engineer can't read anything in 2 s, and an intermittent fault (the very thing a trackside engineer chases) looks like noise rather than being named.
  - Steps: load with the sim and take screenshots 1 s apart (`flap-1440-t0/t1/t2`).
  - Fix: hold each displayed break for at least 2 s unless a newer one stays stable for about 500 ms. Add an "Intermittent: changed 12× in 10 s, between BMS latch, IMD latch, BSPD latch" warn chip under the verdict. This is still live-only: a short in-memory window, not replay.
  - Screenshots: `flap-1440-t0.png`, `flap-1440-t1.png`

- **major — On the phone, car markers overlap into blobs and fail the 24px minimum target size (WCAG 2.5.8)**
  - Where: `car-view.component.html` markers `size-5 … sm:size-7`; 390x844.
  - Issue: markers are 20px, but many centre-to-centre distances are only 10–11px: BMS/IMD/BSPD/CAN latches, the four sense points with the AIRs, the two side BRBs, inertia and cockpit BRB. GLVMS overlaps TSMS at 15px. Tapping picks an arbitrary neighbour, and the callout covers the side BRBs. At 1280 there are 9 more overlapping pairs at 24–27px for 28px markers.
  - Steps: `s8.js` lists overlapping pairs per viewport.
  - Fix: below `sm`, make the car view a non-interactive overview (`aria-hidden`, no tab stop; the strip is the control) and give it more height. Or let the car scroll horizontally at about 700px wide. Or nudge clustered nodes apart in the `car` coordinates for narrow widths, or collapse each cluster into one group badge ("4 latches") that expands into the strip.
  - Screenshots: `phone-390-break-bms-latch-full.png`, `phone-390-mismatch-hvd.png`

- **major — In the car view, status is colour-only on phones and on the wiring everywhere; under deuteranopia or protanopia, closed and cause look identical**
  - Where: `car-view.component.html` (`status-glyph class="max-sm:hidden"`), segment strokes from `NODE_STATE_DISPLAY.*.stroke` / `dash`; 390x844 and all widths for wiring.
  - Issue: below `sm` the glyph is hidden, so the only difference between closed and cause markers is green vs orange (`success` #4ade80 vs `danger` #fb923c). Both simulate to the same yellow. On every viewport, closed and cause segments are both solid (cause is 4px instead of 3px), so the simulated wiring looks the same. The frame PNG's dimmed red tubes also turn olive in the simulation and blend with both colours. The spec says "Status must not rely on colour alone".
  - Steps: Break at BMS latch with the feColorMatrix deuteranopia filter (`s6.js`).
  - Fix: keep the glyph at every width (`size-6` disc with `xs` glyph). Give cause segments a pattern of their own, such as a halo (a second wider `stroke-page` line under it) or `dash: '10 3'`, so solid means closed. Use `grayscale` on the frame `<img>` (or `opacity-30 grayscale`) so the drawing never shares a hue with the statuses.
  - Screenshots: `phone-390-cvd-deuteranopia-break-bms-latch.png`, `desktop-1440-cvd-deuteranopia-break-bms-latch.png`, `desktop-1440-cvd-protanopia-break-bms-latch.png`

## Minor

- **minor — The strip doesn't fit at 1280 and gives no hint that it scrolls; at 1440 it overflows by 2px**
  - Where: `loop-strip.component.html` (`w-18` items, `w-max` list, `px-1`); 1280x720 and 1440x900.
  - Issue: 19×72px + 8px = 1376px. At 1280 the content area is 1214px, so TS+ and AIRs (the outcome node) are cut off, the label "TS− Upstrean" is clipped, and the "Not the cause" bracket label is hidden, with no fade or arrow to say there's more. At 1440 the scroll width is 1376 against a client width of 1374. On Windows trackside laptops (classic scrollbars) that 2px shows a 15px scrollbar.
  - Fix: at `lg`, make items `flex-1 min-w-14` with a `w-full` list so all 19 fit from about 1100px up. When it does scroll, add an edge fade (`[mask-image:linear-gradient(90deg,#000_90%,transparent)]`) and keep AIRs pinned.
  - Screenshot: `laptop-1280-strip-break-acc-sense.png`

- **minor — The default callout covers neighbouring markers**
  - Where: `car-view` `[data-callout]`; 1280 Break at TSMS, 390 every break.
  - Issue: the callout always sits 18px above the marker. At 1280 with a break at TSMS it covers side BRB R and side BRB L, and on phones it covers the side BRBs in every state. In the live 1440 view it clips the marker above the latch row.
  - Fix: flip the callout below the marker when another marker falls inside its box (a cheap rectangle test over `markers()`). Or show no callout by default, since the banner and detail already name the break, and show it only on hover or focus.
  - Screenshots: `laptop-1280-break-bms-latch.png`, `phone-390-break-bms-latch-full.png`

- **minor — The strip's auto-scroll snaps back whatever the user scrolled to every time the suspect changes**
  - Where: `loop-strip.component.ts` `afterRenderEffect` → `scrollIntoView`; 390x844, live sim.
  - Issue: after swiping to the end of the strip, the position went back to 0 four times in 7 s (scroll positions sampled: 1036, 0, 1036, 1036, 1036, 0, …).
  - Fix: auto-scroll only when the highlighted node changes because of the user, or when the stretch first appears. Skip it for 5 s after a `scroll`/`pointerdown` on the scroller.
  - Screenshot: `phone-390-live-sim.png`

- **minor — Nodes after the break are labelled "Upstream"**
  - Where: `NODE_STATE_DISPLAY['downstream-open'].short` / `.label` ("Open — upstream"); strip at every viewport.
  - Issue: under nodes that sit downstream of the break, "Upstream" reads as a location and contradicts where they are. "Not the cause" only appears in the bracket, which is often scrolled off.
  - Fix: use short "Not cause" (or "Downstream") and label "Open — downstream of break".
  - Screenshot: `desktop-1440-live-sim-full.png`

- **minor — The silent-board note says "for over 60 s" a few seconds after page load**
  - Where: `loop-banner.component.ts` `silentText()` with `boardFreshness().stale` true when `ageMs === undefined`; live sim (BMS never publishes).
  - Issue: 4 s after load the note reads "No data from BMS for over 60 s".
  - Fix: when the age is undefined, say "No data from BMS since the page opened…". Keep "for over 60 s" for stale boards.
  - Screenshot: `desktop-1440-live-sim.png`

- **minor — Keyboard focus pins the selection, and there is no visible way to get back to the break**
  - Where: `(focus)="nodeSelect.emit(…)"` in `car-view` and `loop-strip`, `node-detail`; keyboard at 1440.
  - Issue: just tabbing past the car view pins the first suspect. The detail panel switches to "SELECTED NODE" and stays there after focus leaves, even once the live break has moved elsewhere. Only Escape clears it, and nothing on screen says so. After Escape the focused option has `tabindex=-1`.
  - Fix: focus should `preview`, and Enter, Space or click should `select`. When something is pinned, show a "Show the break" button in the detail header that calls `select(null)`.
  - Screenshot: `kb-desktop-car-marker-focused.png`

- **minor — A mismatched node's state contradicts its reading**
  - Where: `nodeAriaLabel`, strip and detail for `mismatch`; Mismatch at HVD.
  - Issue: HVD reads 1, but it shows the dash glyph with "Upstream" and its accessible name is "HVD: Open — upstream, mismatch". The only hint is a tiny `text-badge` (11.2px) MISMATCH tag, and a 12–16px "!" on the car.
  - Fix: give mismatch its own presentation: warn border, `priority_high` glyph, short label "Reads 1", name "HVD: reads closed after the break — sensor mismatch".
  - Screenshot: `desktop-1440-mismatch-hvd-full.png`

- **minor — With nothing selected, the detail panel is a tall empty card, and the page has no legend**
  - Where: `node-detail` (`h-full`), the page; closed and unknown states at 1440.
  - Issue: a 560px card holds a single hint line. Nowhere does the page explain filled vs hollow (measured vs no sensor), dashed vs dotted wiring, or the glyphs, which the spec relies on ("so the gap in coverage is visible").
  - Fix: in that empty state, show a compact legend: one swatch per state, measured vs no-sensor ring, wire patterns. Use `h-fit` (or `lg:self-start`).
  - Screenshots: `desktop-1440-closed.png`, `desktop-1440-unknown.png`

- **minor — The cards don't look like the rest of Argos**
  - Where: the three `<section>`s in `shutdown-page.component.html` and `node-detail`.
  - Issue: eFuses and Charging cards are `bg-panel` (#2c2c2c), borderless, with an icon and title header (`info-background` / `cardClass()`). These are `bg-surface-1` (#1c1c1c) with a 1px `border-border`, and their headings differ (none, a tiny uppercase label, a bold `h2`). The same class list is repeated three times, against CONTEXT.md's "a look used in more than one place is a recipe".
  - Fix: use `<info-background>` or `cardClass()` with `bg-panel`, with an icon and title per card (e.g. `directions_car` "On the car", `linear_scale` "Loop order", `info` "Details").
  - Screenshots: `compare-efuses-1440.png`, `compare-charging-1440.png`

- **minor — Heading structure and screen-reader names need work**
  - Where: the page and `loop-strip` section.
  - Issue: there is no `h1` (axe `page-has-heading-one`); "Shutdown Loop" is a `<p>` from `typography`. The verdict is a `<p>`, so screen-reader heading navigation skips it. The `h2` name includes the hint ("Loop order GLV source → AIR coils · arrow keys move between nodes"), and the region inherits that name.
  - Fix: render the title as an `h1` (or `role="heading" aria-level="1"`). Make the verdict an `h2`. Move the hint into a `<p id>` referenced by `aria-describedby` on the listbox.
  - Evidence: the ARIA snapshot in `s10.js`.

- **minor — The banner chips don't separate the actual open reading from the no-sensor suspects**
  - Where: `loop-banner` chips; Break at BMS latch.
  - Issue: "Cause is one of: Side BRB R · Side BRB L · BMS latch" draws all three alike. The strip's own vocabulary (filled = measured, hollow = no sensor) is lost.
  - Fix: show the measured first-open reading as a solid chip with "reads 0". Show unmeasured suspects as a hollow or dashed chip with a "no sensor" suffix.
  - Screenshot: `desktop-1440-live-sim-full.png`

- **minor — The dev mock panel can't show its states while the sim runs, and can't set TS ON/OFF**
  - Where: `mock-panel.component.ts`.
  - Issue: after Publish + All closed with the sim up, the verdict cycles between closed, BMS latch, IMD latch and BSPD latch. The panel never publishes `BMS/Shutdown/State`, so the TS chip reads "TS —" while BMS shows "just now". I had to inject the state by hand to see TS ON.
  - Fix: while publishing, have the mock override live values for shutdown topics: gate `Storage.addValue` for those topics, or stamp mock values ahead of live. Add a TS ON/OFF toggle.
  - Screenshots: `phone-390-closed-ts-on.png`, `desktop-1440-closed-ts-on.png`

## Nits

- **nit — The TS chip's "TS —" is read as "em dash"**
  - Where: `loop-meta`.
  - Fix: add `<span class="sr-only">unknown</span>` and make the dash `aria-hidden`.

- **nit — Header chips jitter sideways each second**
  - Where: `loop-meta` and the detail "Updated" field.
  - Issue: the age text alternates "just now" ↔ "1 s ago", so the right-aligned header chips shift sideways (the detail `dl` also shows up in the layout-shift log).
  - Fix: `min-w-[7ch]` on the age span, or say "<1 s ago" instead of "just now".

- **nit — Strip columns have uneven heights**
  - Where: strip.
  - Issue: "Cockpit BRB" wraps to two lines, so that column is taller, and the placeholder and mismatch tags vary heights further.
  - Fix: short label "Ckpt BRB", or a fixed label height (`h-8 line-clamp-2`).

- **nit — The keyboard hint shows on touch devices**
  - Where: strip heading.
  - Issue: "arrow keys move between nodes" appears on phones.
  - Fix: `pointer-coarse:hidden` (custom variant) or `max-md:hidden`.

- **nit — The car image is larger than needed**
  - Where: `assets/images/car-frame-side.png`.
  - Issue: 1762×942, 267KB. Angular warns NG0913 (oversized image) on the phone.
  - Fix: a WebP plus a `srcset` at 1000w and 500w.

- **nit — No-sensor markers look like cogs**
  - Where: car view.
  - Issue: no-sensor markers downstream of the break use `border-dashed` with `sm:border-3` on 28px, which looks like a cog.
  - Fix: `border-2` for dashed rings.

- **nit — The cause marker pings indefinitely**
  - Where: car view.
  - Issue: the cause marker `animate-ping`s forever, and with three suspects three markers pulse at once. `motion-safe` is respected.
  - Fix: limit it to the measured break (the last suspect), or to the first about 5 s after a verdict change.

- **nit — Console errors come from the nav bar on every page**
  - Where: nav bar, out of scope.
  - Issue: repeated `NG0100 ExpressionChangedAfterItHasBeenChecked` from `CurrentRunDisplayComponent` and `MessagesPerSecondComponent` with live data. They appear on /efuses and /charging too, so they don't come from this branch. The shutdown page itself logs nothing.

(Screenshots are under `/home/user/Delphi/pictures/throwaway-shutdown-ui/review-r1/`.)
