// The base verify-graph checks, for check.sh to run with `playwright-cli run-code` (it fills in __URL__,
// __RUN__ and __OUT__). Each check asserts what the DOM can show; what only a picture can show (a series
// drawn, the x-axis span) is a screenshot with a `look:` line for the agent to judge.
async (page) => {
  const URL = '__URL__', RUN = __RUN__, OUT = '__OUT__';
  const lines = [], errors = [];
  page.on('console', (m) => {
    if (m.type() === 'error' && !m.text().includes('NG0100')) errors.push(m.text().split('\n')[0].slice(0, 160));
  }); // develop already logs NG0100 (ExpressionChangedAfterItHasBeenChecked)
  const text = (t) => page.getByText(t, { exact: true });
  const button = (name) => page.getByRole('button', { name, exact: true });
  const tree = page.getByRole('tree');
  const absent = async (name) => { if (await button(name).isVisible()) throw new Error(`"${name}" is shown`); };
  const shot = async (name, look) => {
    await page.screenshot({ path: `${OUT}/${name}.png` });
    lines.push(`    look: ${OUT}/${name}.png: ${look}`);
  };
  const check = async (name, steps) => {
    const at = lines.length;
    try {
      await steps();
      lines.splice(at, 0, `[x] ${name}`);
    } catch (e) {
      lines.push(`[ ] ${name}: ${String(e.message).split('\n')[0]}`);
    }
  };

  await check('1 page loads in real time', async () => {
    await page.goto(`${URL}/graph`);
    await text('Real Time').waitFor({ timeout: 30000 });
    for (const b of ['Pause', 'Time Range', 'Select Run', 'Clear Graph', 'Custom']) await button(b).waitFor({ timeout: 2000 });
    await page.getByRole('combobox', { name: 'Quick Select' }).waitFor({ timeout: 2000 });
    await absent('Realtime');
  });
  await check('2 topic from the tree draws live', async () => {
    const node = (name) => tree.getByRole('treeitem').filter({ has: page.getByText(name, { exact: true }) }).last(); // innermost
    for (const name of ['BMS', 'Segment_Total_Volt']) await node(name).locator('.p-tree-node-toggle-button').first().click();
    await tree.getByText('0', { exact: true }).first().click();
    await page.waitForURL(/topics=BMS%2FSegment_Total_Volt%2F0/, { timeout: 5000 });
    await page.waitForTimeout(3000);
    await shot('02-live-topic', 'a live series is drawn');
  });
  await check(`3 seeded run #${RUN}`, async () => {
    await button('Select Run').click();
    await page.locator('.run-card').first().waitFor({ timeout: 10000 });
    await page.evaluate((id) => {
      const card = [...document.querySelectorAll('.run-card')]
        .find((c) => [...c.querySelectorAll('*')].some((e) => !e.childElementCount && e.textContent.trim() === 'Run #' + id));
      const pick = card?.parentElement?.querySelector('.run-select-button button');
      if (!pick) throw new Error(`no Run #${id} in the Select Run dialog`);
      pick.dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true })); // under a PrimeNG overlay
    }, RUN);
    await page.locator('.run-card').first().waitFor({ state: 'detached', timeout: 5000 });
    await text(`Run #${RUN}`).waitFor({ timeout: 10000 });
    await button('Realtime').waitFor({ timeout: 2000 });
    await absent('Pause');
    await page.waitForTimeout(3000);
    await shot('03-seeded-run', 'x-axis spans 50 hours, with a dated day-boundary line at each of the two midnights');
  });
  await check('4 historical Quick Select', async () => {
    await button('Realtime').click();
    await text('Real Time').waitFor({ timeout: 5000 });
    await page.getByRole('combobox', { name: 'Quick Select' }).click();
    await page.getByRole('option').first().waitFor({ timeout: 5000 });
    const options = await page.getByRole('option').count();
    if (options !== 11) throw new Error(`${options} Quick Select options, not 11`);
    await page.getByRole('option', { name: '5 minutes', exact: true }).click();
    await text('Historical').waitFor({ timeout: 5000 });
    await absent('Pause');
    await page.waitForTimeout(3000);
    await shot('04-historical-5-min', 'x-axis about 5 minutes, or since the data starts');
  });
  await check('5 back to real time', async () => {
    await button('Realtime').click();
    await text('Real Time').waitFor({ timeout: 5000 });
    await page.waitForTimeout(10000);
    await shot('05-real-time-after', 'x-axis about 30 seconds, not the whole session');
  });
  await check('6 no new console errors', async () => {
    if (errors.length) throw new Error(`${errors.length}, first: ${errors[0]}`);
  });
  return lines.join('\n');
}
