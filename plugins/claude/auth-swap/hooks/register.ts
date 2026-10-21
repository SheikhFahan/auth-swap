import type { Register } from 'claude-code'

// /auth-swap runs the auth-swap CLI directly: no Claude turn, so it works even
// when the current account has hit its usage limit.
//   /auth-swap                 list saved logins
//   /auth-swap <name>          switch Claude Code to <name>
//   /auth-swap codex <name>    switch Codex to <name>

const USAGE = [
  'Usage:',
  '  /auth-swap                 list saved logins',
  '  /auth-swap <name>          switch Claude Code to a saved login',
  '  /auth-swap codex <name>    switch Codex to a saved login',
  'Add logins in a terminal: auth-swap login claude <name>',
].join('\n')

const PROVIDERS = ['claude', 'codex']

// The CLI arguments for what was typed after /auth-swap, or undefined to show usage.
export function toArgv(args: string): string[] | undefined {
  const words = args.trim().split(/\s+/).filter(Boolean)
  if (words.length === 0) return ['list']
  if (words.length === 1) {
    if (['help', '-h', '--help'].includes(words[0])) return undefined
    return PROVIDERS.includes(words[0]) ? ['list', words[0]] : ['use', 'claude', words[0]]
  }
  if (words.length === 2 && PROVIDERS.includes(words[0])) return ['use', words[0], words[1]]
  return undefined
}

export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    try {
      await $.command.register({
        name: 'auth-swap',
        description: 'List saved Claude/Codex logins, or switch to one',
        argumentHint: '[codex] [name]',
        immediate: true,
      })
    } catch {
      // name taken: leave the session alone
    }
    return next(e)
  })

  on('command.run', { command: 'auth-swap' }, async ($, e) => {
    const argv = toArgv(e.args)
    if (!argv) return { text: USAGE }

    const home = await $.env.get('HOME')
    const bin = `${home ?? ''}/.local/bin/auth-swap`
    if (!home || !(await $.fs.exists(bin))) {
      return { text: `auth-swap is not installed (expected ${bin}). Install it first; see the auth-swap README.` }
    }

    // A Codex switch stops and restarts Codex's shared daemon, which waits up
    // to 60 s for running turns; give it room. Claude switches finish fast.
    const timeoutMs = argv[0] === 'use' && argv[1] === 'codex' ? 180_000 : 30_000
    try {
      const ran = await $.process.run([bin, ...argv], { timeoutMs })
      const out = [ran.stdout.trim(), ran.stderr.trim()].filter(Boolean).join('\n')
      return { text: out || `auth-swap exited with code ${ran.exitCode}` }
    } catch (err) {
      return { text: `auth-swap could not run: ${err instanceof Error ? err.message : String(err)}` }
    }
  })
}
