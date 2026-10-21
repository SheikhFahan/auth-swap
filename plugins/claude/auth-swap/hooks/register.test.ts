import { expect, mock, test } from 'claude-code/testing'
import { toArgv } from './register'

test('maps what was typed to auth-swap arguments', () => {
  expect(toArgv('')).toEqual(['list'])
  expect(toArgv('  ')).toEqual(['list'])
  expect(toArgv('codex')).toEqual(['list', 'codex'])
  expect(toArgv('work')).toEqual(['use', 'claude', 'work'])
  expect(toArgv('codex personal')).toEqual(['use', 'codex', 'personal'])
  expect(toArgv('claude work')).toEqual(['use', 'claude', 'work'])
  expect(toArgv('help')).toEqual(undefined)
  expect(toArgv('a b c')).toEqual(undefined)
})

test('/auth-swap <name> runs the CLI by absolute path and shows its output', async ($, on) => {
  const ran: (readonly string[])[] = []
  mock.env(on, { HOME: '/Users/x' })
  on('session.start', async (_$, e) => ({ cwd: e.cwd }))
  on('command.register', async (_$, e) => ({ value: { command: e.name } }))
  on('fs.exists', async (_$, e) => ({ value: e.path === '/Users/x/.local/bin/auth-swap' }))
  on('process.run', async (_$, e) => {
    ran.push(e.argv)
    return { value: { exitCode: 0, stdout: 'Claude → work (w@example.com).\n', stderr: '', isStdoutTruncated: false, isStderrTruncated: false } }
  })
  await $.session.start({ cwd: '/tmp', surface: 'terminal', isInteractive: true })
  const result = await $.command.run({ command: 'auth-swap', args: 'work' })
  expect(ran).toEqual([['/Users/x/.local/bin/auth-swap', 'use', 'claude', 'work']])
  expect(result.text).toEqual('Claude → work (w@example.com).')
})

test('says so when the CLI is missing', async ($, on) => {
  mock.env(on, { HOME: '/Users/x' })
  on('session.start', async (_$, e) => ({ cwd: e.cwd }))
  on('command.register', async (_$, e) => ({ value: { command: e.name } }))
  on('fs.exists', async () => ({ value: false }))
  await $.session.start({ cwd: '/tmp', surface: 'terminal', isInteractive: true })
  const result = await $.command.run({ command: 'auth-swap', args: '' })
  expect(result.text?.startsWith('auth-swap is not installed')).toEqual(true)
})
