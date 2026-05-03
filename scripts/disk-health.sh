#!/bin/bash

# @description Inspect SMART health data for one or more disks
# @usage disk-health <disk> [disk2 ...]
# @example sudo disk-health /dev/sda /dev/sdb /dev/nvme0n1
# @deps smartctl

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# ── check deps ────────────────────────────────────────────────────────────────

if ! command -v smartctl &>/dev/null; then
    echo -e "\n ${RED}✗ smartctl not found${NC}\n"
    echo -e " ${CYAN}Ubuntu/Debian${NC}  sudo apt install smartmontools"
    echo -e " ${CYAN}Fedora${NC}         sudo dnf install smartmontools"
    echo -e " ${CYAN}Arch${NC}           sudo pacman -S smartmontools\n"
    exit 1
fi

if [[ $EUID -ne 0 ]]; then
    echo -e "\n ${YELLOW}⚠ not running as root — some data may be unavailable${NC}\n"
fi

# ── args ──────────────────────────────────────────────────────────────────────

if [[ $# -eq 0 ]]; then
    echo -e "\n ${BOLD}Usage:${NC} sudo disk-health <disk> [disk2 ...]\n"
    echo -e " ${DIM}disks on this system:${NC}\n"
    lsblk -d -o NAME,SIZE,TYPE,MODEL 2>/dev/null | grep -v loop | while IFS= read -r line; do
        echo -e "   ${DIM}$line${NC}"
    done
    echo ""
    exit 0
fi

# ── helpers ───────────────────────────────────────────────────────────────────

# pipeline-safe grep — use only in variable assignments, never in `if` conditions
pgrep() { grep "$@" || true; }

# get SMART attribute raw value by numeric ID (SATA/SAS, column 10)
get_attr() {
    local data="$1" id="$2"
    echo "$data" | awk -v id="$id" '$1==id {print $10}' | head -1
}

# ── sata analysis ─────────────────────────────────────────────────────────────

analyze_sata() {
    local dev="$1"
    local smart_all smart_info
    smart_all=$(smartctl -a  "$dev" 2>&1) || true
    smart_info=$(smartctl -i "$dev" 2>&1) || true

    # general info
    local model family serial rpm hours temp
    model=$(echo  "$smart_info" | pgrep -i "Device Model\|Model Number" | head -1 | cut -d: -f2- | xargs)
    family=$(echo "$smart_info" | pgrep -i "Model Family"               | head -1 | cut -d: -f2- | xargs)
    serial=$(echo "$smart_info" | pgrep -i "Serial Number"              | head -1 | cut -d: -f2- | xargs)
    rpm=$(echo    "$smart_info" | pgrep -i "Rotation Rate"              | head -1 | cut -d: -f2- | xargs)
    hours=$(get_attr "$smart_all" 9)
    temp=$(get_attr  "$smart_all" 194)
    [[ -z "$temp" ]] && temp=$(get_attr "$smart_all" 190)

    echo ""
    echo -e " ${DIM}model:    ${model:-N/A}${NC}"
    [[ -n "$family" ]] && echo -e " ${DIM}family:   $family${NC}"
    echo -e " ${DIM}serial:   ${serial:-N/A}${NC}"
    echo -e " ${DIM}rotation: ${rpm:-N/A}${NC}"
    [[ -n "$hours" ]] && echo -e " ${DIM}power-on: ${hours}h${NC}"

    if [[ -n "$temp" ]]; then
        if   (( temp >= 60 )); then echo -e " ${RED}✗ temperature: ${temp}°C — critical${NC}"
        elif (( temp >= 50 )); then echo -e " ${YELLOW}⚠ temperature: ${temp}°C — high${NC}"
        else                        echo -e " ${GREEN}✓${NC} ${DIM}temperature: ${temp}°C${NC}"
        fi
    fi

    # overall health
    echo ""
    local overall
    overall=$(echo "$smart_all" | pgrep -i "SMART overall-health\|SMART Health Status" | head -1 | cut -d: -f2- | xargs)
    if echo "$overall" | grep -qi "PASSED\|OK"; then
        echo -e " ${GREEN}✓ SMART overall: ${overall}${NC}"
    else
        echo -e " ${RED}✗ SMART overall: ${overall:-UNKNOWN}${NC}"
    fi

    # critical attributes
    echo ""
    echo -e " ${BOLD}A — critical attributes${NC}"
    echo ""

    local -A CHECKS=(
        ["1"]="1:10:Raw Read Error Rate"
        ["5"]="1:50:Reallocated Sectors Count"
        ["10"]="1:5:Spin Retry Count"
        ["187"]="1:50:Reported Uncorrect"
        ["188"]="1:50:Command Timeout"
        ["196"]="1:10:Reallocated Event Count"
        ["197"]="1:10:Current Pending Sector"
        ["198"]="1:5:Uncorrectable Sector Count"
        ["199"]="1:20:UDMA CRC Error Count"
    )

    local found_any=0
    for id in 1 5 10 187 188 196 197 198 199; do
        local raw
        raw=$(get_attr "$smart_all" "$id")
        [[ -z "$raw" ]] && continue
        found_any=1

        local entry="${CHECKS[$id]}"
        local warn_thr fail_thr desc
        IFS=: read -r warn_thr fail_thr desc <<< "$entry"
        raw=$(echo "$raw" | tr -d ',')

        local label
        label=$(printf "%-32s" "$desc (ID $id)")

        if   (( raw >= fail_thr && fail_thr > 0 )); then
            echo -e " ${RED}✗ ${label}  raw=$raw${NC}"
        elif (( raw >= warn_thr && warn_thr > 0 )); then
            echo -e " ${YELLOW}⚠ ${label}  raw=$raw${NC}"
        else
            echo -e " ${GREEN}✓${NC} ${DIM}${label}  raw=$raw${NC}"
        fi
    done

    [[ $found_any -eq 0 ]] && echo -e " ${DIM}no attributes found (disk may not support them)${NC}"

    # self-test log
    local last_test
    last_test=$(echo "$smart_all" | pgrep -A5 "SMART Self-test log" | pgrep -E "Completed|Failed|Interrupted" | head -1)
    if [[ -n "$last_test" ]]; then
        echo ""
        echo -e " ${BOLD}B — last self-test${NC}"
        echo ""
        if echo "$last_test" | grep -qi "Failed"; then
            echo -e " ${RED}✗ $last_test${NC}"
        else
            echo -e " ${GREEN}✓${NC} ${DIM}$last_test${NC}"
        fi
    fi

    # error log
    local err_count
    err_count=$(echo "$smart_all" | pgrep -i "Error Count\|error count" | head -1 | pgrep -oE '[0-9]+' | tail -1)
    if [[ -n "$err_count" && "$err_count" -gt 0 ]]; then
        echo -e " ${YELLOW}⚠ error log: ${err_count} error(s) recorded${NC}"
    fi
}

# ── nvme analysis ─────────────────────────────────────────────────────────────

analyze_nvme() {
    local dev="$1"
    local smart_all
    smart_all=$(smartctl -a "$dev" 2>&1) || true

    # helper for NVMe fields (assignment pipeline — uses pgrep)
    get_nvme() { echo "$smart_all" | pgrep -i "$1" | head -1 | cut -d: -f2- | xargs; }

    # general info
    local model serial firmware size
    model=$(get_nvme "Model Number")
    serial=$(get_nvme "Serial Number")
    firmware=$(get_nvme "Firmware Version")
    size=$(get_nvme "Total NVM")

    echo ""
    echo -e " ${DIM}model:    ${model:-N/A}${NC}"
    echo -e " ${DIM}serial:   ${serial:-N/A}${NC}"
    echo -e " ${DIM}firmware: ${firmware:-N/A}${NC}"
    [[ -n "$size" ]] && echo -e " ${DIM}capacity: $size${NC}"

    # overall health
    echo ""
    local overall
    overall=$(echo "$smart_all" | pgrep -i "SMART overall-health\|SMART Health Status" | head -1 | cut -d: -f2- | xargs)
    if echo "$overall" | grep -qi "PASSED\|OK"; then
        echo -e " ${GREEN}✓ SMART overall: ${overall}${NC}"
    else
        echo -e " ${RED}✗ SMART overall: ${overall:-UNKNOWN}${NC}"
    fi

    # attributes
    echo ""
    echo -e " ${BOLD}A — NVMe attributes${NC}"
    echo ""

    # critical warning byte — 0x00 = no issues
    local crit_warn
    crit_warn=$(get_nvme "Critical Warning")
    if [[ -n "$crit_warn" ]]; then
        if echo "$crit_warn" | grep -qiE "0x00|^0$"; then
            echo -e " ${GREEN}✓${NC} ${DIM}critical warning:  $crit_warn${NC}"
        else
            echo -e " ${RED}✗ critical warning:  $crit_warn${NC}"
        fi
    fi

    # temperature
    local temp_val
    temp_val=$(echo "$smart_all" | pgrep -i "Temperature:" | head -1 | pgrep -oE '[0-9]+' | head -1)
    if [[ -n "$temp_val" ]]; then
        if   (( temp_val >= 70 )); then echo -e " ${RED}✗ temperature:       ${temp_val}°C — critical${NC}"
        elif (( temp_val >= 60 )); then echo -e " ${YELLOW}⚠ temperature:       ${temp_val}°C — high${NC}"
        else                             echo -e " ${GREEN}✓${NC} ${DIM}temperature:       ${temp_val}°C${NC}"
        fi
    fi

    # available spare
    local spare
    spare=$(get_nvme "Available Spare:" | tr -d '%')
    if [[ -n "$spare" ]]; then
        if   (( spare <= 10 )); then echo -e " ${RED}✗ available spare:   ${spare}%${NC}"
        elif (( spare <= 25 )); then echo -e " ${YELLOW}⚠ available spare:   ${spare}%${NC}"
        else                         echo -e " ${GREEN}✓${NC} ${DIM}available spare:   ${spare}%${NC}"
        fi
    fi

    # percentage used (wear)
    local pct_used
    pct_used=$(get_nvme "Percentage Used:" | tr -d '%')
    if [[ -n "$pct_used" ]]; then
        if   (( pct_used >= 90 )); then echo -e " ${RED}✗ percentage used:   ${pct_used}% — end of life approaching${NC}"
        elif (( pct_used >= 70 )); then echo -e " ${YELLOW}⚠ percentage used:   ${pct_used}%${NC}"
        else                             echo -e " ${GREEN}✓${NC} ${DIM}percentage used:   ${pct_used}%${NC}"
        fi
    fi

    # media errors — any non-zero is bad
    local media_errs
    media_errs=$(get_nvme "Media and Data Integrity Errors")
    if [[ -n "$media_errs" ]]; then
        if (( media_errs > 0 )); then
            echo -e " ${RED}✗ media errors:      $media_errs${NC}"
        else
            echo -e " ${GREEN}✓${NC} ${DIM}media errors:      $media_errs${NC}"
        fi
    fi

    # error log entries
    local err_log
    err_log=$(get_nvme "Error Information Log Entries")
    if [[ -n "$err_log" ]]; then
        if (( err_log > 0 )); then
            echo -e " ${YELLOW}⚠ error log entries: $err_log${NC}"
        else
            echo -e " ${GREEN}✓${NC} ${DIM}error log entries: $err_log${NC}"
        fi
    fi

    # informational
    local poh written read_val
    poh=$(get_nvme "Power On Hours")
    written=$(get_nvme "Data Units Written")
    read_val=$(get_nvme "Data Units Read")
    echo ""
    [[ -n "$poh"      ]] && echo -e " ${DIM}power-on hours: ${poh}h${NC}"
    [[ -n "$written"  ]] && echo -e " ${DIM}data written:   $written${NC}"
    [[ -n "$read_val" ]] && echo -e " ${DIM}data read:      $read_val${NC}"
}

# ── per-disk entry point ──────────────────────────────────────────────────────

analyze_disk() {
    local dev="$1"

    echo ""
    echo -e " $(printf '─%.0s' {1..60})"
    echo ""

    if [[ ! -e "$dev" ]]; then
        echo -e " ${RED}✗ $dev — device not found${NC}"
        return
    fi

    # detect type: NVMe by device name or transport protocol field
    # plain grep in if condition is correct here — non-zero = not NVMe, not an error
    local smart_info
    smart_info=$(smartctl -i "$dev" 2>&1) || true

    if echo "$dev" | grep -qi "nvme" || echo "$smart_info" | grep -qi "Transport Protocol.*NVM"; then
        echo -e " ${BOLD}$dev${NC}  ${DIM}NVMe${NC}"
        analyze_nvme "$dev"
    else
        echo -e " ${BOLD}$dev${NC}  ${DIM}SATA/SAS${NC}"
        analyze_sata "$dev"
    fi
}

# ── main ──────────────────────────────────────────────────────────────────────

echo ""
echo -e " ${BOLD}✦ disk-health${NC}"
echo -e " ${DIM}host: $(hostname)   date: $(date '+%Y-%m-%d %H:%M:%S')${NC}"

for disk in "$@"; do
    analyze_disk "$disk"
done

echo ""
echo -e " $(printf '─%.0s' {1..60})"
echo ""