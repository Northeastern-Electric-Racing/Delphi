// The delphi mod: /ws opens a pane to keep open, with every Delphi workspace and main as cards
// grouped by project (.delphi/switch.sh --list). Press one to select it, then Switch workspace, which
// runs switch.sh; /ws <name> switches straight away. A switch changes CLAUDE.md and the skills on
// disk, but this session keeps the ones it loaded, so after one the pane and the line under the
// prompt ask for a restart. All the git work is switch.sh's; outside a Delphi clone /ws says so.
import type { EngineInterface, Register } from 'claude-code'

// One Delphi workspace, or main: its name (switch.sh takes it), last part, and the folders above it
type Ws = { name: string; leaf: string; group: string }
type Phase = 'pick' | 'confirm' | 'switching' | 'done' | 'failed'

let root = '' // this clone's top, where .delphi/switch.sh is; '' outside a Delphi clone
let all: Ws[] = []
let here = '' // the one this clone is on
let isDirty = false // tracked files have changes, so switch.sh would refuse
let selected = ''
let phase: Phase = 'pick'
let message = ''

function toWs(name: string): Ws {
  if (name === 'main') return { name, leaf: 'main', group: 'project folders, templates, CI' }
  const parts = name.split('/')
  return { name, leaf: parts[parts.length - 1], group: parts.slice(1, -1).join(' / ') }
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

async function load($: EngineInterface) {
  const list = await run($, ['bash', root + '/.delphi/switch.sh', '--list'], 60_000)
  const lines = list.stdout.split('\n').filter(l => l.trim() !== '')
  if (list.exitCode !== 0) message = 'Could not list the workspaces: ' + list.stderr.trim()
  all = lines.map(l => toWs(l.slice(2)))
  here = lines.find(l => l.startsWith('* '))?.slice(2) ?? ''
  isDirty = (await run($, ['git', 'diff', '--quiet', 'HEAD', '--'], 10_000)).exitCode !== 0
  if (!all.some(w => w.name === selected) || (selected === here && phase === 'pick')) {
    selected = all.find(w => w.name !== here)?.name ?? ''
  }
  $.ui.invalidate('ui.render')
}

async function doSwitch($: EngineInterface) {
  if (phase === 'switching' || !selected || selected === here) return
  phase = 'switching'
  message = ''
  $.ui.invalidate('ui.render')
  const r = await run($, ['bash', root + '/.delphi/switch.sh', selected], 600_000)
  if (r.exitCode === 0) {
    phase = 'done'
    await $.ui.status('switched to ' + leafOf(selected) + '; restart Claude Code in this folder')
  } else {
    phase = 'failed'
    message = r.stderr.trim().split('\n').pop() || 'switch.sh failed'
  }
  await load($)
}

const PANE = 'delphi-workspaces'

export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    try {
      await $.command.register({
        name: 'ws',
        description: 'Delphi: open the workspace switcher, or switch this clone to a workspace',
        argumentHint: '[workspace]',
      })
    } catch (err) {
      await $.ui.log('/ws not added: ' + String((err as Error)?.message ?? err))
    }
    return next(e)
  })

  on('command.run', { command: 'ws' }, async ($, e) => {
    if (!(await findRoot($))) return { text: 'Not in a Delphi clone: no .delphi/switch.sh at the top of this repository.' }
    phase = 'pick'
    message = ''
    const name = (e.args ?? '').trim()
    if (name) {
      await load($)
      selected = name
      await doSwitch($)
      if (phase === 'done') return { text: 'On ' + name + ': restart Claude Code in this folder to load its CLAUDE.md and skills.' }
      return { text: phase === 'failed' ? 'Not switched: ' + message : 'Already on ' + name + '.' }
    }
    await $.ui.open({ id: PANE, title: 'Workspaces', focus: true, closeOnEscape: true })
    await load($)
    return {}
  })

  on('ui.render', { component: 'Pane', requestId: PANE }, async ($, e) => {
    const { Box, Text, Button } = $.ui.resolve(e)
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
                <Button key="refresh" onPress={() => load($)}>
                  Refresh
                </Button>
              </Box>
            </Box>
          )}
          {phase === 'switching' && <Text color="warning">Switching to {leafOf(selected)}… fetching, parking worktrees, running setup.sh</Text>}
          {phase === 'done' && (
            <Box flexDirection="column" rowGap={1}>
              <Text color="success">✓ Now on {cur.leaf}</Text>
              <Text>Restart Claude Code in this folder to load its CLAUDE.md and skills.</Text>
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
      </Box>
    )
  })
}
