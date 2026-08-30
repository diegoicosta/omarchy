# Plan: Kilo Code as a first-class Omarchy agent

Adds [Kilo Code](https://kilo.ai/cli) to Omarchy's coding agents with the same standing as Claude Code and Codex — not a wrapped CLI that happens to be installed, but a selectable default agent with a menu row, a brand mark, theme sync, skill exposure, a usage panel tab, a migration for existing installs, and test coverage.

## Problem

Omarchy pre-wires ten coding agents and picks none of them for you. Kilo Code is not among them, and the gap is not cosmetic: `omarchy default agent kilo` fails outright.

The reason is that "supported agent" is a closed list in two places, and nothing about being installed gets you onto it:

- `bin/omarchy-default-agent` enumerates the ten accepted names in a `case`. Anything else prints usage and exits 1.
- `bin/omarchy-agent` enumerates the same ten again, mapping each to the flags that launch it unattended. Anything else prints "Unsupported default agent".

That closure is deliberate, not an oversight. Omarchy launches agents in a don't-stop-to-ask mode, and every agent spells that differently — `--auto` for OpenCode, `--yolo` for Crush, `--permission-mode auto` for Claude, `--approve-for-me` for Codex, `--dangerously-skip-permissions` for Antigravity. Handing a prompt to a session differs too. Those few lines per agent cannot be derived from a package name, so each supported agent is written by hand.

`omarchy-mise-install npm:@kilocode/cli kilo` — the escape hatch `manual/17-ai.md` documents for wrapping any other CLI — gets you a working `kilo` command and nothing else. Everything that routes through `omarchy-agent` stays closed to it: the `Super + Shift + Ctrl + A` keybinding, the Quake console seed in `default/hypr/qconsole.lua`, `omarchy agent prompt`, and the crash handoff in `bin/omarchy-agent-crash`.

## The integration surface

Supporting an agent fully means thirteen touchpoints. They are independent, which is why partial support is easy to reach by accident and easy to mistake for the real thing.

| # | Capability | Owner |
|---|---|---|
| 1 | Lazy launcher stub on `PATH` | `install/user/mise.sh` → `bin/omarchy-mise-install` |
| 2 | Accepted as a default agent | `bin/omarchy-default-agent` |
| 3 | Launch and prompt semantics | `bin/omarchy-agent` |
| 4 | Menu row under Defaults > Agent | `default/omarchy/omarchy-menu.jsonc` |
| 5 | Brand mark for that row | `default/fonts/omarchy/omarchy.ttf` |
| 6 | Theme follows the Omarchy theme | `default/themed/*.tpl`, `bin/omarchy-theme-set` |
| 7 | Omarchy skill visible to the agent | `bin/omarchy-provision-user` |
| 8 | Usage panel tab | `bin/omarchy-agent-usage-*`, `shell/plugins/agents/assets/` |
| 9 | Terminal shortcut | `default/bash/aliases` |
| 10 | Existing installs get it | `migrations/*.sh` |
| 11 | Removable with the other optional agents | `bin/omarchy-remove-preinstalls` |
| 12 | Documented | `manual/17-ai.md` |
| 13 | Covered by the suites | `test/shell.d/*` |

Items 5 and 8 are where "first-class" is actually decided. Five of the ten shipped agents carry a real brand mark in the private icon font rather than a stand-in Nerd Font glyph, and three have a usage collector. An agent without them is visibly a guest.

## Why Kilo fits cleanly

Kilo Code is an OpenCode fork. Its source lives under `packages/opencode/`, it still reads legacy `opencode.json[c]`, and it inherits OpenCode's TUI, theme format, and session database. Omarchy already integrates OpenCode, so most of the work is a second instance of a pattern already in the tree rather than new machinery.

Facts this plan depends on, each read from Kilo's own source or verified against a real install rather than inferred:

- **Package**: `npm:@kilocode/cli`, binary `kilo`. Installs through mise like the other npm-backed agents.
- **Unattended flag**: `--auto`, defined on the interactive command as *"auto-approve permissions that are not explicitly denied (dangerous!)"*. This is the same flag and the same semantics Omarchy already uses for OpenCode.
- **Prompt**: `--prompt`, also on the interactive command, so a seeded session stays open instead of running one headless turn and exiting. This matters for the crash handoff, which must leave a window behind.
- **Skills**: Kilo loads `.claude/skills/` and `.agents/skills/` as compatibility directories, plus its own `~/.kilo/skills`. Since `bin/omarchy-provision-user` already fills `~/.agents/skills`, the Omarchy skill reaches Kilo with no change at all; the symlink into `~/.kilo/skills` is added so it also appears where Kilo's own skill listing and `/reload` look first.
- **Config**: `~/.config/kilo/kilo.jsonc` for the agent, `~/.config/kilo/tui.jsonc` for the terminal UI, custom themes as JSON under `~/.config/kilo/themes/`. `autoupdate` is a documented key, which matters because mise owns the version.
- **Usage data**: `~/.local/share/kilo/kilo.db`, an embedded SQLite database carrying one row per message with provider, model, token counts, and a millisecond `time.created`. Structurally identical to the OpenCode database the Claude and Codex collectors already read.

## Routes considered

**A shell plugin.** Rejected: not possible. `omarchy plugin add` installs Quickshell desktop plugins — manifests declaring `kinds` of `bar`, `bar-widget`, `menu`, `overlay`, `panel`, or `service`, loaded as QML into the running shell and validated by `bin/omarchy-plugin-validate`. No plugin kind registers a CLI command or an agent. The agent registry is not extensible from outside the tree.

**User-level only, no repo changes.** Gets roughly two thirds of the way and survives `omarchy update`: the mise stub, a menu row through `~/.config/omarchy/extensions/omarchy-menu.jsonc`, theme sync through a `~/.config/omarchy/hooks/theme-set.d/` hook, and the Omarchy skill (already working). It cannot deliver items 2 and 3, and therefore cannot deliver the keybinding, the Quake console, `omarchy agent prompt`, or crash diagnosis. Shadowing the two binaries from `$HOME` does not work either: `default/bash/env-bootstrap` *appends* `~/.local/bin` to `PATH` so system binaries keep precedence.

**Editing the installed files in place.** Works immediately and needs no rebuild — Omarchy is bash, JSONC, and QML, with nothing to compile — but `/usr/bin/omarchy-agent` and `/usr/bin/omarchy-default-agent` belong to the `omarchy` package and are overwritten on the next update. Useful for trying the change, not for living with it.

**Patching the tree (this plan).** The only route that reaches all thirteen points and keeps them. It is also the shape an upstream contribution takes, so nothing here is throwaway work.

## The change

Registry and launch:

- `bin/omarchy-default-agent` accepts `kilo`, `kilo-code`, and `kilocode`, mapping to package `npm:@kilocode/cli` and display name "Kilo Code".
- `bin/omarchy-agent` launches `kilo --auto`, adding `--prompt "$prompt"` when one is given — the same arm as OpenCode, which is what the shared lineage earns.
- `install/user/mise.sh` installs the stub on every machine, so it is refreshed along with everything else mise manages on `omarchy update`.
- `bin/omarchy-remove-preinstalls` drops `~/.local/bin/kilo` with the other optional agents.

Presentation:

- `default/omarchy/omarchy-menu.jsonc` gains `setup.default.agent.kilo`, placed alphabetically between Grok and omp.
- `default/fonts/omarchy/omarchy.ttf` gains the Kilo mark at `U+E90A`, taken from the single-path monochrome `KiloLogo` on kilo.ai — upstream publishes no standalone monochrome SVG, and the provenance line in `default/fonts/omarchy/README.md` says so.

Theme:

- `default/themed/kilo.json.tpl` generates a full OpenCode-schema theme from the active Omarchy palette. Kilo inherits OpenCode's `system` theme, which merely adapts to terminal ANSI colors; generating a real theme instead gives exact Omarchy colors, the way Claude and Pi are handled.
- `bin/omarchy-theme-set-kilo` installs it to `~/.config/kilo/themes/omarchy.json` and, with `--activate`, points `tui.jsonc` at it. It refuses to rewrite a `tui.jsonc` that is not plain JSON — the file is JSONC by name, `jq` only reads strict JSON, and silently discarding a user's comments is worse than telling them to run `/themes`.
- `bin/omarchy-restart-kilo` sends `SIGUSR2` so a running session retints, mirroring `bin/omarchy-restart-opencode`.
- Both are wired into `post_theme_commands` in `bin/omarchy-theme-set`; `install/user/theme.sh` activates on a fresh install.
- `config/kilo/kilo.jsonc` sets `autoupdate: false`, because mise owns the version. `config/kilo/tui.jsonc` selects the generated theme.

Skill and panel:

- `bin/omarchy-provision-user` symlinks every shipped skill into `~/.kilo/skills` alongside the existing five destinations.
- `bin/omarchy-agent-usage-kilo` reads `~/.local/share/kilo/kilo.db` read-only and prints the panel's record contract. It filters no provider — a Kilo subscription is whatever ran through Kilo, on whichever model — and reports no limits, because Kilo publishes no usage or balance endpoint and an invented meter is worse than none. A short-lived cache keeps a panel refresh from re-walking the database.
- `shell/plugins/agents/assets/kilo.svg` and `kilo-light.svg` give the panel a mark on dark and light surfaces.

The agents plugin itself needs no change: `bin/omarchy-agent-usage-update` runs every `omarchy-agent-usage-*` collector it finds, and `shell/plugins/agents/Main.qml` treats a provider absent from settings as enabled.

Reach and documentation:

- `migrations/1788087372.sh` installs the stub, seeds only the config files that are missing, symlinks the skill, and installs the theme — activating it only for someone who was not already running Kilo with a theme of their own.
- `default/bash/aliases` adds `ck`, alongside `c`, `cx`, and `cy`.
- `manual/17-ai.md` documents the command, the alias, the theme sync, the skill directory, and the panel coverage.
- `test/shell.d/menu-test.sh`, `default-agent-test.sh`, and `user-theme-test.sh` are updated to expect Kilo, including the icon font's charset range moving to `e900-e90a`.

## Applying it to a running Omarchy install

Nothing here compiles, and no reinstall is involved in any option below.

### Option A — dev-link a checkout (survives updates)

The supported way to run a modified Omarchy. On the Omarchy machine:

```bash
git clone <your-fork> ~/omarchy
cd ~/omarchy && git checkout agents/kilo-code-support
omarchy dev link ~/omarchy
# reboot, so every layer agrees on OMARCHY_PATH
```

`omarchy dev link` writes `/etc/omarchy.conf` so `$OMARCHY_PATH` resolves to the checkout, and prepends its `bin/` to `PATH` and to sudo's `secure_path`. It covers exactly the trees this change touches — `bin/`, `default/`, `config/`, `shell/`, `themes/`, `migrations/`.

Then, once:

```bash
omarchy-mise-install npm:@kilocode/cli kilo   # or: bash migrations/1788087372.sh
omarchy default agent kilo
```

One caveat specific to the font: `omarchy.ttf` is installed by the `omarchy-settings` package to `/usr/share/fonts/omarchy/`, not resolved through `$OMARCHY_PATH`, and fontconfig prefers the packaged copy over one in `~/.local/share/fonts`. Until a settings release carries it, the new menu row renders without its glyph. To preview it, replace the packaged file or add a `<rejectfont>` rule under `~/.config/fontconfig/conf.d/`, then restart the shell — Qt reads the font database at startup, so `omarchy menu refresh` alone will not pick it up.

### Option B — patch in place (immediate, wiped by the next update)

For trying it without a reboot. As root on the Omarchy machine, apply the `bin/omarchy-default-agent` and `bin/omarchy-agent` hunks to `/usr/bin/`, then run the two commands above. Effective immediately, no reboot. `omarchy update` overwrites both files, and you redo it. Everything else in this change either lives in `$HOME` or is cosmetic while the package files are stock.

### A new install

Nothing to do. `install/user/mise.sh` installs the stub, `install/user/theme.sh` activates the theme, and `bin/omarchy-provision-user` links the skill. Picking Kilo under _Setup > Defaults > Agent_ installs it if it is not there yet.

## Verification status

Verified:

- **Launch flags** read from Kilo's own source rather than inferred: `--auto` and `--prompt` are both defined on the interactive command.
- **The usage collector** run against a real `~/.local/share/kilo/kilo.db` — 294 assistant messages across 2 sessions and 7 active days, split into `deepseek-chat` and `deepseek-reasoner`, cross-checked field by field against raw SQL over the 419-row `message` table.
- **The glyph** rendered from the built font and inspected: correct silhouette, hollow counters, 896×896, matching the other marks' optical size.
- **The menu entry** parsed through the real `MenuModel.js` and asserted against the exact contract `menu-test.sh` enforces, including alphabetical position.
- **Every changed file** syntax-checked: `bash -n` across all shell files, `py_compile` on the collector, JSON and XML validity on the configs and marks, and the theme template proven to render to valid JSON using only variables the existing templates already use.

Not yet run:

- `./test/all` needs Linux and bash 5; the font assertion additionally needs `fc-query`. The suites were updated and syntax-checked, but must be executed on an Omarchy machine.
- The theme, the reload signal, and the panel tab have not been seen in the running UI. Per `agents/skills/visual-verification.md`, the menu row, the retint, and the panel need confirming there before this is called done.

Assumed rather than verified:

- That Kilo honors `SIGUSR2` for a live theme reload. It is OpenCode's mechanism and Kilo is OpenCode's fork, but the signal handler has not been observed. If it does not, `bin/omarchy-restart-kilo` is a harmless no-op and the theme applies at next start.
