#!/bin/bash
set -euo pipefail
shopt -u nocasematch

### Colors ##
ESC=$(printf '\033')
RESET="${ESC}[0m"
BLACK="${ESC}[30m"
RED="${ESC}[31m"
GREEN="${ESC}[32m"
YELLOW="${ESC}[33m"
BLUE="${ESC}[34m"
MAGENTA="${ESC}[35m"
CYAN="${ESC}[36m"
WHITE="${ESC}[37m"
DEFAULT="${ESC}[39m"

### Color Functions ##
greenprint() { printf "${GREEN}%s${RESET}\n" "$1"; }
blueprint()  { printf "${BLUE}%s${RESET}\n" "$1"; }
redprint()   { printf "${RED}%s${RESET}\n" "$1"; }
yellowprint(){ printf "${YELLOW}%s${RESET}\n" "$1"; }
magentaprint(){ printf "${MAGENTA}%s${RESET}\n" "$1"; }
cyanprint()  { printf "${CYAN}%s${RESET}\n" "$1"; }

### Exit / Navigation Helpers ##
fn_bye() {
    echo
    echo "Bye."
    exit 0
}

fn_fail() {
    redprint "Unrecognized option."
}

### Check if a command exists (respects PATH) ###
cmd_exists() {
    command -v "$1" >/dev/null 2>&1
}

### Check if running as root ###
is_root() {
    [[ $EUID -eq 0 ]]
}

warn_not_root() {
    if ! is_root; then
        yellowprint "Warning: Some commands may require root privileges."
        echo
    fi
}

### Run a command with pagination if output is long ###
run_cmd() {
    local cmd="$1"
    local output
    output=$(eval "$cmd" 2>&1) || true
    local lines
    lines=$(echo "$output" | wc -l)
    if [[ "$lines" -gt $(tput lines 2>/dev/null || echo 20) ]]; then
        echo "$output" | less -R
    else
        echo "$output"
    fi
}

###
### Custom command runner
###
run_custom_command() {
    echo
    echo -ne "${CYAN}Enter command to run (empty to cancel): ${RESET}"
    read -r cmd
    if [[ -z "$cmd" ]]; then
        echo "Cancelled."
        echo
        return
    fi
    echo
    echo -ne "${YELLOW}Running: ${cmd}${RESET}\n"
    echo "---"
    eval "$cmd" 2>&1 || true
    echo "---"
    echo
}

###
### Find largest files with human-readable sizes
###
find_large_files() {
    find / -xdev -type f -printf '%s\t%p\n' 2>/dev/null | sort -rn | head -15 | while IFS=$'\t' read -r size path; do
        if [[ "$size" -ge 1073741824 ]]; then
            printf '%.2f GB  %s\n' "$(awk "BEGIN {printf \"%.2f\", $size / 1073741824}")" "$path"
        elif [[ "$size" -ge 1048576 ]]; then
            printf '%.2f MB  %s\n' "$(awk "BEGIN {printf \"%.2f\", $size / 1048576}")" "$path"
        elif [[ "$size" -ge 1024 ]]; then
            printf '%.2f KB  %s\n' "$(awk "BEGIN {printf \"%.2f\", $size / 1024}")" "$path"
        else
            printf '%d B  %s\n' "$size" "$path"
        fi
    done || echo 'find not available'
}

###
### Check if any optional dependency is missing for a menu
###
check_deps() {
    local -a missing=()
    for dep in "$@"; do
        if ! cmd_exists "$dep"; then
            missing+=("$dep")
        fi
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        yellowprint "Note: ${missing[*]} not found — some options may be limited."
        echo
    fi
}

###
### Reusable submenu renderer (loop-based, no recursion)
###
# Usage:
#   run_submenu "Title" \
#     "1" "label" "command_or_action" \
#     "2" "label" "command_or_action" \
#     ...
#
# Action strings:
#   A shell command (string) → executed via run_cmd
#   "fn_bye"                 → exit the script
#   "return_to"              → return to caller
#   "run_custom_command"     → prompt user for a command
#
# Navigation items (Go Back / Exit) use keys "0" and "B" (Back).

run_submenu() {
    local title="$1"
    shift

    # Build menu lines into a flat array: key, label, action triples
    local -a items=()
    while [[ $# -gt 0 ]]; do
        items+=("$1" "$2" "$3")
        shift 3
    done

    # Main loop: render menu, read input, dispatch action, repeat
    while true; do
        # Render the menu
        echo
        blueprint "$title"
        echo

        local i=0
        while [[ $i -lt ${#items[@]} ]]; do
            local k="${items[$i]}"
            local l="${items[$((i+1))]}"
            local a="${items[$((i+2))]}"
            i=$((i + 3))

            # Skip navigation stubs (empty label)
            [[ -z "$l" ]] && continue

            if [[ "$l" == *"$(printf '\033')"* ]]; then
                echo -ne "${l})\n"
            else
                echo -ne "$(yellowprint "${k})") ${l}\n"
            fi
        done

        echo -ne "${CYAN}? Help | R Refresh | E Exit${RESET}\n"
        echo -ne "Choose an option: "

        read -r -t 60 ans || {
            echo
            echo "Timed out. Returning to menu."
            return
        }
        case "${ans^^}" in
            E|EXIT)
                fn_bye
                ;;
            R|REFRESH)
                # Loop continues, re-renders the menu
                ;;
            "?"|HELP)
                echo
                echo "  Navigation:"
                echo "    Enter key number to select"
                echo "    R - Refresh current view"
                echo "    ? - This help"
                echo "    E - Exit"
                echo "    Ctrl+C - Return to parent menu"
                echo
                ;;
            *)
                # Try to match a key
                local found=0
                i=0
                while [[ $i -lt ${#items[@]} ]]; do
                    local k="${items[$i]}"
                    local l="${items[$((i+1))]}"
                    local a="${items[$((i+2))]}"
                    i=$((i + 3))

                    [[ -z "$l" ]] && continue

                    if [[ "${ans^^}" == "${k^^}" ]]; then
                        found=1
                        # Execute the action
                        case "$a" in
                            fn_bye)
                                fn_bye
                                ;;
                            return_to)
                                return
                                ;;
                            run_custom_command)
                                run_custom_command
                                ;;
                            *)
                                # Check if it's a known submenu function (no output capture)
                                # vs a shell command (output captured/paginated)
                                if declare -f "$a" >/dev/null 2>&1; then
                                    "$a"
                                else
                                    run_cmd "$a"
                                fi
                                ;;
                        esac
                        break
                    fi
                done

                if [[ $found -eq 0 ]]; then
                    fn_fail
                fi
                ;;
        esac
    done
}

###
### DATETIME MENU
###
datetimemenu() {
    run_submenu "Time/Date" \
        "1" "timedatectl" "timedatectl" \
        "2" "Current date & time" "date '+%Y-%m-%d %H:%M:%S %Z'" \
        "3" "Calendar" "cal" \
        "4" "Epoch / uptime" "uptime" \
        "0" "Exit" "fn_bye" \
        "B" "Go Back" "return_to"
}

###
### ARCH / SYSTEM INFO MENU
###
archsysteminfomenu() {
    check_deps "lspci" "lsusb" "lsblk" "lsb_release"

    run_submenu "Arch/SystemInfo" \
        "1" "Display Arch" "dpkg --print-architecture 2>/dev/null || uname -m" \
        "2" "CPU Info" "cat /proc/cpuinfo" \
        "3" "CPU Summary (model, cores)" "grep -m1 'model name' /proc/cpuinfo; nproc" \
        "4" "PCI Buses" "lspci 2>/dev/null || echo 'lspci not found'" \
        "5" "Block Devices" "lsblk 2>/dev/null || echo 'lsblk not found'" \
        "6" "USB Buses" "lsusb 2>/dev/null || echo 'lsusb not found'" \
        "7" "Memory (free)" "free -g -h -t" \
        "8" "Memory (detailed)" "cat /proc/meminfo" \
        "9" "uname -a" "uname -a" \
        "10" "Linux Distribution" "lsb_release -a 2>/dev/null || cat /etc/os-release" \
        "11" "Kernel version" "uname -r" \
        "12" "OS release codename" ". /etc/os-release 2>/dev/null && printf '%s\n' \"\${VERSION_CODENAME:-No codename in /etc/os-release}\" || echo '/etc/os-release not found'" \
        "0" "Exit" "fn_bye" \
        "B" "Go Back" "return_to"
}

###
### DISK SPACE MENU
###
diskspacemenu() {
    run_submenu "Disk Space" \
        "1" "df -h (excl. tmpfs)" "df -h -x tmpfs" \
        "2" "df -h (all)" "df -h" \
        "3" "Inode usage" "df -i" \
        "4" "Current directory listing" "ls -lh" \
        "5" "Large files in / (top 20)" "find / -xdev -type f -size +100M 2>/dev/null | head -20" \
        "0" "Exit" "fn_bye" \
        "B" "Go Back" "return_to"
}

###
### NETWORK MENU
###
networkmenu() {
    check_deps "ifconfig" "curl" "tailscale"

    run_submenu "Network" \
        "1" "ifconfig / ip addr" "ip addr 2>/dev/null || ifconfig 2>/dev/null || echo 'Neither ifconfig nor ip found'" \
        "2" "Public IP" "curl -s ifconfig.me 2>/dev/null || curl -s icanhazip.com 2>/dev/null || echo 'curl not available'" \
        "3" "Private IP" "hostname -I | awk '{print \$1}'" \
        "4" "Routing table" "ip route 2>/dev/null || route -n 2>/dev/null || echo 'No routing tool found'" \
        "5" "DNS config" "cat /etc/resolv.conf" \
        "6" "Listening ports" "ss -tln 2>/dev/null || netstat -tlnp 2>/dev/null || echo 'ss/netstat not found'" \
        "7" "Active connections" "ss -tn 2>/dev/null || netstat -tnp 2>/dev/null || echo 'ss/netstat not found'" \
        "8" "ARP table" "ip neigh 2>/dev/null || arp -a 2>/dev/null || echo 'No ARP tool found'" \
        "9" "Network interface stats" "cat /proc/net/dev" \
        "10" "Tailscale" "tailscale ip && tailscale status && tailscale netcheck 2>/dev/null || echo 'tailscale not found'" \
        "11" "Sockets by process (root for all)" "ss -tulpn 2>/dev/null || netstat -tulpn 2>/dev/null || lsof -i -P -n 2>/dev/null || echo 'ss/netstat/lsof not found'" \
        "0" "Exit" "fn_bye" \
        "B" "Go Back" "return_to"
}

###
### PROCESS / RESOURCE MONITORING MENU
###
processmenu() {
    check_deps "htop"

    run_submenu "Processes & Resources" \
        "1" "Top 10 CPU consumers" "ps aux --sort=-%cpu 2>/dev/null | head -11" \
        "2" "Top 10 Memory consumers" "ps aux --sort=-%mem 2>/dev/null | head -11" \
        "3" "Running services count" "systemctl list-units --type=service --state=running --no-pager 2>/dev/null | grep running || echo 'systemctl not available'" \
        "4" "Zombie processes" "ps aux | awk '/\[Z\]/ || /Z/ {print}' || echo 'None found'" \
        "5" "System load average" "uptime" \
        "6" "System load (detailed)" "top -bn1 | head -5" \
        "0" "Exit" "fn_bye" \
        "B" "Go Back" "return_to"
}

###
### USER / SECURITY MENU
###
usersecuritymenu() {
    check_deps "iptables" "ufw" "nmap"

    run_submenu "Users & Security" \
        "1" "Logged-in users" "who" \
        "2" "User activity detail" "w" \
        "3" "Recent logins" "last -n 20" \
        "4" "Failed SSH attempts (1h)" "journalctl -u ssh --since '1 hour ago' --no-pager 2>/dev/null | grep -i 'failed password' | tail -20 || echo 'journalctl/ssh not available'" \
        "5" "Sudoers config" "ls -la /etc/sudoers.d/ 2>/dev/null || cat /etc/sudoers 2>/dev/null || echo 'No sudoers found'" \
        "6" "SSH authorized keys summary" "find /home -maxdepth 3 -name authorized_keys -exec echo {} \; -exec wc -l {} \; 2>/dev/null || echo 'No SSH keys found'" \
        "7" "Firewall rules (iptables)" "iptables -L -n -v 2>/dev/null || echo 'iptables not available'" \
        "8" "Firewall status (ufw)" "ufw status 2>/dev/null || echo 'ufw not available'" \
        "9" "Listening ports" "ss -tln 2>/dev/null || netstat -tlnp 2>/dev/null || echo 'ss/netstat not found'" \
        "0" "Exit" "fn_bye" \
        "B" "Go Back" "return_to"
}

###
### KERNEL / SYSTEM MENU
###
kernelmenu() {
    run_submenu "Kernel & System" \
        "1" "Kernel version" "uname -r" \
        "2" "Kernel version (full)" "uname -a" \
        "3" "System uptime" "uptime" \
        "4" "Kernel parameters" "sysctl -a 2>/dev/null | less -R || echo 'sysctl not available'" \
        "5" "Mounted filesystems" "mount" \
        "6" "fstab contents" "cat /etc/fstab 2>/dev/null || echo '/etc/fstab not found'" \
        "7" "Recent dmesg messages" "dmesg -T 2>/dev/null | tail -30 || echo 'dmesg not available'" \
        "8" "Recent systemd errors" "journalctl -p err --no-pager -n 20 2>/dev/null || echo 'journalctl not available'" \
        "9" "Kernel module list" "lsmod 2>/dev/null || echo 'lsmod not available'" \
        "10" "Kernel boot cmdline" "cat /proc/cmdline 2>/dev/null || echo '/proc/cmdline not available'" \
        "0" "Exit" "fn_bye" \
        "B" "Go Back" "return_to"
}

###
### STORAGE / DISK EXTENDED MENU
###
storagemenu() {
    check_deps "smartctl"

    run_submenu "Storage & Filesystem" \
        "1" "Disk SMART status (sda)" "smartctl -a /dev/sda 2>/dev/null || smartctl -a /dev/nvme0n1 2>/dev/null || echo 'smartctl not available or no disk found'" \
        "2" "Inode usage" "df -i" \
        "3" "Largest dirs in / (top 15)" "du -sh /* 2>/dev/null | sort -rh | head -15" \
        "4" "Largest files in / (top 15)" "find_large_files" \
        "5" "Mount points with type" "findmnt 2>/dev/null || mount | awk '{print \$3, \$5}' || echo 'findmnt/mount not found'" \
        "6" "LVM volumes" "vgs 2>/dev/null && lvs 2>/dev/null && pvs 2>/dev/null || echo 'LVM tools not available'" \
        "7" "RAID status" "cat /proc/mdstat 2>/dev/null || echo 'No RAID detected'" \
        "8" "Disk I/O stats" "iostat -x 1 1 2>/dev/null || cat /proc/diskstats || echo 'iostat not available'" \
        "0" "Exit" "fn_bye" \
        "B" "Go Back" "return_to"
}

###
### TIME / SCHEDULING MENU
###
schedulingmenu() {
    check_deps "systemctl"

    run_submenu "Time & Scheduling" \
        "1" "User crontab" "crontab -l 2>/dev/null || echo 'No user crontab'" \
        "2" "System cron directories" "ls -la /etc/cron.d/ 2>/dev/null; ls -la /etc/cron.daily/ 2>/dev/null; ls -la /etc/cron.hourly/ 2>/dev/null || echo 'Cron dirs not found'" \
        "3" "Anacron jobs" "ls -la /etc/anacrontab 2>/dev/null || echo 'Anacron not installed'" \
        "4" "Systemd timers" "systemctl list-timers --all --no-pager 2>/dev/null || echo 'systemctl not available'" \
        "0" "Exit" "fn_bye" \
        "B" "Go Back" "return_to"
}

###
### PACKAGE / SOFTWARE MENU
###
packagemenu() {
    check_deps "apt" "dnf" "yum" "docker"

    run_submenu "Packages & Software" \
        "1" "Installed packages (count)" "(dpkg -l 2>/dev/null || rpm -qa 2>/dev/null || echo 'No package manager found') | wc -l" \
        "2" "Recently installed (dpkg)" "dpkg --get-selections 2>/dev/null | tail -20 || echo 'dpkg not available'" \
        "3" "Updates available (apt)" "apt list --upgradable 2>/dev/null | grep -v '^Listing' || echo 'apt not available or no updates'" \
        "4" "Updates available (dnf)" "dnf check-update 2>/dev/null || echo 'dnf not available'" \
        "5" "Docker containers" "docker ps -a 2>/dev/null || echo 'Docker not installed'" \
        "6" "Docker images" "docker images 2>/dev/null || echo 'Docker not installed'" \
        "7" "Auto-start services" "systemctl list-unit-files --type=service --state=enabled --no-pager 2>/dev/null | head -30 || echo 'systemctl not available'" \
        "0" "Exit" "fn_bye" \
        "B" "Go Back" "return_to"
}

###
### DEVELOPMENT / SWE MENU
###
devmenu() {
    check_deps "git" "node" "python3" "go"

    run_submenu "Development & SWE" \
        "1" "Git repos in home" "find ~ -maxdepth 3 -name .git -type d 2>/dev/null | head -20 || echo 'No git repos found'" \
        "2" "Node version" "node --version 2>/dev/null || echo 'Node not installed'" \
        "3" "npm global packages" "npm list -g --depth=0 2>/dev/null || echo 'npm not available'" \
        "4" "Python version" "python3 --version 2>/dev/null || echo 'Python3 not installed'" \
        "5" "pip packages" "pip3 list 2>/dev/null | head -30 || echo 'pip not available'" \
        "6" "Go version" "go version 2>/dev/null || echo 'Go not installed'" \
        "7" "Environment variables" "env | sort" \
        "8" "Active SSH sessions" "ps aux | grep ssh | grep -v grep || echo 'No active SSH sessions'" \
        "9" "SSH known hosts" "wc -l ~/.ssh/known_hosts 2>/dev/null || echo 'No known_hosts'" \
        "0" "Exit" "fn_bye" \
        "B" "Go Back" "return_to"
}

###
### PERFORMANCE & TROUBLESHOOTING MENU
###
performancemenu() {
    check_deps "vmstat" "mpstat" "pidstat" "systemd-analyze" "sensors" "pstree" "ss" "dmesg"

    run_submenu "Performance & Troubleshooting" \
        "1" "vmstat snapshot (3s)" "vmstat 1 3 2>/dev/null || echo 'vmstat not available'" \
        "2" "Per-CPU stats (mpstat)" "mpstat -P ALL 1 1 2>/dev/null || echo 'mpstat not available'" \
        "3" "Context switches & page faults" "vmstat -s 2>/dev/null || echo 'vmstat not available'" \
        "4" "Connection states summary" "ss -s 2>/dev/null || echo 'ss not available'" \
        "5" "Failed systemd units" "systemctl --failed --no-pager 2>/dev/null || echo 'systemctl not available'" \
        "6" "Boot time analysis (top 20)" "systemd-analyze blame 2>/dev/null | head -20 || echo 'systemd-analyze not available'" \
        "7" "Boot critical chain" "systemd-analyze critical-chain 2>/dev/null || echo 'systemd-analyze not available'" \
        "8" "OOM killer history" "dmesg -T 2>/dev/null | grep -i oom | tail -10 || echo 'dmesg not available'" \
        "9" "Process tree" "pstree -p 2>/dev/null || ps axjf 2>/dev/null || echo 'pstree/ps not available'" \
        "10" "Top 10 open file descriptors" "ls /proc/*/fd 2>/dev/null | cut -d/ -f3 | sort | uniq -c | sort -rn | head -10 || echo '/proc not available'" \
        "11" "CPU temps" "sensors 2>/dev/null || cat /sys/class/thermal/thermal_zone*/temp 2>/dev/null || echo 'No thermal data available'" \
        "12" "CPU frequency/governor" "cat /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor 2>/dev/null || echo 'No CPUfreq data available'" \
        "13" "Interrupt stats (top 20)" "cat /proc/interrupts 2>/dev/null | head -20 || echo '/proc/interrupts not available'" \
        "0" "Exit" "fn_bye" \
        "B" "Go Back" "return_to"
}

###
### MAIN MENU
###
mainmenu() {
    echo
    echo " █████╗ ██████╗ ███╗   ███╗██╗███╗   ██╗    ███╗   ███╗███████╗███╗   ██╗██╗   ██╗"
    echo "██╔══██╗██╔══██╗████╗ ████║██║████╗  ██║    ████╗ ████║██╔════╝████╗  ██║██║   ██║"
    echo "███████║██║  ██║██╔████╔██║██║██╔██╗ ██║    ██╔████╔██║█████╗  ██╔██╗ ██║██║   ██║"
    echo "██╔══██║██║  ██║██║╚██╔╝██║██║██║╚██╗██║    ██║╚██╔╝██║██╔══╝  ██║╚██╗██║██║   ██║"
    echo "██║  ██║██████╔╝██║ ╚═╝ ██║██║██║ ╚████║    ██║ ╚═╝ ██║███████╗██║ ╚████║╚██████╔╝"
    echo "╚═╝  ╚═╝╚═════╝ ╚═╝     ╚═╝╚═╝╚═╝  ╚═══╝    ╚═╝     ╚═╝╚══════╝╚═╝  ╚═══╝ ╚═════╝ "
    echo

    warn_not_root

    run_submenu "Main Menu" \
        "1" "Date/Time" "datetimemenu" \
        "2" "Arch/SystemInfo" "archsysteminfomenu" \
        "3" "Disk Space" "diskspacemenu" \
        "4" "Network" "networkmenu" \
        "5" "Processes & Resources" "processmenu" \
        "6" "Users & Security" "usersecuritymenu" \
        "7" "Kernel & System" "kernelmenu" \
        "8" "Storage & Filesystem" "storagemenu" \
        "9" "Time & Scheduling" "schedulingmenu" \
        "A" "Packages & Software" "packagemenu" \
        "B" "Development & SWE" "devmenu" \
        "C" "Performance & Troubleshooting" "performancemenu" \
        "D" "Run Custom Command" "run_custom_command" \
        "0" "Exit" "fn_bye"
}

###
### SIGINT handler — return to parent menu instead of exiting
###
trap 'echo; echo "Interrupted. Returning to menu."; return' INT

###
### Start
###
mainmenu
