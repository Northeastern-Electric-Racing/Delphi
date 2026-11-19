// covers: TODO
// {{name}}: a demo of {{route}}, run by the demo skill. The covers line above lists path fragments of the source
// this page shows, specific enough that other pages don't match (its page and component folders, like
// pages/graph-page/ components/graph/, not a word like graph), so a branch that changes them reruns this demo.
// Find data by what the page shows (a name, a topic), never by an id that changes each time data is seeded.
// Steps run in order. Each one's name is a video chapter and a stills heading, and --from <name> replays from it.
// A step gets h: h.page (the Playwright page); h.moveTo, h.click (locator, { dx, dy }), h.drag (locator, x, y),
// h.key, h.type, h.pick (combobox, option name) and h.park (x, y: rest the cursor off hover targets).
// h.dwell(ms) holds the video for viewers and is skipped in stills; h.wait(ms) and locator waits hold for data in both.
// Helpers only this app needs go in a lib.js next to its demos: const lib = require('./lib');
module.exports = {
  title: '{{name}}',
  route: '{{route}}',
  viewport: { width: 1440, height: 900 },
  // Warm-up before the first step, never recorded: wait until the page shows real data.
  ready: async (h) => {
    await h.page.locator('body').waitFor();
  },
  steps: [
    {
      name: 'Overview',
      caption: 'What the page shows when it opens.',
      run: async (h) => {
        await h.dwell(2500);
      },
    },
  ],
};
