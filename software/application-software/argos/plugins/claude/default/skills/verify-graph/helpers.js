// Bodies for Playwright MCP `browser_run_code` in the verify-graph skill. Paste one function as-is.

// selectRun: the run carousel's "Select this Run" button sits under a PrimeNG overlay, so click it
// with a synthetic event instead of browser_click.
async (page) => {
  await page.waitForTimeout(1500);
  await page.evaluate(() => {
    const btn = Array.from(document.querySelectorAll('button'))
      .find(b => b.textContent?.includes('Select this Run'));
    if (btn) btn.dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true }));
  });
  await page.waitForTimeout(2000);
}

// selectTopic: clicking a leaf in the tree navigates away, so click its label instead.
// Change 'Voltage' to the leaf you want.
async (page) => {
  await page.evaluate((topicName) => {
    const p = Array.from(document.querySelectorAll('p'))
      .find(el => el.textContent?.trim() === topicName);
    if (p) p.click();
  }, 'Voltage');
  await page.waitForTimeout(3000);
}
