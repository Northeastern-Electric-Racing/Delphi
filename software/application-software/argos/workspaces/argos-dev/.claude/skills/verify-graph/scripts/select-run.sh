#!/usr/bin/env bash
# select-run.sh <branch> <run-id>: with the Select Run dialog open in <branch>'s session, pick run
# <run-id>. The carousel autoplays and its "Select this Run" button sits under a PrimeNG overlay, so this
# finds the run's card by id and clicks its button with a synthetic event instead of `playwright-cli click`.
set -euo pipefail
branch=${1:?usage: select-run.sh <branch> <run-id>}; id=${2:?usage: select-run.sh <branch> <run-id>}
case $id in '' | *[!0-9]*) echo "select-run: run id must be a number, got '$id'" >&2 && exit 1 ;; esac
playwright-cli -s="$branch" run-code "async (page) => {
  await page.waitForSelector('.run-card');
  const found = await page.evaluate((id) => {
    const card = [...document.querySelectorAll('.run-card')]
      .find((c) => [...c.querySelectorAll('*')].some((e) => !e.childElementCount && e.textContent.trim() === 'Run #' + id));
    const button = card?.parentElement?.querySelector('.run-select-button button');
    button?.dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true }));
    return !!button;
  }, $id);
  if (!found) throw new Error('select-run: no Run #$id in the Select Run dialog');
}"
