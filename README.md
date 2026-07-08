# AdminMenu — Agent Guide

## What This Is

A single-file bash menu system (`menu.sh`) that lets sysadmins and developers quickly browse system information on a Linux server — without memorizing arcane commands. It presents a colored, navigable TUI menu where each option runs a diagnostic or info command and returns to the menu afterward.

**Single source of truth:** `menu.sh` (463 lines). That's it. There is no build step, no dependencies, no framework.

## Project Structure

```
adminmenu/
├── menu.sh              # The entire application — all logic lives here
├── AGENTS.md            # This file
├── README.md            # End-user documentation (blank, TBD)
├── main.py              # Placeholder (not used; keep as-is)
├── pyproject.toml       # Python project metadata (not used; keep as-is)
├── .python-version      # Python version pin (not used; keep as-is)
└── .gitignore           # Ignores .venv and Python artifacts
```

## Running It

```bash
./menu.sh
# or
bash menu.sh
```

Requires **bash 4+** (for `${var^^}` case conversion, `local -a`, etc.) and a POSIX-compatible terminal. No other dependencies — only coreutils and procps are used.

## Architecture Overview

The entire application is a **single bash script** organized into three conceptual layers:

### 1. Infrastructure Layer (lines ~1–130)

Shared utilities, colors, and helpers that every menu uses:

| Function | Purpose |
|---|---|
| `greenprint`, `blueprint`, `redprint`, `yellowprint`, `magentaprint`, `cyanprint` | Color output wrappers using ANSI escape codes |
| `fn_bye()` | Exit the script cleanly |
| `fn_fail()` | Print "Unrecognized option." in red |
| `cmd_exists()` | Check if a command is in PATH |
| `is_root()` / `warn_not_root()` | Root privilege detection and warning |
| `run_cmd()` | Execute a command with automatic pagination (pipes through `less -R` if output exceeds terminal height) |
| `run_custom_command()` | Interactive prompt for ad-hoc command execution |
| `check_deps()` | Warn when optional tools (lspci, docker, etc.) are missing |
| **`run_submenu()`** | **The core engine** — renders a menu, reads input, dispatches actions, loops until exit/return |

### 2. Menu Functions (lines ~130–450)

Each menu is a function that calls `run_submenu()` with a flat list of key/label/action triples:

```
datetimemenu()         → Date/Time info
archsysteminfomenu()   → Architecture & system info
diskspacemenu()        → Disk usage
networkmenu()          → Network diagnostics
processmenu()          → Process & resource monitoring
usersecuritymenu()     → Users, security, firewall
kernelmenu()           → Kernel, mounts, dmesg, systemd
storagemenu()          → SMART, LVM, RAID, disk I/O
schedulingmenu()       → Cron, systemd timers
packagemenu()          → Package manager, Docker
devmenu()              → Git, Node, Python, Go, env vars
mainmenu()             → Root menu (ASCII art banner)
```

### 3. Entry Point (line 463)

```bash
mainmenu    # Called once at script end
```

## The `run_submenu()` Engine

This is the most important function in the codebase. Understanding it is key to adding, modifying, or debugging menus.

### Signature

```bash
run_submenu "Title" \
    "1" "Label text" "action string" \
    "2" "Another label" "another action" \
    "0" "Exit" "fn_bye" \
    "B" "Go Back" "return_to"
```

### Parameters

- **First arg:** Menu title (displayed in blue)
- **Remaining args:** Groups of 3 — key, label, action
- Navigation stubs (Exit/Go Back) use empty labels and are skipped during rendering

### Action Strings

The action string determines how the selection is handled:

| Action Value | Behavior |
|---|---|
| A shell command string (e.g., `"df -h"`) | Executed via `run_cmd()` with pagination |
| `"fn_bye"` | Exits the script |
| `"return_to"` | Returns to the calling menu |
| `"run_custom_command"` | Prompts user for a command to run |
| Name of a defined function (e.g., `"archsysteminfomenu"`) | Called directly (no output capture, allows nested menus) |

### Dispatch Logic (the critical path)

```
User presses key → case "${ans^^}" in
  E/EXIT → fn_bye
  R/REFRESH → loop restarts (re-renders menu)
  ?/HELP → prints help, loop continues
  * (anything else) → scan items for matching key
    → if found: execute action via inner case
    → if not found: fn_fail (red "Unrecognized option.")
```

**Important:** The `?` in the case pattern **must be quoted** as `"?"` — unquoted `?` is a glob wildcard that matches any single character, which would cause `"2"` to match `"?"|HELP`.

### Loop-Based (Not Recursive)

`run_submenu()` uses `while true` instead of recursion. This avoids stack buildup and makes navigation predictable. Each menu function calls `run_submenu()` once, and `return_to` exits the function to return to the caller.

## Adding a New Menu

1. **Add a new menu function** before `mainmenu()`:

```bash
###
### MY NEW MENU
###
mynewmenu() {
    # Optional: warn about missing optional tools
    check_deps "optional_tool1" "optional_tool2"

    run_submenu "My New Menu" \
        "1" "Option one description" "command to run" \
        "2" "Option two" "another command" \
        "0" "Exit" "fn_bye" \
        "B" "Go Back" "return_to"
}
```

2. **Register it in `mainmenu()`** by adding a line to the `run_submenu` call:

```bash
run_submenu "Main Menu" \
    ...existing items...
    "D" "My New Menu" "mynewmenu" \
    ...
```

Use keys `1`–`9`, then `A`–`Z` for additional menus. Keys `0` (Exit) and `B` (Go Back) are reserved for navigation stubs.

## Adding a New Option to an Existing Menu

Simply add a new triple to the existing `run_submenu` call:

```bash
"12" "New option label" "command to run" \
```

Re-number existing items if needed to keep the new item in a logical position.

## Key Conventions & Gotchas

### Color Usage

| Color | Purpose |
|---|---|
| Blue | Menu titles |
| Yellow | Menu item labels and keys |
| Red | Errors, exit, warnings |
| Cyan | Help text, custom command prompts |
| Magenta | ASCII art, special notes |
| Green | (available, not currently used in menus) |

### Command Execution Patterns

- **Always redirect stderr:** `command 2>/dev/null` to suppress error noise
- **Always provide fallbacks:** `command 2>/dev/null || echo 'command not found'`
- **Avoid `-p` flag with `ss`:** `ss -tlnp` produces extremely wide output (thousands of chars) when many processes share ports. Use `ss -tln` instead.
- **Use `--no-pager`** with systemctl/journalctl to avoid interactive pager prompts that break the menu flow
- **Use `head -N`** to cap output from commands that could produce unlimited lines (ps, last, etc.)

### The `check_deps()` Pattern

Call `check_deps` at the top of menu functions for optional tools. It prints a yellow warning if any listed command is missing from PATH. This is informational only — individual menu items should still handle missing commands with `|| echo '...'` fallbacks.

### `run_cmd()` vs Direct Function Calls

- `run_cmd()` captures output in a subshell via `$(eval "$cmd")` — use for one-shot commands
- Direct function calls (`"$a"` when `declare -f "$a"` succeeds) — use for nested menus that need their own interactive `read`
- **Never use `run_cmd()` for a submenu function** — the subshell capture prevents the nested menu from reading stdin properly

### SIGINT Handling

The `trap ... INT` at the bottom catches Ctrl+C and returns to the parent menu. The `return` in the trap handler works because `run_submenu` is called from a function context (not the top level).

### Input Timeout

`read -r -t 60` times out after 60 seconds and returns to the menu. This prevents the menu from hanging if a user walks away.

## File Layout

```
Lines  1–17:  Shebang, strict mode, color definitions
Lines 18–25:  Color print functions
Lines 26–50:  Exit helpers, root check, command existence
Lines 51–65:  run_cmd() — command execution with pagination
Lines 66–82:  run_custom_command() — ad-hoc command entry
Lines 83–96:  check_deps() — optional dependency warnings
Lines 97–200: run_submenu() — the core menu engine (~100 lines)
Lines 201–450: Individual menu functions (~15 lines each)
Lines 451–463: mainmenu() + entry point + SIGINT trap
```

## Testing

### Interactive Testing

```bash
./menu.sh
```

Navigate through menus, test each option, verify:
- Navigation (B = Back, E = Exit) works correctly
- Commands produce expected output
- Long output is paginated through `less`
- Invalid input shows "Unrecognized option." and re-displays the menu
- R (Refresh) re-renders the current menu
- ? (Help) shows navigation instructions

### Automated Testing (Piped Input)

```bash
# Navigate: Main → Arch → option 9 → Back → Exit
printf '2\n9\nB\nE\n' | bash menu.sh

# Full flow test: visit every menu
printf '1\n2\nB\n2\n3\nB\n3\n1\nB\n4\n2\nB\n5\n1\nB\n6\n1\nB\n7\n1\nB\n8\n1\nB\n9\n1\nB\nA\n1\nB\nB\n1\nB\nE\n' | bash menu.sh
```

### Syntax Check

```bash
bash -n menu.sh    # Reports syntax errors, exits 0 if OK
```

## Development Notes

- **No tests directory** — the script is tested manually and via piped input
- **No CI/CD** — single-file deployment to servers
- **No Python usage** — `main.py` and `pyproject.toml` are placeholders; ignore them
- **ShellCheck recommended** — run `shellcheck menu.sh` for linting (not installed by default)
- **Bash 4.0+ required** — `${var^^}` (case conversion) needs bash 4+

## History

| Phase | What Changed |
|---|---|
| Original | Crude menu with 4 categories, recursive navigation, dead code, no robustness |
| Phase 1 | Refactored to reusable `run_submenu()` engine, added custom command, refresh, help, pagination, dependency checks, root warnings, fixed glob `?` bug, removed dead code |
| Phase 2 | Added 7 new menus (Processes, Users/Security, Kernel, Storage, Scheduling, Packages, Development) — 13 total menu categories |
