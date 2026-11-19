#!/usr/bin/env bash
# select-run.sh <branch> <run-id>: with the Select Run dialog open in <branch>'s session, pick run
# <run-id>. The dialog is a carousel showing one run at a time and autoplaying, so this stops it, steps
# to the run with Next, and clicks its "Select this Run".
set -euo pipefail
branch=${1:?usage: select-run.sh <branch> <run-id>}; id=${2:?usage: select-run.sh <branch> <run-id>}
case $id in '' | *[!0-9]*) echo "select-run: run id must be a number, got '$id'" >&2 && exit 1 ;; esac
playwright-cli -s="$branch" run-code "async (page) => {
  const runs = page.getByRole('region', { name: 'Runs' }), slide = runs.getByRole('group');
  const here = () => slide.getByText('Run #$id', { exact: true });
  await runs.getByRole('button', { name: 'Stop automatic slide show' }).click({ timeout: 10000 });
  const total = Number((await slide.getAttribute('aria-label')).split(' of ')[1]);
  for (let i = 0; i < total && !(await here().count()); i++) {
    const at = Number((await slide.getAttribute('aria-label')).split(' of ')[0]);
    await runs.getByRole('button', { name: 'Next run' }).click();
    await runs.locator('[aria-label=\"' + ((at % total) + 1) + ' of ' + total + '\"]').waitFor({ timeout: 2000 });
  }
  if (!(await here().count())) throw new Error('select-run: no Run #$id in the Select Run dialog');
  await slide.getByRole('button', { name: 'Select this Run' }).click();
}"
