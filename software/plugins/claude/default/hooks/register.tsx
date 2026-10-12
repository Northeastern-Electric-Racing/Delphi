// The delphi mod: /ws-delphi opens a pane to keep open, with every Delphi workspace and main as cards
// grouped by project (.delphi/switch.sh --list). Press one to select it, then Switch workspace, which
// runs switch.sh; /ws-delphi <name> switches straight away. A switch (or pull) changes CLAUDE.md and the
// skills on disk: Claude Code reloads the skills itself but keeps the CLAUDE.md it started with, so
// the next prompt after the root's CLAUDE.md changed (by /ws-delphi or anything else) carries the new one,
// which says it replaces the old. All the git work is switch.sh's; outside a Delphi clone /ws-delphi says so.
// /ws-delphi --web (or the pane's Open in browser) starts web/server.py for the session: the same cards in
// a browser tab, served on 127.0.0.1; a switch made there shows up here too. Refresh fetches the
// list again; Pull brings this clone's workspace up to date (switch.sh on the one it's on: fetch,
// fast-forward, setup.sh) and says how many commits came.
import type { EngineInterface, Register } from 'claude-code'

// One Delphi workspace, or main: its name (switch.sh takes it), last part, and the folders above it
type Ws = { name: string; leaf: string; group: string }
type Phase = 'pick' | 'confirm' | 'switching' | 'done' | 'failed'

const PANE = 'delphi-workspaces'

let root = '' // this clone's top, where .delphi/switch.sh is; '' outside a Delphi clone
let all: Ws[] = []
let here = '' // the one this clone is on
let isDirty = false // tracked files have changes, so switch.sh would refuse
let selected = ''
let phase: Phase = 'pick'
let message = ''
let isRefreshing = false // switch.sh --list is fetching
let fetchedAt = '' // when it last listed, HH:MM
let listError = '' // why it couldn't, if it couldn't
let isPulling = false
let pullNote = '' // what the last pull did
let isPullOk = true
let toldMd: string | null = null // the root's CLAUDE.md as Claude last read it: at session start, or sent since
let webUrl = '' // the browser view's address while web/server.py runs
let webError = '' // why it isn't running, when it failed to
let webStart: Promise<string> | null = null

function toWs(name: string): Ws {
  if (name === 'main') return { name, leaf: 'main', group: 'project folders, templates, CI' }
  const parts = name.split('/')
  return { name, leaf: parts[parts.length - 1] ?? name, group: parts.slice(1, -1).join(' / ') }
}

function leafOf(name: string): string {
  return toWs(name).leaf
}

async function run($: EngineInterface, argv: string[], timeoutMs: number) {
  try {
    return await $.process.run(argv, { cwd: root, timeoutMs })
  } catch (err) {
    return { exitCode: -1, stdout: '', stderr: String((err as Error)?.message ?? err) }
  }
}

async function findRoot($: EngineInterface): Promise<boolean> {
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

const hhmm = (d: Date) => String(d.getHours()).padStart(2, '0') + ':' + String(d.getMinutes()).padStart(2, '0')

async function load($: EngineInterface) {
  isRefreshing = true
  $.ui.invalidate('ui.render')
  const list = await run($, ['bash', root + '/.delphi/switch.sh', '--list'], 60_000)
  const lines = list.stdout.split('\n').filter(l => l.trim() !== '')
  listError = list.exitCode === 0 ? '' : 'Could not list the workspaces: ' + (list.stderr.trim().split('\n').pop() ?? '')
  fetchedAt = hhmm(new Date())
  isRefreshing = false
  if (list.exitCode === 0 || all.length === 0) { // a failed refresh keeps the last list
    all = lines.map(l => toWs(l.slice(2)))
    here = lines.find(l => l.startsWith('* '))?.slice(2) ?? ''
  }
  isDirty = (await run($, ['git', 'diff', '--quiet', 'HEAD', '--'], 10_000)).exitCode !== 0
  if (!all.some(w => w.name === selected) || (selected === here && phase === 'pick')) {
    selected = all.find(w => w.name !== here)?.name ?? ''
  }
  $.ui.invalidate('ui.render')
}

// Plural-aware "N commit(s)"
const commits = (n: number) => n + (n === 1 ? ' commit' : ' commits')

// What `switch.sh <name>` printed last on stderr, or `otherwise`
const lastLine = (text: string, otherwise: string) => text.trim().split('\n').pop() || otherwise

// Says what a pull of `name` did, from HEAD before and after and switch.sh's answer
async function notePull($: EngineInterface, name: string, before: string, r: { exitCode: number; stderr: string }) {
  const after = (await run($, ['git', 'rev-parse', 'HEAD'], 10_000)).stdout.trim()
  const n = before && after && before !== after ? Number((await run($, ['git', 'rev-list', '--count', before + '..' + after], 10_000)).stdout.trim()) || 0 : 0
  isPullOk = r.exitCode === 0 && !r.stderr.includes('diverged')
  if (r.exitCode !== 0) pullNote = 'Not pulled: ' + lastLine(r.stderr, 'switch.sh failed')
  else if (!isPullOk) pullNote = lastLine(r.stderr, 'diverged from origin')
  else pullNote = n === 0 ? leafOf(name) + ' is up to date with origin' : 'Pulled ' + commits(n) + ' into ' + leafOf(name)
  if (n > 0) await $.ui.status('pulled ' + commits(n) + ' into ' + leafOf(name))
}

async function doPull($: EngineInterface) {
  if (isPulling || phase === 'switching' || !here) return
  isPulling = true
  pullNote = ''
  $.ui.invalidate('ui.render')
  const name = here
  const before = (await run($, ['git', 'rev-parse', 'HEAD'], 10_000)).stdout.trim()
  await notePull($, name, before, await run($, ['bash', root + '/.delphi/switch.sh', name], 600_000))
  isPulling = false
  await load($)
}

// Refresh from its button: fetch again, then put the focus back on it
async function refresh($: EngineInterface) {
  pullNote = ''
  await load($)
  try {
    await $.ui.focus({ requestId: PANE, key: 'refresh' })
  } catch {
    // the pane isn't holding the keys
  }
}

async function readMd($: EngineInterface): Promise<string> {
  try {
    const md = await $.fs.read(root + '/CLAUDE.md')
    return typeof md === 'string' ? md : ''
  } catch {
    return ''
  }
}

async function doSwitch($: EngineInterface) {
  if (phase === 'switching' || !selected || selected === here) return
  phase = 'switching'
  message = ''
  $.ui.invalidate('ui.render')
  const r = await run($, ['bash', root + '/.delphi/switch.sh', selected], 600_000)
  if (r.exitCode === 0) {
    phase = 'done'
    await $.ui.status('switched to ' + leafOf(selected) + '; Claude reads its CLAUDE.md with your next message')
  } else {
    phase = 'failed'
    message = r.stderr.trim().split('\n').pop() || 'switch.sh failed'
  }
  await load($)
}

// A switch made in the browser view: the pane and the line under the prompt say so too
async function switchedInBrowser($: EngineInterface, name: string) {
  phase = 'done'
  message = ''
  await $.ui.status('switched to ' + leafOf(name) + '; Claude reads its CLAUDE.md with your next message')
  await load($)
}

// Starts web/server.py for the rest of the session, once; resolves its URL, or '' with webError set.
// The loop is the server's life: it ends with the server, or kills it when the module unloads.
function startWeb($: EngineInterface): Promise<string> {
  if (webStart) return webStart
  webError = ''
  webStart = new Promise<string>(resolve => {
    void (async () => {
      let pending = ''
      try {
        const server = $.process.spawn({ argv: ['python3', $.plugin.root + '/web/server.py', root], cwd: root })
        for await (const { stream, text } of server) {
          if (stream === 'stderr') {
            $.ui.log(text.trimEnd(), { to: 'debug' })
            webError = 'The browser view stopped: ' + (text.trim().split('\n').pop() ?? '')
            continue
          }
          const lines = (pending + text).split('\n')
          pending = lines.pop() ?? ''
          for (const line of lines) {
            if (!webUrl && line.startsWith('http://')) {
              webUrl = line
              resolve(line)
              $.ui.invalidate('ui.render')
            } else if (line.startsWith('switched ')) await switchedInBrowser($, line.slice('switched '.length))
            else if (line.startsWith('pulled ')) {
              pullNote = line.slice('pulled '.length) // the browser view's own note
              isPullOk = true
              await load($)
            }
          }
        }
      } catch (err) {
        webError = 'No browser view (it needs python3): ' + String((err as Error)?.message ?? err)
      }
      webUrl = ''
      webStart = null
      resolve('')
      $.ui.invalidate('ui.render')
    })()
  })
  return webStart
}

// Starts the browser view if it isn't running and opens it in the default browser
async function openWeb($: EngineInterface): Promise<string> {
  const url = await startWeb($)
  if (url) await run($, ['python3', '-m', 'webbrowser', '-t', url], 30_000)
  $.ui.invalidate('ui.render')
  return url
}


export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    try {
      await $.command.register({
        name: 'ws-delphi',
        description: 'Delphi: open the workspace switcher, or switch this clone to a workspace',
        argumentHint: '[workspace | --web]',
      })
    } catch (err) {
      await $.ui.log('/ws-delphi not added: ' + String((err as Error)?.message ?? err))
    }
    if (await findRoot($)) toldMd = await readMd($)
    return next(e)
  })

  // The first prompt after the root's CLAUDE.md changed carries the new one, once
  on('prompt.submit', async ($, e, next) => {
    if (!root || toldMd === null) return next(e)
    const md = await readMd($)
    if (md === toldMd) return next(e)
    toldMd = md
    const branch = (await run($, ['git', 'branch', '--show-current'], 10_000)).stdout.trim()
    const note =
      'Delphi: since this session started, this clone moved to ' + (branch || 'another commit') + ' (a workspace switch or pull), so ' +
      root + '/CLAUDE.md changed. It replaces the CLAUDE.md you were given at the start; follow this one. Skills under .claude/skills/ have reloaded on their own.\n\n' + md
    return next({ ...e, context: [...(e.context ?? []), note] })
  })

  on('command.run', { command: 'ws-delphi' }, async ($, e) => {
    if (!(await findRoot($))) return { text: 'Not in a Delphi clone: no .delphi/switch.sh at the top of this repository.' }
    phase = 'pick'
    message = ''
    const name = (e.args ?? '').trim()
    if (name === '--web') {
      const url = await openWeb($)
      return { text: url ? 'Browser view: ' + url + ' (it runs until this session ends)' : webError }
    }
    if (name) {
      await load($)
      selected = name
      await doSwitch($)
      const after = phase as Phase // doSwitch changed it
      if (after === 'done') return { text: 'On ' + name + ': Claude reads its CLAUDE.md with your next message.' }
      return { text: after === 'failed' ? 'Not switched: ' + message : 'Already on ' + name + '.' }
    }
    await $.ui.open({ id: PANE, title: 'Workspaces', focus: true, closeOnEscape: true })
    await load($)
    return {}
  })

  on('ui.render', { component: 'Pane', requestId: PANE }, async ($, e) => {
    const { Box, Text, Button, Link } = $.ui.resolve(e)
    const cur = toWs(here)
    const sel = all.find(w => w.name === selected)
    const groups = [...new Set(all.map(w => w.group))]
    const redraw = () => $.ui.invalidate('ui.render')
    const pick = (name: string) => {
      selected = name
      phase = 'pick'
      redraw()
    }
    const ring = phase === 'done' ? 'success' : phase === 'failed' ? 'error' : phase === 'switching' ? 'warning' : 'claude'

    return (
      <Box flexDirection="column" rowGap={1}>
        <Box flexDirection="row" columnGap={1}>
          <Text color="success">●</Text>
          <Text bold>{cur.leaf || 'not on a workspace'}</Text>
          <Text dimColor>{cur.group}</Text>
        </Box>
        {isDirty && <Text color="warning">⚠ Tracked files have changes: commit them before switching.</Text>}
        <Box flexDirection="column" rowGap={1}>
          {groups.map(g => (
            <Box key={'group:' + g} flexDirection="column">
              <Text dimColor>{g.toUpperCase()}</Text>
              {all
                .filter(w => w.group === g)
                .map(w => (
                  <Button key={'ws:' + w.name} plain onPress={() => pick(w.name)}>
                    <Text {...(w.name === selected ? { color: 'claude', bold: true } : {})}>
                      {(w.name === selected ? '› ' : '  ') + w.leaf}
                    </Text>
                    {w.name === here && <Text color="success"> · current</Text>}
                  </Button>
                ))}
            </Box>
          ))}
        </Box>
        <Box borderStyle="round" borderColor={ring} paddingX={1} flexDirection="column" rowGap={1}>
          {phase === 'pick' && (!sel || sel.name === here) && <Text dimColor>Pick a workspace above.</Text>}
          {phase === 'pick' && sel && sel.name !== here && (
            <Box flexDirection="column" rowGap={1}>
              <Text>
                Switch this clone to <Text bold>{sel.leaf}</Text> <Text dimColor>({sel.group})</Text>
              </Text>
              <Box flexDirection="row" columnGap={2}>
                <Button key="switch" variant="primary" autoFocus onPress={() => doSwitch($)}>
                  Switch workspace
                </Button>
              </Box>
            </Box>
          )}
          {phase === 'switching' && <Text color="warning">Switching to {leafOf(selected)}… fetching, parking worktrees, running setup.sh</Text>}
          {phase === 'done' && (
            <Box flexDirection="column" rowGap={1}>
              <Text color="success">✓ Now on {cur.leaf}</Text>
              <Text>Claude reads its CLAUDE.md with your next message; its skills have reloaded.</Text>
              <Button key="close" onPress={() => $.ui.close({ id: PANE })}>
                Close
              </Button>
            </Box>
          )}
          {phase === 'failed' && (
            <Box flexDirection="column" rowGap={1}>
              <Text color="error">✗ Not switched: {message}</Text>
              <Button key="back" onPress={() => pick(selected)}>
                Back
              </Button>
            </Box>
          )}
        </Box>
        {phase !== 'switching' && (
          <Box flexDirection="row" columnGap={2}>
            <Button key="refresh" onPress={() => refresh($)}>
              Refresh
            </Button>
            {here && (
              <Button key="pull" onPress={() => doPull($)}>
                Pull
              </Button>
            )}
            <Button key="web" onPress={() => openWeb($)}>
              Open in browser
            </Button>
            {isPulling && <Text color="warning">{'Pulling ' + cur.leaf + '… fetching, fast-forwarding, running setup.sh'}</Text>}
            {!isPulling && isRefreshing && <Text dimColor>Fetching the workspaces from origin…</Text>}
            {!isPulling && !isRefreshing && pullNote && <Text color={isPullOk ? 'success' : 'error'}>{pullNote}</Text>}
            {!isPulling && !isRefreshing && !pullNote && listError && <Text color="error">{listError}</Text>}
            {!isPulling && !isRefreshing && !pullNote && !listError && fetchedAt && <Text dimColor>{'Fetched from origin at ' + fetchedAt}</Text>}
          </Box>
        )}
        {webUrl && (
          <Box flexDirection="row" columnGap={1}>
            <Text dimColor>Browser view</Text>
            <Link href={webUrl} />
          </Box>
        )}
        {!webUrl && webError && <Text color="error">{webError}</Text>}
      </Box>
    )
  })
}
