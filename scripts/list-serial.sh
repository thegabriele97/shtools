#!/bin/bash

# @description List available serial ports with device, name and info to tell them apart
# @usage list-serial [-a]
# @example list-serial
# @deps udevadm (optional), lsof (optional)

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

SHOW_ALL=0
[[ "$1" == "-a" || "$1" == "--all" ]] && SHOW_ALL=1

# ── helpers ────────────────────────────────────────────────────────────────────

# read a sysfs attribute, walking up parent dirs until found (for USB attrs)
sysfs_walk() {
  local dir="$1" attr="$2"
  while [[ "$dir" != "/" && -n "$dir" ]]; do
    if [[ -r "$dir/$attr" ]]; then
      cat "$dir/$attr" 2>/dev/null
      return 0
    fi
    dir=$(dirname "$dir")
  done
  return 1
}

# by-id friendly name for a /dev node
byid_for() {
  local dev="$1" link
  [[ -d /dev/serial/by-id ]] || return 1
  for link in /dev/serial/by-id/*; do
    [[ -e "$link" ]] || continue
    if [[ "$(readlink -f "$link")" == "$dev" ]]; then
      basename "$link"
      return 0
    fi
  done
  return 1
}

# is the port currently opened by a process?
port_user() {
  command -v lsof &>/dev/null || return 1
  lsof -t "$1" 2>/dev/null | head -1
}

# ── collect candidate ports ─────────────────────────────────────────────────────

PORTS=()
for name in /sys/class/tty/*; do
  tty=$(basename "$name")
  [[ -e "$name/device" ]] || continue

  case "$tty" in
    ttyUSB*|ttyACM*|ttyAMA*|ttyGS*) PORTS+=("/dev/$tty") ;;
    ttyS*)
      # serial8250 exposes many phantom ttyS*; keep only real UARTs
      # (a real one has a nonzero io/mem base in the driver's type)
      if [[ "$SHOW_ALL" == "1" ]]; then
        PORTS+=("/dev/$tty")
      elif [[ -r "$name/device/resources" || -r "/proc/tty/driver/serial" ]]; then
        line=$(grep -E "^${tty#ttyS}:" /proc/tty/driver/serial 2>/dev/null)
        [[ -n "$line" && "$line" != *"uart:unknown"* ]] && PORTS+=("/dev/$tty")
      fi
      ;;
  esac
done

# ── output ───────────────────────────────────────────────────────────────────

echo ""
echo -e "  ${BOLD}🔌 list-serial${NC}"
echo ""

if [[ ${#PORTS[@]} -eq 0 ]]; then
  echo -e "  ${YELLOW}⚠ no serial ports found${NC}"
  [[ "$SHOW_ALL" == "0" ]] && echo -e "  ${DIM}onboard ttyS* are hidden unless they look real — use -a to show them all${NC}"
  echo ""
  exit 0
fi

IFS=$'\n' PORTS=($(sort <<<"${PORTS[*]}")); unset IFS

for dev in "${PORTS[@]}"; do
  tty=$(basename "$dev")
  syspath=$(readlink -f "/sys/class/tty/$tty/device")

  vendor=""; model=""; serial=""; vid=""; pid=""; driver=""
  if command -v udevadm &>/dev/null; then
    while IFS='=' read -r k v; do
      case "$k" in
        ID_VENDOR_FROM_DATABASE) vendor="$v" ;;
        ID_VENDOR) [[ -z "$vendor" ]] && vendor="$v" ;;
        ID_MODEL_FROM_DATABASE) model="$v" ;;
        ID_MODEL) [[ -z "$model" ]] && model="$v" ;;
        ID_SERIAL_SHORT) serial="$v" ;;
        ID_VENDOR_ID) vid="$v" ;;
        ID_MODEL_ID) pid="$v" ;;
        ID_USB_DRIVER) driver="$v" ;;
      esac
    done < <(udevadm info -q property "$dev" 2>/dev/null)
  fi

  # sysfs fallbacks
  [[ -z "$vendor" ]] && vendor=$(sysfs_walk "$syspath" manufacturer)
  [[ -z "$model"  ]] && model=$(sysfs_walk "$syspath" product)
  [[ -z "$serial" ]] && serial=$(sysfs_walk "$syspath" serial)
  [[ -z "$vid"    ]] && vid=$(sysfs_walk "$syspath" idVendor)
  [[ -z "$pid"    ]] && pid=$(sysfs_walk "$syspath" idProduct)
  [[ -z "$driver" && -e "/sys/class/tty/$tty/device/driver" ]] && driver=$(basename "$(readlink -f "/sys/class/tty/$tty/device/driver")")

  byid=$(byid_for "$dev")
  vidpid=""; [[ -n "$vid" && -n "$pid" ]] && vidpid="${vid}:${pid}"

  desc="$vendor $model"; desc="${desc# }"; desc="${desc% }"
  [[ -z "$desc" ]] && desc="(unknown device)"

  echo -e "  ${GREEN}●${NC} ${BOLD}$dev${NC}  ${DIM}$desc${NC}"
  [[ -n "$byid" ]]   && echo -e "     ${DIM}by-id    ${NC}$byid"
  [[ -n "$serial" ]] && echo -e "     ${DIM}serial   ${NC}$serial"
  [[ -n "$vidpid" ]] && echo -e "     ${DIM}usb id   ${NC}$vidpid"
  [[ -n "$driver" ]] && echo -e "     ${DIM}driver   ${NC}$driver"

  user=$(port_user "$dev")
  if [[ -n "$user" ]]; then
    pname=$(ps -o comm= -p "$user" 2>/dev/null)
    echo -e "     ${DIM}status   ${NC}${YELLOW}in use${NC} ${DIM}(pid $user${pname:+ · $pname})${NC}"
  else
    echo -e "     ${DIM}status   ${NC}${GREEN}free${NC}"
  fi
  echo ""
done

echo -e "  ${DIM}${#PORTS[@]} port(s) · tip: use the by-id path in scripts, it stays stable across reboots${NC}"
echo ""
