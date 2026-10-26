# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A sysadmin utility: a colorized terminal menu for browsing Linux system info without
memorizing commands. Intended to be dropped onto any server as a single file.

**Everything lives in `menu.sh`** (~500 lines, bash 4+). Do not add Python or other
dependencies; the value proposition is zero dependencies. `prompt.md` is a historical
brainstorming prompt, not a spec.

## Commands

```bash
bash -n menu.sh    # syntax check — the only automated check available
./menu.sh          # run
sudo ./menu.sh     # full access to dmesg/iptables/smartctl//proc/*/fd

# non-interactive smoke test: unknown key, then Exit (expect "Unrecognized option." / "Bye.", rc 0)
printf 'zz\n0\n' | timeout 10 ./menu.sh
```

No test suite, build, or linter (`shellcheck` is not installed). After changing
`menu.sh`, run `bash -n`, then exercise the affected menu manually — a broken action
string is a runtime failure, not a syntax error. Do not stand up a test harness as a side
effect of an unrelated change; propose it first.

## Architecture

### `run_submenu` is the whole framework

Every menu — including `mainmenu` — is one call to `run_submenu`, which takes a title
followed by a flat list of `key label action` triples:

```bash
datetimemenu() {
    run_submenu "Time/Date" \
        "1" "Calendar" "cal" \
        "0" "Exit" "fn_bye" \
        "B" "Go Back" "return_to"
}
```

It loops: render → `read -r -t 60` → dispatch → repeat. No recursion; submenus are
ordinary nested function calls unwound by `return_to`. **Adding a menu option means
adding one triple** — never hand-roll a render/read loop. A triple with an empty label
is skipped when rendering and matching.

### Action dispatch

| Action | Behavior |
|---|---|
| `fn_bye` | exit the script |
| `return_to` | `return` from `run_submenu` → back to the parent menu |
| `run_custom_command` | prompt for and `eval` an arbitrary command |
| any other **defined shell function** (`declare -f` hit) | called directly, output not captured |
| anything else | passed to `run_cmd`, which `eval`s it and paginates |

The `declare -f` check is why submenu functions and helpers like `find_large_files` work
as actions. It is also why **naming a helper the same as a shell command you meant to
run silently calls the helper instead**.

`run_cmd` captures output (stdout+stderr), then pipes through `less -R` if the line count
exceeds `tput lines`. Consequences:

- Actions needing an interactive TTY (`htop`, `top` without `-bn1`, `vi`) won't work as
  plain action strings — wrap them in a function.
- **Never put a pager inside an action string.** `run_cmd` already pages, and a nested
  `less` sees captured stdout and passes everything through unpaged.

### Action strings are `eval`'d — escape accordingly

Action strings are ordinary double-quoted arguments, so `$` expands **when the menu is
built**, not when the option is chosen. Escape any `$` meant for the inner command:

```bash
"3" "Private IP" "hostname -I | awk '{print \$1}'"
"12" "OS release codename" ". /etc/os-release ... \"\${VERSION_CODENAME:-...}\""
```

Two failure modes, both silent in review:

- An unescaped `$1` expands to the enclosing menu function's own first argument (none,
  so under `set -u` it aborts) instead of reaching the inner `awk`.
- An unescaped reference to a variable the *inner* command defines (`$VERSION_CODENAME`,
  sourced from `/etc/os-release`) is unbound at build time; under `set -u` that aborts
  the script **before the menu renders**, not when the option is selected.

Guard inner variables with `${VAR:-fallback}`: `set -u` applies inside `run_cmd` too, so a
field absent on some distros would otherwise error instead of degrading.

### Graceful degradation is the house style

Expected on every new option:

1. `check_deps "tool1" "tool2"` at the top of the menu function — prints one yellow note
   listing anything missing.
2. Every action string ends in a fallback chain so a missing tool prints a message:
   ```bash
   "lspci 2>/dev/null || echo 'lspci not found'"
   "ip addr 2>/dev/null || ifconfig 2>/dev/null || echo 'Neither ifconfig nor ip found'"
   ```

The script runs under `set -euo pipefail`; `run_cmd` and `run_custom_command` append
`|| true` so a failing user command returns to the menu instead of killing the script.
Keep that.

### Input handling

- Keys match case-insensitively via `${ans^^}`; `shopt -u nocasematch` is set
  deliberately so other comparisons stay case-sensitive.
- `R`, `?`, and `E` (plus the words `REFRESH`, `HELP`, `EXIT`) are handled before key
  matching and are reserved — do not assign them as menu keys.
- An idle menu returns to its parent after 60s.
- The `INT` trap's `return` pops one frame, so Ctrl+C leaves the current submenu for its
  parent instead of exiting.

## Conventions

- 4-space indentation, no tabs; `snake_case` for functions/variables, UPPERCASE for
  constants such as the color codes.
- `eval` is load-bearing in `run_cmd` and `run_custom_command` — do not refactor it away,
  and do not introduce `eval` anywhere else.
- Keep changes minimal (YAGNI/KISS); small cleanups are fine only within the code you are
  already touching.

## Keeping README in sync

`README.md` documents every menu option in tables and is the user-facing manual. When you
add, remove, or relabel an option, update the matching table row in the same change.
