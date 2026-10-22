I wrote `TRIAGE.md` (85 lines) at the repo root. The existing file there was empty, so nothing was overwritten, and no other files changed.

- **Purpose and stack:** `menu.sh` is a single Bash 4+ script of 509 lines with no dependencies. The Python files, `.venv` and `prompt.md` are dead leftovers.
- **Test coverage:** about 0% automated, because only `bash -n` is available.
- **Build and run:** `bash -n` passes, and I ran the script through piped input to confirm it starts, rejects unknown keys and exits cleanly.
- **Top risks:**
  - The zombie-process option at `menu.sh:327` is wrong. Its filter matches any line containing a capital `Z`, and it returned 5 lines here with no real zombies.
  - An idle or closed-stdin main menu exits the script with status 0, even though the message says "Returning to menu."
  - Several options scan the whole filesystem (`:290`, `:382`, `:92`) with no guard, and the public-IP `curl` at `:303` has no timeout.
  - `env | sort` at `:438` prints secrets to the screen.
  - There are several mislabeled or dead options. For example, "Recently installed" at `:415` isn't sorted by recency, and "Epoch / uptime" at `:253` shows no epoch.
- **Top tasks:**
  1. Fix the action-string bugs, which are one-liners.
  2. Fix the main-menu timeout exit.
  3. Add a Bash 4 check and a `curl` timeout.
  4. Remove the Python scaffold and trim noisy `check_deps` calls.
  5. Guard the entry point at `:509` so the script can be sourced and every action smoke-tested.

I did not fix any of these. Deleting the Python files should be confirmed with you first.
 args). Run here, it returned
   5 lines with no real zombies. The `|| echo 'None found'` fallback can't fire because awk
   exits 0. Fix: `awk '$8 ~ /^Z/'`, or `ps -eo stat,pid,ppid,comm | awk '$1 ~ /^Z/'`.
2. **Idle/EOF at the main menu silently exits the script** — `menu.sh:176-180`. The 60s
   timeout `return`s from `run_submenu`; for the main menu that ends `mainmenu` and the
   script exits 0 while printing "Returning to menu." (confirmed: `printf '' | bash menu.sh`
   → rc=0). Misleading message, and a closed stdin/terminal exits "successfully".
3. **Full-filesystem scans with no guard** — `menu.sh:290` (`find / -size +100M`), `:382`
   (`du -sh /*`), `:92` (`find_large_files`: `find / ... | sort -rn`). These are heavy I/O on
   production servers, with no `ionice`/`nice`/timeout/progress note. `:92`'s trailing
   `|| echo 'find not available'` applies to the `while` loop, so it's dead. Related:
   `:303` Public IP uses `curl` with no `--max-time`, so it can hang on air-gapped hosts, and
   it contacts a third party (`ifconfig.me`) without saying so.
4. **Sensitive data and unguarded privileged input** — `menu.sh:438` (`env | sort`) prints
   environment secrets (tokens, API keys) to the screen and scrollback. `run_custom_command`
   (`:71-86`) is an `eval` prompt that is root-equivalent under `sudo`. That is intentional
   per `CLAUDE.md`, but worth stating in the README since the goal is installing on all
   servers. Also no Bash-version check: on macOS bash 3.2 or old `sh`-linked shells the
   `${ans^^}` expansions fail with "bad substitution" mid-menu rather than at startup.
5. **Mislabeled, dead, or duplicate options** (quality debt that undermines trust):
   - `menu.sh:362` `| less -R` inside an action (dead, already flagged in `CLAUDE.md`).
   - `:415` "Recently installed (dpkg)" actually lists `--get-selections | tail -20`
     (alphabetical, not recent). Use `/var/log/dpkg.log` or `grep ' install ' ...`.
   - `:253` "Epoch / uptime" runs `uptime` only, with no epoch (`date +%s`).
   - `:344` "Failed SSH attempts": unit `ssh` is Debian-only (`sshd` on RHEL), and `grep`
     with no matches trips `pipefail` into the misleading "not available" fallback.
   - `check_deps` lists tools no option uses: `htop` (`:321`), `nmap` (`:338`), `go`
     fallback noise, and `apt dnf yum` (`:411`) always warns on single-distro hosts.
   - Duplicates: Inode usage (`:288`/`:381`), listening ports (`:307`/`:349`), kernel
     version/uname/uptime (`:273,275`/`:359-361`).
   - `:380` SMART hardcodes `/dev/sda` then `/dev/nvme0n1`.
   - `:304` `hostname -I` has no fallback (not on Alpine/BusyBox/BSD).

Stale deps: none. `pyproject.toml` declares `dependencies = []` and `requires-python
>=3.13`; the whole Python scaffold is dead code (`main.py`: 6 lines, "Hello from adminmenu!").

## Top 5 tasks by value/effort

| # | Task | Value | Effort | Where |
|---|---|---|---|---|
| 1 | **Fix the correctness bugs in risk #5 plus the zombie filter** (`:327`, `:415`, `:253`, `:344`, `:362`). Each is a one-line action-string edit; update matching README rows in the same change. | High | S | `menu.sh`, `README.md` |
| 2 | **Fix main-menu timeout/EOF exit**: have `run_submenu` distinguish the top-level menu (e.g. print "Timed out. Exiting." and `exit` in `mainmenu`, or `exit` on EOF), and correct the message. | Med | S | `menu.sh:176-180` |
| 3 | **Add a Bash ≥4 guard and `--max-time 5` on curl**: a 3-line check after `set -euo pipefail`, plus the curl timeout. Cheap hardening for the "drop on any server" goal. | Med | S | `menu.sh:2`, `:303` |
| 4 | **Remove the dead Python scaffold** (`main.py`, `pyproject.toml`, `.python-version`, `.venv/`) and trim `check_deps` noise (`htop`, `nmap`, `yum`). Removes the contradiction that `CLAUDE.md` currently has to explain. Confirm with the owner first (deleting files). | Med | S | repo root, `:321,338,411` |
| 5 | **Make the script smoke-testable**: guard the entry point (`[[ "${BASH_SOURCE[0]}" == "$0" ]] && mainmenu` at `:509`) so it can be sourced. A small script can then run every action string with a timeout and flag non-zero/"command not found" output. That catches the class of bug that `bash -n` can't. Per `CLAUDE.md`, propose the harness before building it. | High | M | `menu.sh:509`, new script |

Ranking note: 1-3 are same-day fixes with direct user-visible payoff; 5 has the best
long-term payoff but is the only one that needs a design decision, so it ranks last by
effort despite its value. Resource-heavy scans (risk #3) deserve a follow-up of adding a
"this may take a while" notice and `nice -n 19 ionice -c3`, once task 1 is done.
