# Plugin systems — Claude Code mods and Codex skills (verified)

Verified 2026-10-21 against Claude Code 2.1.305 and Codex 0.163.0.

## Claude Code — mod command (runs code, no Claude turn)
Docs: <https://code.claude.com/docs/en/plugins/mods/overview.md>, <https://code.claude.com/docs/en/plugins/mods/api.md>.

- A mod is a plugin whose `hooks/hooks.json` is `{"modules": ["./register.js"]}` and `register.js` exports `register(on)`. "Mods are on by default. In the terminal, use Claude Code v2.1.287 or later."
- Command: register in `session.start` with `$.command.register({ name, description, argumentHint })`; handle `on('command.run', { command: name }, async ($, e) => ...)`. "`e.args` is the text typed after the command name, or an empty string". After the session starts "`/standup` appears with its description in the list you see when you type `/`" (bare name). `immediate: true` "let[s] the command run while Claude is working".
- Return `{ text }`: "The `text` you return prints in the transcript and Claude reads it." `{}` prints nothing.
- `$.command.register` "throws for a taken name"; "A hook that throws is skipped" → wrap in try/catch, register last.
- `$.process.run([...])` "takes an argument list and uses no shell. It resolves to `{ exitCode, stdout, stderr }` whatever the exit code. It rejects if the program can't start or is still running at the timeout, which is 30 seconds by default".
- Hooks module has no Node APIs; files via `$.fs.read/write/exists/stat/list`, env via `$.env.get`.
- Load/validate: `claude plugin validate <dir>`; one session: `claude --plugin-dir <dir>`; after install from shell run `/reload-plugins`.

## Claude Code — marketplace / install
- `<root>/.claude-plugin/marketplace.json`: required `name`, `owner`, `plugins[]` (`{name, source:"./path"}`) (<https://code.claude.com/docs/en/plugins/marketplace-reference.md>).
- Plugin manifest `.claude-plugin/plugin.json`: only `name` required (<https://code.claude.com/docs/en/plugins/manifest-reference.md>).
- `claude plugin marketplace add <dir> [--scope user|project|local]`; `claude plugin install <plugin>@<marketplace> [-s scope]`; `claude plugin uninstall`, `claude plugin marketplace remove`. A local relative-path marketplace reads plugin files in place.
- Plugin commands in `commands/<file>.md` become `/<plugin>:<file>`; a plugin **skill** named `x` also answers bare `/x` (skills docs). Skills/commands always go through a Claude turn; `` !`cmd` `` pre-exec needs `allowed-tools` and aborts on non-zero exit.

## Codex — plugin + skill
- Manifest `.codex-plugin/plugin.json` keys: `name, version, description, keywords, skills, mcpServers, apps, hooks, interface, extensions` (`codex-rs/core-plugins/src/manifest.rs:48-73`); paths must start with `./` (`:616-617`); `skills` defaults to `skills/`.
- `SKILL.md` frontmatter: `name` (optional, defaults to dir name, ≤64), `description` (required) (`codex-rs/skills/src/parser.rs:6-20, 64-85`).
- **No custom slash commands in 0.163**: popup holds only built-ins (`tui/src/bottom_pane/command_popup.rs:30-33`); unknown → "Unrecognized command" (`chat_composer.rs:3011-3016`). Plugin skills are namespaced `plugin:skill` (`ext/skills/src/loader/namespace.rs:13-15`) and invoked as `$auth-swap:auth-swap` or via `/skills`.
- Skills get no `$ARGUMENTS` and no `` !` `` execution; the model runs shell commands, sandboxed by default (see codex doc, Sandbox).
- Local marketplace file: `<root>/.agents/plugins/marketplace.json` (also accepted: `.claude-plugin/marketplace.json`) (`marketplace.rs:20-25`); required `name`, `plugins[]` with `{name, source:"./path"}` (`:997-1070`).
- `codex plugin marketplace add <dir>`; `codex plugin add <plugin>@<marketplace>`; `codex plugin remove <plugin>@<marketplace>`; `codex plugin marketplace remove <name>`.
- Codex hooks: 12 events, none for API errors / usage limits (`config/src/hook_config.rs:35-61`).
