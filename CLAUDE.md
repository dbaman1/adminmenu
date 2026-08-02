# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A sysadmin utility: a colorized terminal menu for browsing Linux system info without
memorizing commands. Intended to be dropped onto any server as a single file.

**Everything lives in `menu.sh`.** `main.py`, `pyproject.toml`, `.python-version`, and
`.venv/` are leftovers from a `uv init` scaffold — nothing imports them, nothing runs
them. Do not add Python; the value proposition is zero dependencies.

`prompt.md` is a historical brainstorming prompt, not a spec.

## Commands

```bash
bash -n menu.sh    # syntax check — the only automated check available
./menu.sh          # run
sudo ./menu.sh     # full access to dmesg/iptables/smartctl//proc/*/fd
```

There is no test suite, no build, and no linter configured (`shellcheck` is not
installed). After changing `menu.sh`, run `bash -n` and then exercise the affected menu
manually — a broken action string is a runtime failure, not a syntax error.

## Architecture

### `run_submenu` is the whole framework

Every menu — including the main menu — is one call to `run_submenu`, which takes a
title followed by a flat list of `key label action` triples:

```bash
datetimemenu() {
    run_submenu "Time/Date" \
        "1" "Calendar" "cal" \
        "0" "Exit" "fn_bye" \
        "B" "Go Back" "return_to"
}
```

It loops: render → `read -r -t 60` → dispatch → repeat. No recursion; submenus are
stacked as ordinary function calls and unwound by `return_to`. **Adding a menu option
means adding one triple** — never hand-roll a render/read loop.

### Action dispatch

The third element of a triple is resolved in `run_submenu` as:

| Action | Behavior |
|---|---|
| `fn_bye` | exit the script |
| `return_to` | `return` from `run_submenu` → back to the parent menu |
| `run_custom_command` | prompt for and `eval` an arbitrary command |
| any other **defined shell function** (`declare -f` hit) | called directly, output not captured |
| anything else | passed to `run_cmd`, which `eval`s it and paginates |

That `declare -f` check is why submenu functions and helpers like `find_large_files`
work as actions with no special casing. It is also why **naming a helper the same as a
shell command you meant to run will silently call the helper instead**.

`run_cmd` captures output, then pipes through `less -R` if the line count exceeds
`tput lines`. Two consequences:

- Actions needing an interactive TTY (`htop`, `top` without `-bn1`, `vi`) will not work
  as plain action strings — wrap them in a function.
- **Never put a pager inside an action string.** `run_cmd` already handles paging, and
  a nested `less` runs with stdout captured, so it passes everything through unpaged.
  The `| less -R` in the "Kernel parameters" action (`menu.sh:360`) is dead weight —
  don't copy that pattern.

### Action strings are `eval`'d — escape accordingly

Any `$` meant for an inner tool must be escaped in the source. Action strings are
ordinary double-quoted arguments, so they expand **when the menu is built**, not when
the option is chosen:

```bash
"3" "Private IP" "hostname -I | awk '{print \$1}'"
"12" "OS release codename" ". /etc/os-release ... \"\${VERSION_CODENAME:-...}\""
```

Two distinct failure modes, both silent in review:

- An unescaped `$1` expands to `run_cmd`'s own first positional argument.
- An unescaped reference to a variable the *inner* command defines (`$VERSION_CODENAME`,
  sourced from `/etc/os-release`) is unbound at build time, and under `set -u` that
  aborts the script **before the menu ever renders** — not when the option is selected.

For the same reason, guard inner variables with `${VAR:-fallback}`: `set -u` applies
inside `run_cmd`'s subshell too, so a field absent on some distros would otherwise error
instead of degrading.

### Graceful degradation is the house style

Two layers, both expected on every new option:

1. `check_deps "tool1" "tool2"` at the top of the menu function — prints one yellow
   note listing anything missing.
2. Every action string ends in a fallback chain, so a missing tool prints a message
   instead of a bare error:
   ```bash
   "lspci 2>/dev/null || echo 'lspci not found'"
   "ip addr 2>/dev/null || ifconfig 2>/dev/null || echo 'Neither ifconfig nor ip found'"
   ```

The script runs under `set -euo pipefail`, but `run_cmd` and `run_custom_command`
append `|| true` so a failing user command returns to the menu rather than killing the
script. Keep that.

### Input handling

- Keys are matched case-insensitively via `${ans^^}` (bash 4+; `shopt -u nocasematch`
  is set deliberately so other comparisons stay case-sensitive).
- `R`, `?`, and `E` are handled by `run_submenu` itself and are reserved — do not
  assign them as menu keys.
- `read -r -t 60` means an idle menu returns to its parent after 60s.
- The `INT` trap runs inside the innermost executing function, so its `return` pops one
  frame: Ctrl+C leaves the current submenu for its parent instead of exiting.

### Keeping README in sync

`README.md` documents every menu option in tables and is the user-facing manual. When
you add, remove, or relabel an option, update the matching table row in the same change.

## Coding Guidelines

# Project General Coding Guidelines

You are a collaborative developer on this team: a thoughtful implementer and a
constructive critic. Write clean, maintainable code and say plainly when a
request looks mistaken.

## Working style

Keep responses focused and concise. Lead with the outcome — the first sentence
answers "what happened" or "what did you find" — then supporting detail. Say in
one sentence what you're about to do before the first tool call; while working,
update only on an important finding or a change of direction.

Match written deliverables (Markdown docs, reports, summaries) to what the task
needs. Cover the substance; no filler sections, redundant summaries, or
boilerplate.

## Test-driven implementation

1. Write ONE failing test for ONE concept.
2. Write the minimal code to pass it.
3. Refactor: extract small functions, improve names, remove duplication.
4. Confirm the whole suite still passes.

**This repo has no test harness.** Do not stand one up as a side effect of an unrelated
change — verify with `bash -n` plus a manual run of the affected menu. If a change is
large enough to warrant tests, propose the harness first rather than assuming one.

## Shell Scripts

# Structure and Formatting

Shebang: Always start with #!/bin/bash or #!/usr/bin/env bash to specify the interpreter. 
Indentation: Use 2 spaces (per Google) or 4 spaces (per Vokal) consistently; avoid tabs.
Line Length: Keep lines under 80–120 characters; use backslashes (\) for line continuation. 
Extensions: Use .sh for libraries; executables may have no extension or .sh depending on deployment. 
Naming: Use snake_case for variables and functions; reserve UPPERCASE for environment variables. 
Syntax and Best Practices

Command Substitution: Prefer $(...) over backticks `...` for better readability and nesting. 
Variable Quoting: Always quote variables, e.g., "$var", to handle spaces and prevent word splitting. 
Variable Expansion: Use curly braces ${var} to clearly delimit variable names. 
Conditionals: Use [[ ... ]] instead of [ ... ] for safer conditional expressions. 
Arithmetic: Perform numeric operations within (( ... )) blocks.
Error Handling and Safety

Strict Mode: Use set -euo pipefail at the start of scripts to exit on errors (-e), treat unset variables as errors (-u), and catch pipeline failures (-o pipefail).
Exit Codes: End successful scripts with exit 0 and failures with non-zero statuses. 
Security: avoid SUID/SGID permissions on scripts; use mktemp for temporary files.
Documentation: Include a header comment describing the script’s purpose, arguments, and dependencies. 

**Where this repo pins the above:** indentation is **4 spaces** (`menu.sh` uses it
throughout, no tabs). `eval` is load-bearing in `run_cmd` and `run_custom_command` —
action strings and the ad-hoc command prompt are `eval`-based by design. Do not
refactor those away; do not introduce `eval` anywhere else.

## Design principles

**YAGNI** — implement what is needed now. No speculative generality, no
future-proofing, no premature optimization.

**KISS** — the simplest thing that works wins. Complexity is the cost, not the
product.

**DRY** — one authoritative representation per piece of knowledge. Ask: if this
changes, how many places need editing?

**SRP** — one reason to change per function, class, or module. If you can't name
it without "and", split it.

## Leaving the code
Leave it cleaner than you found it: opportunistic small improvements, within the
scope of the change you are already making.

<tone_preference>
Keep outputs reasonably concise. Match document length to the task.
</tone_preference>  