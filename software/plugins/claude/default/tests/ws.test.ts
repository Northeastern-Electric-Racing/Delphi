// Tests for the delphi mod's /ws (claude plugin test; tests/e2e.sh runs them). A fake clone answers
// the mod's processes: git for the clone's top and its changes, .delphi/switch.sh for the list and
// the switch, web/server.py and the browser it opens, so no git, switch or server runs (tests/e2e.sh
// runs the real server).
import type { On } from 'claude-code'
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

// /ws as typed at the prompt
const ws = (args: string) => ({
  command: 'ws',
  args,
  origin: { kind: 'composer' as const },
  presentation: { isFullscreen: false, columns: 100 },
})

// What switch.sh would print and exit with
const done = (exitCode: number, stdout = '', stderr = '') => ({
  value: { exitCode, stdout, stderr, isStdoutTruncated: false, isStderrTruncated: false },
})

const URL = 'http://127.0.0.1:8765/token/'

type Clone = {
  here: string
  isDirty: boolean
  isDelphi: boolean
  switches: { name: string; timeoutMs?: number }[]
  status: string[]
  servers: string[][] // each web/server.py started, its argv
  opened: string[] // the URLs opened in a browser
  browser: (name: string) => void // the browser view switches to name ('' stops the server)
  seen: Promise<void> // once the mod has read what the server printed after that
}

// Stubs every call the mod makes, answered from a clone on `here`; returns it to inspect
function fakeClone(on: On, here = ARGOS, isDirty = false, isDelphi = true, hasPython = true): Clone {
  let browse = (name: string) => {}
  let seen = () => {}
  const switched = new Promise<string>(r => (browse = r))
  const c: Clone = { here, isDirty, isDelphi, switches: [], status: [], servers: [], opened: [], browser: n => browse(n), seen: new Promise(r => (seen = r)) }
  on('session.start', () => ({ cwd: ROOT }))
  on('command.register', ($, e) => ({ value: { command: e.name } }))
  on('ui.open', () => ({ value: { isPlaced: true } }))
  on('ui.log', () => ({ value: undefined }))
  on('ui.status', ($, e) => {
    c.status.push(e.text ?? '')
    return { value: undefined }
  })
  on('fs.exists', ($, e) => ({ value: c.isDelphi && e.path === SWITCH }))
  on('process.run', ($, e) => {
    const [cmd = '', a1 = '', a2 = ''] = e.argv
    if (cmd === 'git' && a1 === 'rev-parse') return done(0, ROOT + '\n')
    if (cmd === 'git' && a1 === 'diff') return done(c.isDirty ? 1 : 0)
    if (cmd === 'bash' && a1 === SWITCH && a2 === '--list') {
      const out = ['main', ARGOS, BMS].map((n) => (n === c.here ? '* ' : '  ') + n).join('\n') + '\n'
      return done(0, out)
    }
    if (cmd === 'python3' && a1 === '-m' && a2 === 'webbrowser') {
      c.opened.push(e.argv[e.argv.length - 1] ?? '')
      return done(0)
    }
    if (cmd === 'bash' && a1 === SWITCH) {
      c.switches.push(e.init?.timeoutMs === undefined ? { name: a2 } : { name: a2, timeoutMs: e.init.timeoutMs })
      if (c.isDirty) return done(1, '', 'switch: commit or set aside your changes first (git status)\n')
      c.here = a2.split('/').length > 1 || a2 === 'main' ? a2 : BMS
      return done(0, 'switch: on ws/' + c.here + '\n')
    }
    return { deny: 'unexpected process: ' + e.argv.join(' ') }
  })
  on('process.spawn', async function* ($, e) {
    c.servers.push([...e.argv])
    if (!hasPython) throw new Error('spawn python3 ENOENT')
    yield { stream: 'stdout' as const, text: URL + '\n' }
    const name = await switched
    if (name) {
      c.here = BMS
      yield { stream: 'stdout' as const, text: 'switched ' + name + '\n' }
    }
    seen()
    return { value: { code: 0, signal: null } }
  })
  return c
}

test('/ws is registered at session start', async ($, on) => {
  const names: string[] = []
  on('session.start', () => ({ cwd: ROOT }))
  on('command.register', ($, e) => {
    names.push(e.name)
    return { value: { command: e.name } }
  })
  await $.session.start({ surface: 'terminal', isInteractive: true, cwd: ROOT })
  expect(names).toEqual(['ws'])
})

test('/ws opens a pane of cards grouped by project, this one marked current', async ($, on) => {
  fakeClone(on)
  expect(await $.command.run(ws(''))).toEqual({})
  const ui = await $.ui.mount(PANE)
  expect(await ui.find({ type: 'Text', text: 'APPLICATION-SOFTWARE / ARGOS' })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: 'ELECTRICAL' })).toBeDefined()
  expect(await ui.find({ key: 'ws:main' })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: ' · current' })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: /Tracked files have changes/ })).toBeUndefined()
})

test('pressing a card only selects it; Switch workspace switches and asks for a restart', async ($, on) => {
  const c = fakeClone(on)
  await $.command.run(ws(''))
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
  await $.command.run(ws(''))
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
  const answer = await $.command.run(ws('bms-dev'))
  expect(c.switches.map(s => s.name)).toEqual(['bms-dev'])
  expect(answer.text).toMatch(/^On bms-dev: restart Claude Code in this folder/)
})

test('outside a Delphi clone, /ws says so and runs nothing', async ($, on) => {
  const c = fakeClone(on, ARGOS, false, false)
  const answer = await $.command.run(ws('main'))
  expect(answer.text).toMatch(/^Not in a Delphi clone/)
  expect(c.switches).toEqual([])
})

test('Open in browser starts web/server.py once for the clone, opens it, and links it in the pane', async ($, on) => {
  const c = fakeClone(on)
  await $.command.run(ws(''))
  const ui = await $.ui.mount(PANE)
  await ui.press({ key: 'web' })
  await ui.press({ key: 'web' })
  expect(c.servers.length).toBe(1)
  expect(c.servers[0]?.[0]).toBe('python3')
  expect(c.servers[0]?.[1]).toMatch(/\/web\/server\.py$/)
  expect(c.servers[0]?.[2]).toBe(ROOT)
  expect(c.opened).toEqual([URL, URL])
  expect(await ui.find({ type: 'Link' })).toMatchObject({ props: { href: URL } })
  c.browser('')
  await c.seen
})

test('a switch made in the browser view shows in the pane and under the prompt', async ($, on) => {
  const c = fakeClone(on)
  await $.command.run(ws(''))
  const ui = await $.ui.mount(PANE)
  await ui.press({ key: 'web' })
  c.browser(BMS)
  await c.seen
  expect(c.status).toEqual(['switched to bms-dev; restart Claude Code in this folder'])
  expect(await ui.find({ type: 'Text', text: '✓ Now on bms-dev' })).toBeDefined()
})

test('/ws --web answers with the URL', async ($, on) => {
  const c = fakeClone(on)
  expect((await $.command.run(ws('--web'))).text).toMatch(/^Browser view: http:\/\/127\.0\.0\.1:8765\/token\//)
  expect(c.opened).toEqual([URL])
  expect(c.switches).toEqual([])
  c.browser('')
  await c.seen
})

test('without python3, /ws --web says it needs it and opens nothing', async ($, on) => {
  const c = fakeClone(on, ARGOS, false, true, false)
  expect((await $.command.run(ws('--web'))).text).toMatch(/^No browser view \(it needs python3\)/)
  expect(c.opened).toEqual([])
})
