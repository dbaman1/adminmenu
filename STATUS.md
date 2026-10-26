# STATUS

## Resume here

**State (2026-10-26):** `master` == `origin/master` (head: `git log -1`), tree clean. `bash -n` OK and
`tests/smoke.sh` 98/98 pass (non-root) as of 2026-10-26. Nothing is half-done.

**FIRST (<2 min):**
```bash
git status -sb                                   # expect: ## master...origin/master, nothing else
bash -n menu.sh && tests/smoke.sh                # expect: N passed, 0 failed, 0 warnings (N=98 today)
```

**THEN — next direction (pick one; none started):**
1. Decide on the duplicate options (Inode usage, Listening ports, uname/uptime). That's a
   product call, so ask the user.
2. Known gaps, not started:
   - `ssh_key_summary` ignores a custom `AuthorizedKeysFile`; fixing it means parsing `sshd -T`.
   - The full-filesystem scans don't use `nice`/`ionice` and give no "may take a while" notice.
   - `packagemenu`'s `check_deps "apt" "dnf" "docker"` always warns on single-distro hosts,
     because one of apt/dnf is always missing.

## What shipped

- **2026-10-26:** fixed all 19 audit findings (`3a52546`, `f15cbc1`; the never-committed
  `AUDIT.md` is deleted, so the detail lives in those commit messages), finished the `TRIAGE.md`
  quick fixes (`ce0176c`), and deleted the dead `uv init` Python scaffold at the user's request
  (`69e7dfc`). Added the `tests/smoke.sh` harness, which caught `cal` having no fallback
  (now fixed).

## Standing reference (don't re-derive)

- **There's no `.gitignore`, on purpose.** The old one held only Python patterns from the
  deleted scaffold. Don't restore it; the repo is `menu.sh`, `tests/smoke.sh` and Markdown.
- **The Bash ≥4 guard sits above `set -euo pipefail` on purpose.** `sh`/dash dies on
  `set -o pipefail`, so the guard has to run first to print its message.
- **Security invariants. Don't regress these:**
  - `find_large_files` reads NUL-separated `find` output and rejects any size that isn't plain
    digits. `[[ -ge ]]` evaluates arithmetic, so a crafted filename meant root code execution
    under sudo.
  - `run_cmd` strips control characters except tab and newline, which blocks terminal escape
    injection from filenames and remote text. As a result, action output can't show colour.
  - Helpers called directly (`find_large_files`, `ssh_key_summary`) bypass `run_cmd`, so they
    must replace control characters in paths themselves, with `${x//[[:cntrl:]]/?}`.
  - `run_custom_command` evals inside `( set +u; ... )`, so `exit`, `cd` and `IFS=` can't touch
    the menu.
  - The public-IP lookup uses HTTPS with `--max-time 5`.
- **Fallback pattern under `pipefail`:**
  - When the output gets piped through `head` or `grep`, write
    `if cmd_exists X; then X | head ...; else echo 'X not available'; fi`, not
    `X | head || echo ...`. With the second form, SIGPIPE or a no-match prints a false
    "not available".
  - When the result can be empty, put `|| echo 'None found'` inside the branch.
  - `cmd_exists` is available inside action strings.
- **Tests (`tests/smoke.sh`, ~20s; details in `CLAUDE.md`):**
  - Run it after any `menu.sh` change. The pass count equals the number of options, so it
    changes whenever options are added or removed. A FAIL means the action is broken.
  - It depends on the `BASH_SOURCE` guard at the bottom of `menu.sh`. Removing the guard makes
    the harness start the interactive menu.
  - It only catches breakage, not wrong output. Non-root runs only exercise the "need root"
    paths for sudoers, iptables, ufw, LVM and dmesg. `smartctl` and `dnf` aren't installed
    here, so those options have only been checked for their "not available" path.
- **Commit rhythm:** a short-lived branch, then a commit, then a `--ff-only` merge to `master`,
  then delete the branch and push `origin master`. Commit and push only when the user says to.
- `TRIAGE.md` is the original triage, now partly stale (most of its risks are fixed). Use it
  only for the open items listed above.
