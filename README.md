# AdminMenu

A single-file bash menu system for browsing Linux system information — no dependencies, no build step.

```
 █████╗ ██████╗ ███╗   ███╗██╗███╗   ██╗    ███╗   ███╗███████╗███╗   ██╗██╗   ██╗
██╔══██╗██╔══██╗████╗ ████║██║████╗  ██║    ████╗ ████║██╔════╝████╗  ██║██║   ██║
███████║██║  ██║██╔████╔██║██║██╔██╗ ██║    ██╔████╔██║█████╗  ██╔██╗ ██║██║   ██║
██╔══██║██║  ██║██║╚██╔╝██║██║██║╚██╗██║    ██║╚██╔╝██║██╔══╝  ██║╚██╗██║██║   ██║
██║  ██║██████╔╝██║ ╚═╝ ██║██║██║ ╚████║    ██║ ╚═╝ ██║███████╗██║ ╚████║╚██████╔╝
╚═╝  ╚═╝╚═════╝ ╚═╝     ╚═╝╚═╝╚═╝  ╚═══╝    ╚═╝     ╚═╝╚══════╝╚═╝  ╚═══╝ ╚═════╝
```

## Requirements

- **Bash 4+** (for `${var^^}` case conversion, `local -a`)
- A POSIX-compatible terminal
- Standard coreutils and procps (pre-installed on virtually all Linux distros)
- No additional packages required — optional tools are detected and warned about gracefully

## Usage

```bash
./menu.sh
# or
bash menu.sh
```

## Navigation

| Key | Action |
|---|---|
| `1`–`9`, `A`–`D` | Select a menu option |
| `B` | Go back to parent menu |
| `R` | Refresh current view |
| `?` | Show help |
| `E` | Exit |
| `Ctrl+C` | Return to parent menu |
| `0` | Exit (from submenus) |

Long output is automatically paginated through `less -R`.

## Menus

### 1 — Date/Time

| Key | Option |
|---|---|
| 1 | `timedatectl` |
| 2 | Current date & time |
| 3 | Calendar |
| 4 | Epoch / uptime |

### 2 — Arch/SystemInfo

| Key | Option |
|---|---|
| 1 | Display architecture |
| 2 | CPU info (`/proc/cpuinfo`) |
| 3 | CPU summary (model, cores) |
| 4 | PCI buses (`lspci`) |
| 5 | Block devices (`lsblk`) |
| 6 | USB buses (`lsusb`) |
| 7 | Memory (`free -g -h -t`) |
| 8 | Memory detailed (`/proc/meminfo`) |
| 9 | `uname -a` |
| 10 | Linux distribution info |
| 11 | Kernel version |
| 12 | OS release codename (`/etc/os-release`) |

### 3 — Disk Space

| Key | Option |
|---|---|
| 1 | `df -h` (excluding tmpfs) |
| 2 | `df -h` (all) |
| 3 | Inode usage |
| 4 | Current directory listing |
| 5 | Large files in `/` (top 20) |

### 4 — Network

| Key | Option |
|---|---|
| 1 | `ip addr` / `ifconfig` |
| 2 | Public IP |
| 3 | Private IP |
| 4 | Routing table |
| 5 | DNS config (`/etc/resolv.conf`) |
| 6 | Listening ports (`ss -tln`) |
| 7 | Active connections (`ss -tn`) |
| 8 | ARP table |
| 9 | Network interface stats (`/proc/net/dev`) |
| 10 | Tailscale status |

### 5 — Processes & Resources

| Key | Option |
|---|---|
| 1 | Top 10 CPU consumers |
| 2 | Top 10 Memory consumers |
| 3 | Running services count |
| 4 | Zombie processes |
| 5 | System load average |
| 6 | System load (detailed, `top -bn1`) |

### 6 — Users & Security

| Key | Option |
|---|---|
| 1 | Logged-in users (`who`) |
| 2 | User activity detail (`w`) |
| 3 | Recent logins (`last`) |
| 4 | Failed SSH attempts (last 1h) |
| 5 | Sudoers config |
| 6 | SSH authorized keys summary |
| 7 | Firewall rules (iptables) |
| 8 | Firewall status (ufw) |
| 9 | Listening ports |

### 7 — Kernel & System

| Key | Option |
|---|---|
| 1 | Kernel version |
| 2 | Kernel version (full) |
| 3 | System uptime |
| 4 | Kernel parameters (`sysctl -a`) |
| 5 | Mounted filesystems |
| 6 | fstab contents |
| 7 | Recent dmesg messages |
| 8 | Recent systemd errors |
| 9 | Kernel module list (`lsmod`) |
| 10 | Kernel boot cmdline (`/proc/cmdline`) |

### 8 — Storage & Filesystem

| Key | Option |
|---|---|
| 1 | Disk SMART status |
| 2 | Inode usage |
| 3 | Largest dirs in `/` (top 15) |
| 4 | Largest files in `/` (top 15, human-readable sizes) |
| 5 | Mount points with type |
| 6 | LVM volumes |
| 7 | RAID status |
| 8 | Disk I/O stats |

### 9 — Time & Scheduling

| Key | Option |
|---|---|
| 1 | User crontab |
| 2 | System cron directories |
| 3 | Anacron jobs |
| 4 | Systemd timers |

### A — Packages & Software

| Key | Option |
|---|---|
| 1 | Installed packages (count) |
| 2 | Recently installed (dpkg) |
| 3 | Updates available (apt) |
| 4 | Updates available (dnf) |
| 5 | Docker containers |
| 6 | Docker images |
| 7 | Auto-start services |

### B — Development & SWE

| Key | Option |
|---|---|
| 1 | Git repos in home |
| 2 | Node version |
| 3 | npm global packages |
| 4 | Python version |
| 5 | pip packages |
| 6 | Go version |
| 7 | Environment variables |
| 8 | Active SSH sessions |
| 9 | SSH known hosts |

### C — Performance & Troubleshooting

| Key | Option |
|---|---|
| 1 | vmstat snapshot (3s) |
| 2 | Per-CPU stats (mpstat) |
| 3 | Context switches & page faults |
| 4 | Connection states summary (`ss -s`) |
| 5 | Failed systemd units |
| 6 | Boot time analysis (top 20) |
| 7 | Boot critical chain |
| 8 | OOM killer history |
| 9 | Process tree (`pstree -p`) |
| 10 | Top 10 open file descriptors |
| 11 | CPU temps |
| 12 | CPU frequency/governor |
| 13 | Interrupt stats (top 20) |

### D — Run Custom Command

Enter any shell command to run ad-hoc.

## Root Privileges

Some options (dmesg, iptables, /proc/*/fd, smartctl, etc.) require root. Run with `sudo` for full access:

```bash
sudo ./menu.sh
```

When run without root, a warning is displayed and individual options fall back gracefully with a message.

## Optional Tools

The following tools are detected at runtime. If missing, a yellow warning is shown and affected options display a fallback message:

- `lspci`, `lsusb`, `lsblk`, `lsb_release` — Arch/SystemInfo
- `ifconfig`, `curl`, `tailscale` — Network
- `htop` — Processes & Resources
- `iptables`, `ufw`, `nmap` — Users & Security
- `smartctl` — Storage & Filesystem
- `systemctl` — Time & Scheduling
- `apt`, `dnf`, `yum`, `docker` — Packages & Software
- `git`, `node`, `python3`, `go` — Development & SWE
- `vmstat`, `mpstat`, `pidstat`, `systemd-analyze`, `sensors`, `pstree`, `ss`, `dmesg` — Performance & Troubleshooting

## File

Everything is in `menu.sh` — no build step, no dependencies, no framework.

```bash
bash -n menu.sh   # syntax check
./menu.sh          # run
```
