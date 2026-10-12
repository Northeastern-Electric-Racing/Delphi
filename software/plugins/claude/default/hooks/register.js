// The delphi mod: /ws opens a pane, to keep open, that lists main and every Delphi workspace
// (.delphi/switch.sh --list) and switches this clone to the one you pick; /ws <name> switches straight
// away. A switch changes CLAUDE.md and the skills on disk, but this session keeps the ones it loaded,
// so after one the pane and the line under the prompt ask for a restart. All the git work is
// switch.sh's; outside a Delphi clone /ws says so and does nothing.
const PANE = 'delphi-workspaces'
const LIST_MS = 60_000 // switch.sh --list fetches the ws/* branches
const SWITCH_MS = 600_000 // the most $.process.run allows: a switch runs the new workspace's setup.sh

let root = '' // this clone's top, where .delphi/switch.sh is; '' until found, or outside a Delphi clone
let names = [] // main, then each workspace, as switch.sh --list prints them
let here = '' // the one this clone is on
let isDirty = false // tracked files have changes, so switch.sh would refuse
let note = '' // what the last switch did
let isBusy = false

async function run($, argv, timeoutMs) {
  try {
    return await $.process.run(argv, { cwd: root, timeoutMs })
  } catch (err) {
    return { exitCode: -1, stdout: '', stderr: String(err?.message ?? err) }
  }
}

async function findRoot($) {
  if (root) return true
  try {
    const top = await $.process.run(['git', 'rev-parse', '--show-toplevel'])
    const dir = top.exitCode === 0 ? top.stdout.trim() : ''
    if (dir && (await $.fs.exists(dir + '/.delphi/switch.sh'))) root = dir
  } catch {
    root = ''
  }
  return root !== ''
}

async function load($) {
  const list = await run($, ['bash', root + '/.delphi/switch.sh', '--list'], LIST_MS)
  const lines = list.stdout.split('\n').filter((l) => l.trim() !== '')
  names = lines.map((l) => l.slice(2))
  here = (lines.find((l) => l.startsWith('* ')) ?? '').slice(2)
  if (list.exitCode !== 0) note = 'Could not list the workspaces: ' + list.stderr.trim()
  isDirty = (await run($, ['git', 'diff', '--quiet', 'HEAD', '--'], LIST_MS)).exitCode !== 0
  $.ui.invalidate('ui.render')
}

async function switchTo($, name) {
  if (isBusy) return
  if (name === here) {
    note = 'Already on ' + name + '.'
    $.ui.invalidate('ui.render')
    return
  }
  isBusy = true
  note = 'Switching to ' + name + '…'
  $.ui.invalidate('ui.render')
  const r = await run($, ['bash', root + '/.delphi/switch.sh', name], SWITCH_MS)
  if (r.exitCode === 0) {
    note = 'On ' + name + ': restart Claude Code in this folder to load its CLAUDE.md and skills.'
    await $.ui.status('switched to ' + name + '; restart Claude Code here')
  } else {
    note = 'Not switched: ' + (r.stderr.trim().split('\n').pop() || 'switch.sh failed')
  }
  isBusy = false
  await load($)
}

export function register(on) {
  on('session.start', async ($, e, next) => {
    try {
      await $.command.register({
        name: 'ws',
        description: 'Delphi: open the workspace switcher, or switch this clone to a workspace',
        argumentHint: '[workspace]',
      })
    } catch (err) {
      await $.ui.log('delphi: /ws not added: ' + String(err?.message ?? err))
    }
    return next(e)
  })

  on('command.run', { command: 'ws' }, async ($, e) => {
    if (!(await findRoot($))) return { text: 'Not in a Delphi clone: no .delphi/switch.sh at the top of this repository.' }
    const name = (e.args ?? '').trim()
    if (name) {
      await load($)
      await switchTo($, name)
      return { text: note }
    }
    await $.ui.open({ id: PANE, title: 'Workspaces', focus: true, closeOnEscape: true })
    await load($)
    return {}
  })

  on('ui.render', { component: 'Pane' }, async ($, e, next) => {
    if (e.requestId !== PANE) return next(e)
    const { Box, Text, Button } = $.ui.resolve(e)
    const head = 'On ' + (here || 'a branch that is no workspace')
    const rows = names.map((name, i) => {
      const button = {
        key: 'ws:' + name,
        label: name + (name === here ? ' (here)' : ''),
        plain: true,
        onPress: () => switchTo($, name),
      }
      return Button(i < 9 ? { ...button, hotkey: String(i + 1) } : button)
    })
    return Box({
      flexDirection: 'column',
      children: [
        Text({ bold: true, children: [head] }),
        ...(isDirty ? [Text({ color: 'yellow', children: ['Tracked files have changes: commit them before switching.'] })] : []),
        Text({ children: [' '] }),
        ...rows,
        Text({ children: [' '] }),
        Button({ key: 'refresh', label: 'Refresh', hotkey: 'r', plain: true, onPress: () => load($) }),
        ...(note ? [Text({ dimColor: true, children: [note] })] : []),
      ],
    })
  })
}
