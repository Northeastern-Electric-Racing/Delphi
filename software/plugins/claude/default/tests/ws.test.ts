// Tests for the delphi mod's /ws (claude plugin test; tests/e2e.sh runs them). A fake clone answers
// the mod's processes: git for the clone's top and its changes, .delphi/switch.sh for the list and
// the switch, so no git or switch runs.
import { expect, test } from 'claude-code/testing'

const ROOT = '/work/delphi'
const SWITCH = ROOT + '/.delphi/switch.sh'
const ARGOS = 'software/application-software/argos/argos-dev'
const BMS = 'software/electrical/bms-dev'
const PANE = {
  plugin: 'delphi',
  component: 'Pane',
  requestId: 'delphi-workspaces',
  surface: 'terminal',
  viewport: { columns: 100, rows: 30 },
  props: { title: 'Workspaces', isFocused: true, bodyColumns: 80, placement: 'inline', scroll: { offset: 0, bodyRows: 20 }, view: {} },
} as const

type Clone = { here: string; isDirty: boolean; isDelphi: boolean; switches: { name: string; timeoutMs?: number }[]; status: string[] }

// Stubs every call the mod makes, answered from a clone on `here`; returns it to inspect
function fakeClone(on, here = ARGOS, isDirty = false, isDelphi = true): Clone {
  const c: Clone = { here, isDirty, isDelphi, switches: [], status: [] }
  on('session.start', () => ({ cwd: ROOT }))
  on('command.register', () => ({ value: undefined }))
  on('ui.open', () => ({ value: { isPlaced: true } }))
  on('ui.log', () => ({ value: undefined }))
  on('ui.status', ($, e) => {
    c.status.push(e.text)
    return { value: undefined }
  })
  on('fs.exists', ($, e) => ({ value: c.isDelphi && e.path === SWITCH }))
  on('process.run', ($, e) => {
    const [cmd, a1, a2] = e.argv
    if (cmd === 'git' && a1 === 'rev-parse') return { value: { exitCode: 0, stdout: ROOT + '\n', stderr: '' } }
    if (cmd === 'git' && a1 === 'diff') return { value: { exitCode: c.isDirty ? 1 : 0, stdout: '', stderr: '' } }
    if (cmd === 'bash' && a1 === SWITCH && a2 === '--list') {
      const out = ['main', ARGOS, BMS].map((n) => (n === c.here ? '* ' : '  ') + n).join('\n') + '\n'
      return { value: { exitCode: 0, stdout: out, stderr: '' } }
    }
    if (cmd === 'bash' && a1 === SWITCH) {
      c.switches.push({ name: a2, timeoutMs: e.init?.timeoutMs })
      if (c.isDirty) return { value: { exitCode: 1, stdout: '', stderr: 'switch: commit or set aside your changes first (git status)\n' } }
      c.here = a2.split('/').length > 1 || a2 === 'main' ? a2 : BMS
      return { value: { exitCode: 0, stdout: 'switch: on ws/' + c.here + '\n', stderr: '' } }
    }
    return { deny: 'unexpected process: ' + e.argv.join(' ') }
  })
  return c
}

test('/ws is registered at session start', async ($, on) => {
  const names: string[] = []
  on('session.start', () => ({ cwd: ROOT }))
  on('command.register', ($, e) => {
    names.push(e.name)
    return { value: undefined }
  })
  await $.session.start({ surface: 'terminal', isInteractive: true, cwd: ROOT })
  expect(names).toEqual(['ws'])
})

test('/ws opens a pane of cards grouped by project, this one marked current', async ($, on) => {
  fakeClone(on)
  expect(await $.command.run({ command: 'ws', args: '' })).toEqual({})
  const ui = await $.ui.mount(PANE)
  expect(await ui.find({ type: 'Text', text: 'APPLICATION-SOFTWARE / ARGOS' })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: 'ELECTRICAL' })).toBeDefined()
  expect(await ui.find({ key: 'ws:main' })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: ' · current' })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: /Tracked files have changes/ })).toBeUndefined()
})

test('pressing a card only selects it; Switch workspace switches and asks for a restart', async ($, on) => {
  const c = fakeClone(on)
  await $.command.run({ command: 'ws', args: '' })
  const ui = await $.ui.mount(PANE)
  await ui.press({ key: 'ws:' + BMS })
  expect(c.switches).toEqual([])
  expect(await ui.find({ type: 'Text', text: '› bms-dev' })).toBeDefined()
  await ui.press({ key: 'switch' })
  expect(c.switches).toEqual([{ name: BMS, timeoutMs: 600_000 }])
  expect(c.status).toEqual(['switched to bms-dev; restart Claude Code in this folder'])
  expect(await ui.find({ type: 'Text', text: '✓ Now on bms-dev' })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: /^Restart Claude Code in this folder/ })).toBeDefined()
  expect(await ui.find({ key: 'close' })).toBeDefined()
})

test('with tracked changes the pane warns, a refused switch says why, and Back returns', async ($, on) => {
  const c = fakeClone(on, ARGOS, true)
  await $.command.run({ command: 'ws', args: '' })
  const ui = await $.ui.mount(PANE)
  expect(await ui.find({ type: 'Text', text: /^⚠ Tracked files have changes/ })).toBeDefined()
  await ui.press({ key: 'ws:main' })
  await ui.press({ key: 'switch' })
  expect(c.here).toBe(ARGOS)
  expect(c.status).toEqual([])
  expect(await ui.find({ type: 'Text', text: '✗ Not switched: switch: commit or set aside your changes first (git status)' })).toBeDefined()
  await ui.press({ key: 'back' })
  expect(await ui.find({ key: 'switch' })).toBeDefined()
})

test('/ws <name> switches without the pane', async ($, on) => {
  const c = fakeClone(on)
  const answer = await $.command.run({ command: 'ws', args: 'bms-dev' })
  expect(c.switches.map(s => s.name)).toEqual(['bms-dev'])
  expect(answer.text).toMatch(/^On bms-dev: restart Claude Code in this folder/)
})

test('outside a Delphi clone, /ws says so and runs nothing', async ($, on) => {
  const c = fakeClone(on, ARGOS, false, false)
  const answer = await $.command.run({ command: 'ws', args: 'main' })
  expect(answer.text).toMatch(/^Not in a Delphi clone/)
  expect(c.switches).toEqual([])
})
