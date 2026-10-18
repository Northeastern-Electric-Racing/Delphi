// selectRun, for `playwright-cli run-code --filename=<this file>` in the verify-graph skill: the run
// carousel's "Select this Run" button sits under a PrimeNG overlay, so click it with a synthetic event
// instead of `playwright-cli click`.
async (page) => {
  await page.waitForTimeout(1500);
  await page.evaluate(() => {
    const btn = Array.from(document.querySelectorAll('button'))
      .find(b => b.textContent?.includes('Select this Run'));
    if (btn) btn.dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true }));
  });
  await page.waitForTimeout(2000);
}
