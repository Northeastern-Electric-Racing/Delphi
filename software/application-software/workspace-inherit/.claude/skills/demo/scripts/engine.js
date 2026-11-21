// engine.js <out> <url> stills|video <from-step> <demo.js>...: run.sh's engine. Opens each demo's route in
// Chromium at 2x and runs its named steps. Stills skip dwells and write NN-<step>.png plus walkthrough.md
// (a caption per step). Video keeps real pacing with an in-page cursor, records a CDP screencast and
// encodes <demo>.mp4 (constant 30 fps, with ffmpeg) plus chapters.md (a timestamp per step). Steps before
// <from-step> run unpaced and unrecorded, and their stills stay in walkthrough.md. Each mode replaces only its
// own files. A failed step stops its demo with its name and failed-<step>.png.
'use strict';
const { chromium } = require('playwright');
const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');

const [out, url, mode, from, ...demos] = process.argv.slice(2);
const video = mode === 'video';
const slug = (s) => s.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '');
const clock = (s) => `${Math.floor(s / 60)}:${String(Math.floor(s % 60)).padStart(2, '0')}`;

/** Headless video has no pointer: draw one as a manual popover, re-raised whenever another popover opens,
 * so overlays in the top layer (CDK's are popovers) never cover it. */
function cursor() {
  const add = () => {
    const c = document.createElement('div');
    c.setAttribute('popover', 'manual');
    c.style.cssText = 'position:fixed;inset:auto;left:0;top:0;width:22px;height:22px;margin:-11px 0 0 -11px;padding:0;' +
      'border-radius:50%;background:rgba(255,255,255,.35);border:2px solid #fff;box-shadow:0 0 0 1px rgba(0,0,0,.6);' +
      'pointer-events:none;transition:transform .12s;transform:translate(-100px,-100px)';
    document.documentElement.appendChild(c);
    c.showPopover();
    addEventListener('toggle', (e) => { if (e.target !== c && e.newState === 'open') { c.hidePopover(); c.showPopover(); } }, true);
    let at = 'translate(-100px,-100px)';
    addEventListener('mousemove', (e) => { at = `translate(${e.clientX}px,${e.clientY}px)`; c.style.transform = at; }, true);
    addEventListener('mousedown', () => { c.style.transform = at + ' scale(.7)'; c.style.background = 'rgba(239,68,68,.6)'; }, true);
    addEventListener('mouseup', () => { c.style.transform = at; c.style.background = 'rgba(255,255,255,.35)'; }, true);
  };
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', add);
  else add();
}

/** What a step gets. Paced (video): human-speed moves, and dwells hold the frame; unpaced: both instant.
 * wait() is for data and always waits. */
function harness(page, paced) {
  const h = {
    page,
    wait: (ms) => page.waitForTimeout(ms),
    dwell: async (ms) => { if (paced) await page.waitForTimeout(ms); },
    async moveTo(loc, { dx = 0, dy = 0, steps = 20 } = {}) {
      await loc.waitFor({ state: 'visible', timeout: 10000 });
      await loc.scrollIntoViewIfNeeded({ timeout: 3000 }).catch(() => {});
      const b = await loc.boundingBox();
      if (!b) throw new Error(`no box for ${loc}`);
      await page.mouse.move(b.x + b.width / 2 + dx, b.y + b.height / 2 + dy, { steps: paced ? steps : 1 });
      await h.dwell(180);
    },
    async click(loc, opts) {
      await h.moveTo(loc, opts);
      await page.mouse.down();
      await h.dwell(70);
      await page.mouse.up();
      await h.dwell(350);
    },
    async drag(loc, x, y) {
      await h.moveTo(loc);
      await page.mouse.down();
      await page.mouse.move(x, y, { steps: paced ? 30 : 5 });
      await page.mouse.up();
      await h.dwell(300);
    },
    async key(k) { await page.keyboard.press(k); await h.dwell(400); },
    type: (text) => page.keyboard.type(text, { delay: paced ? 120 : 0 }),
    park: (x, y) => page.mouse.move(x, y, { steps: paced ? 15 : 1 }),
    async pick(combobox, option) {
      await h.click(combobox);
      await h.click(page.getByRole('option', { name: option }).first());
    },
  };
  return h;
}

/** Starts a 2x JPEG screencast into dir; stop() resolves to [{ file, t }], t in epoch seconds. */
async function screencast(ctx, page, dir) {
  fs.mkdirSync(dir, { recursive: true });
  const cdp = await ctx.newCDPSession(page);
  const frames = [], writes = [];
  let stopped = false;
  cdp.on('Page.screencastFrame', (f) => {
    if (stopped) return; // a frame already in flight when stopping: its write would outlive the frames dir
    cdp.send('Page.screencastFrameAck', { sessionId: f.sessionId }).catch(() => {});
    const file = `${String(frames.length).padStart(6, '0')}.jpg`;
    frames.push({ file, t: f.metadata.timestamp });
    writes.push(fs.promises.writeFile(path.join(dir, file), Buffer.from(f.data, 'base64')));
  });
  const { width, height } = page.viewportSize();
  await cdp.send('Page.startScreencast', { format: 'jpeg', quality: 95, maxWidth: width * 2, maxHeight: height * 2 });
  return async () => {
    stopped = true;
    await cdp.send('Page.stopScreencast');
    await Promise.all(writes);
    return frames;
  };
}

/** Each frame lasts until the next one's timestamp; ffmpeg resamples that to 30 fps, at most 1440 wide. */
function encode(dir, frames, end, mp4) {
  const list = ['ffconcat version 1.0'];
  frames.forEach((f, i) => list.push(`file '${f.file}'`, `duration ${((frames[i + 1] ? frames[i + 1].t : end) - f.t).toFixed(4)}`));
  list.push(`file '${frames[frames.length - 1].file}'`);
  fs.writeFileSync(path.join(dir, 'frames.txt'), list.join('\n') + '\n');
  execFileSync('ffmpeg', ['-y', '-v', 'error', '-f', 'concat', '-safe', '0', '-i', path.join(dir, 'frames.txt'),
    '-vf', "fps=30,scale='min(1440,iw)':-2:flags=lanczos,format=yuv420p", '-c:v', 'libx264', '-preset', 'slow',
    '-tune', 'stillimage', '-crf', process.env.DEMO_CRF || '20', '-movflags', '+faststart', mp4]);
}

async function run(browser, file) {
  const name = path.basename(file, '.demo.js');
  const dir = path.join(out, name), framesDir = path.join(dir, 'frames');
  const demo = require(path.resolve(file));
  const first = from ? demo.steps.findIndex((s) => s.name === from) : 0;
  fs.mkdirSync(dir, { recursive: true });
  // Clear only this mode's output (stills from the replayed step on), so stills and video keep each other's.
  if (first >= 0) for (const f of fs.readdirSync(dir)) {
    const mine = video ? f === `${name}.mp4` || f === 'chapters.md'
      : f === 'walkthrough.md' || (/^\d+-.*\.png$/.test(f) && parseInt(f, 10) > first);
    if (mine || f.startsWith('failed-') || f === 'frames') fs.rmSync(path.join(dir, f), { recursive: true, force: true });
  }
  const ctx = await browser.newContext({ viewport: demo.viewport || { width: 1440, height: 900 }, deviceScaleFactor: 2 });
  if (video) await ctx.addInitScript(cursor);
  const page = await ctx.newPage();
  const errors = [];
  page.on('pageerror', (e) => errors.push(e.message));
  page.on('console', (m) => { if (m.type() === 'error') errors.push(m.text()); });
  const chapters = [], doc = [`# ${demo.title || name}`, ''];
  let stop, step, ok = true;
  try {
    if (first < 0) throw new Error(`no step named "${from}"`);
    await page.goto(url + (demo.route || ''));
    if (demo.ready) await demo.ready(harness(page, false)); // warm-up, never recorded
    for (const [i, s] of demo.steps.entries()) {
      step = s;
      const live = i >= first;
      if (live && video && !stop) stop = await screencast(ctx, page, framesDir);
      if (live && video) chapters.push({ t: Date.now() / 1000, name: s.name });
      await s.run(harness(page, live && video));
      if (video) continue;
      const png = `${String(i + 1).padStart(2, '0')}-${slug(s.name)}.png`;
      const entry = [`## ${i + 1}. ${s.name}`, '', ...(s.caption ? [s.caption, ''] : []), `![${s.name}](${png})`, ''];
      if (!live) { if (fs.existsSync(path.join(dir, png))) doc.push(...entry); continue; } // kept from an earlier run
      await page.waitForTimeout(300); // let the last click's transition settle
      await page.screenshot({ path: path.join(dir, png) });
      doc.push(...entry);
    }
    step = undefined;
    if (video) {
      const end = Date.now() / 1000, frames = await stop();
      stop = undefined;
      const mp4 = path.join(dir, `${name}.mp4`), t0 = frames[0].t;
      encode(framesDir, frames, end, mp4);
      fs.writeFileSync(path.join(dir, 'chapters.md'), chapters.map((c) => `${clock(Math.max(0, c.t - t0))} ${c.name}`).join('\n') + '\n');
      const mb = fs.statSync(mp4).size / 1e6;
      console.log(`${name}: ${mp4} (${mb.toFixed(1)} MB, ${clock(end - t0)}), chapters in ${path.join(dir, 'chapters.md')}`);
      if (mb >= 10) console.log(`${name}: over GitHub's 10 MB attachment limit; rerun with DEMO_CRF=28 (default 20)`);
    } else {
      fs.writeFileSync(path.join(dir, 'walkthrough.md'), doc.join('\n'));
      console.log(`${name}: ${path.join(dir, 'walkthrough.md')} (${demo.steps.length - first} new stills)`);
    }
  } catch (e) {
    ok = false;
    const shot = path.join(dir, `failed-${step ? slug(step.name) : 'start'}.png`);
    await page.screenshot({ path: shot }).catch(() => {});
    console.log(`${name}: FAILED at ${step ? `step "${step.name}"` : 'start'}: ${String(e.message).split('\n')[0]}\n  screenshot: ${shot}`);
  }
  if (stop) await stop().catch(() => {});
  fs.rmSync(framesDir, { recursive: true, force: true });
  if (errors.length) console.log(`${name}: ${errors.length} console errors, first: ${errors[0].split('\n')[0].slice(0, 160)}`);
  await ctx.close();
  return ok;
}

(async () => {
  // Chromium gives 2x screencast frames only when launched with this flag.
  const browser = await chromium.launch({ args: ['--force-device-scale-factor=2'] });
  let ok = true;
  try {
    for (const file of demos) ok = (await run(browser, file)) && ok;
  } finally {
    await browser.close();
  }
  process.exit(ok ? 0 : 1);
})();
