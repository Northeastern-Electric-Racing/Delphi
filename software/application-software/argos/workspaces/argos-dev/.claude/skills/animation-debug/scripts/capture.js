// The animation-debug capture, for capture.sh to run with `playwright-cli run-code` (it replaces the args
// placeholder below with a JSON object). Screenshots can't keep up with a 100 ms animation (each takes
// 30-100 ms), so where it can, this freezes the animations and steps their time: frames are the same on
// every run. Otherwise it takes screenshots in real time. Returns text for capture.sh to print.
async (page) => {
  const { url, out, action, target, windowMs, stepMs, mode, setup } = __ARGS__;

  // a frame every `stepMs` over the window: the first at 0, the last at the window (or the last step inside it)
  const times = [];
  for (let t = 0; t <= windowMs; t += stepMs) times.push(t);
  const frames = times.length;
  const frame = (i, t) => `${out}/${String(i + 1).padStart(2, '0')}-${t}ms.png`;

  // the whole page ('allow' leaves paused animations as set; 'disabled' would jump them to the end)
  const shoot = (path) => page.screenshot({ path, animations: 'allow' });

  // Date.now() can step backwards when the machine's clock re-syncs (it did on WSL), and run-code has no
  // monotonic clock, so never let this one go back
  let last = 0;
  const now = () => (last = Math.max(last, Date.now()));

  let triggeredAt = 0;
  const trigger = async () => {
    for (const sel of setup) await page.locator(sel).first().click({ timeout: 15000 });
    const el = page.locator(target).first();
    await el.waitFor({ timeout: 15000 });
    if (action === 'hover') await el.hover();
    else await el.click();
    triggeredAt = now();
  };

  // Real time, nothing paused: a screenshot every `stepMs`, or back to back when they take longer, each named
  // by when it was taken (ms after the trigger), so frames differ between runs. For what pausing can't freeze,
  // such as a chart drawing in as data arrives.
  const burst = async (why) => {
    const stamps = [];
    for (let n = 0; n < frames; n++) {
      stamps.push(now() - triggeredAt);
      await shoot(frame(n, stamps[n]));
      const wait = times[n + 1] - (now() - triggeredAt);
      if (n + 1 < frames && wait > 0) await page.waitForTimeout(wait);
    }
    const gaps = stamps.slice(1).map((s, i) => s - stamps[i]);
    return `captured ${frames} frames in real time${why}, named by when each was taken` +
      (gaps.length ? `\n    actual spacing ${Math.min(...gaps)}-${Math.max(...gaps)} ms (asked for ${stepMs})` : '');
  };

  // forced real time, even if animations are running
  if (mode === 'live') {
    await page.goto(url);
    await trigger();
    return burst('');
  }

  // timer or requestAnimationFrame animations, which pausing can't reach: step the page's fake clock instead
  if (mode === 'clock') {
    // The fake clock keeps running until paused, so pause from the page's own time. It is resumed before
    // returning: a paused clock stops the page timers that playwright-cli waits on, and it would hang.
    await page.clock.install();
    await page.goto(url);
    // Align the pause to the fake requestAnimationFrame's 16 ms grid, which counts from install (it is
    // performance.now()'s), or load time shifts every frame.
    await page.clock.pauseAt(await page.evaluate(() => {
      const offset = Date.now() - performance.now();
      return Math.round(Math.ceil((performance.now() + 1000) / 16) * 16 + offset);
    }));
    await trigger();
    for (const [i, t] of times.entries()) {
      if (i > 0) await page.clock.runFor(t - times[i - 1]);
      await shoot(frame(i, t));
    }
    await page.clock.resume();
    return `captured ${frames} frames with the page clock, every ${stepMs} ms over ${windowMs} ms`;
  }

  // Web Animations (Angular animations, CSS transitions and animations): pause every running animation, then
  // set each one's currentTime to the step. A finished animation is rewound, not lost, because the list is
  // kept on window. With none running, fall back to real time.
  await page.goto(url);
  await trigger();
  const count = await page.evaluate(async () => {
    // two refreshes, so the animation the trigger caused has started (Angular starts them on the next pass)
    await new Promise((r) => requestAnimationFrame(() => requestAnimationFrame(r)));
    window.__debugAnimations = document.getAnimations();
    window.__debugAnimations.forEach((a) => a.pause());
    return window.__debugAnimations.length;
  });
  if (count === 0) return burst(' (no animation to freeze)');
  for (const [i, t] of times.entries()) {
    await page.evaluate((ms) => window.__debugAnimations.forEach((a) => { a.currentTime = ms; }), t);
    await shoot(frame(i, t));
  }
  return `captured ${frames} frames of ${count} animation(s), every ${stepMs} ms over ${windowMs} ms`;
}
