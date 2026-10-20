async (page) => {
  // Live-mode cost of the graph page with __TOPICS__ selected: retained JS heap after a GC, how fast it allocates
  // (heap growth between 100 ms samples, GC drops ignored), and frame rate. Compare branches at the same topics.
  const topics = '__TOPICS__'.split(',');
  await page.goto(`__URL__/graph?topics=${encodeURIComponent(topics.join(','))}`);
  await page.getByText('Real Time').first().waitFor({ timeout: 30000 });
  const cdp = await page.context().newCDPSession(page);
  const heap = async (gc) => {
    if (gc) await cdp.send('HeapProfiler.collectGarbage');
    return (await cdp.send('Runtime.getHeapUsage')).usedSize / 1e6;
  };
  await page.waitForTimeout(20000); // fill the live window
  let alloc = 0, prev = await heap(false);
  const t0 = Date.now();
  while (Date.now() - t0 < 20000) {
    await page.waitForTimeout(100);
    const h = await heap(false);
    if (h > prev) alloc += h - prev;
    prev = h;
  }
  const allocMBps = alloc / ((Date.now() - t0) / 1000);
  const frames = await page.evaluate(() => new Promise((done) => {
    let n = 0, worst = 0, longTasks = 0, last = performance.now();
    const end = last + 10000;
    new PerformanceObserver((l) => (longTasks += l.getEntries().length)).observe({ type: 'longtask' });
    const tick = (t) => {
      worst = Math.max(worst, t - last);
      last = t;
      n++;
      if (t < end) requestAnimationFrame(tick);
      else done({ fps: n / 10, worstFrameMs: Math.round(worst), longTasks });
    };
    requestAnimationFrame(tick);
  }));
  const retainedMB = await heap(true);
  return `retained JS heap ${retainedMB.toFixed(1)} MB, allocating ${allocMBps.toFixed(1)} MB/s, ` +
    `${frames.fps} fps, worst frame ${frames.worstFrameMs} ms, ${frames.longTasks} long tasks`;
}
