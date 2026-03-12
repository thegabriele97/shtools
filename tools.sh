#!/bin/bash

BASE_URL="https://raw.githubusercontent.com/thegabriele97/shtools/main/scripts"

RED='\033[0;31m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# ── available scripts ──────────────────────────────────────────────────────────
# format: "filename.sh|command-name"
SCRIPTS=(
  "compress-video.sh|compress-video"
  "compress-images.sh|compress-images"
  "organize-files.sh|organize-files"
  "find-hardlinks.sh|find-hardlinks"
)

# ── helpers ────────────────────────────────────────────────────────────────────

get_meta() {
  local file="$1" tag="$2"
  if [[ -f "./scripts/$file" ]]; then
    grep "^# @${tag}" "./scripts/$file" | sed "s/^# @${tag} //"
  else
    curl -sL "$BASE_URL/$file" 2>/dev/null | grep "^# @${tag}" | sed "s/^# @${tag} //"
  fi
}

run_script() {
  local file="$1" cmd="$2"
  shift 2
  local display="tools $cmd $*"
  if [[ -f "./scripts/$file" ]]; then
    echo -e "\n  ${DIM}↳ ${CYAN}$display${NC}  ${DIM}(local)${NC}\n"
    bash "./scripts/$file" "$@"
  else
    echo -e "\n  ${DIM}↳ ${CYAN}$display${NC}  ${DIM}(remote)${NC}\n"
    bash <(curl -sL "$BASE_URL/$file") "$@"
  fi
}

# ── preview mode (called internally by fzf) ───────────────────────────────────

if [[ "$1" == "--preview" ]]; then
  NAME=$(echo "$2" | awk '{print $1}')
  FILE="${NAME}.sh"
  desc=$(get_meta "$FILE" "description")
  usage=$(get_meta "$FILE" "usage")
  example=$(get_meta "$FILE" "example")
  deps=$(get_meta "$FILE" "deps")
  presets=$(get_meta "$FILE" "preset")
  echo ""
  echo "  📄 $NAME"
  echo "  ──────────────────────────────"
  echo ""
  [[ -n "$desc" ]]    && echo "  $desc"        && echo ""
  [[ -n "$usage" ]]   && echo "  USAGE"        && echo "  tools $usage"   && echo ""
  [[ -n "$example" ]] && echo "  EXAMPLE"      && echo "  tools $example" && echo ""
  [[ -n "$deps" ]]    && echo "  DEPENDENCIES" && echo "  $deps"          && echo ""
  if [[ -n "$presets" ]]; then
    echo "  PRESETS"
    echo "$presets" | while IFS= read -r line; do echo "  $line"; done
    echo ""
  fi
  exit 0
fi

# ── check fzf ─────────────────────────────────────────────────────────────────

if ! command -v fzf &>/dev/null; then
  echo -e "\n  ${RED}${BOLD}✗ fzf not found${NC}\n"
  echo -e "  ${BOLD}Install it with:${NC}\n"
  echo -e "  ${CYAN}macOS${NC}           brew install fzf"
  echo -e "  ${CYAN}Ubuntu/Debian${NC}   sudo apt install fzf"
  echo -e "  ${CYAN}Arch${NC}            sudo pacman -S fzf"
  echo -e "  ${CYAN}Fedora${NC}          sudo dnf install fzf\n"
  exit 1
fi

# ── direct mode: tools compress-video input.mp4 ───────────────────────────────

if [[ -n "$1" ]]; then
  CMD="$1"; shift
  for entry in "${SCRIPTS[@]}"; do
    if [[ "${entry#*|}" == "$CMD" ]]; then
      run_script "${entry%%|*}" "$CMD" "$@"
      exit $?
    fi
  done
  echo -e "\n  ${RED}Command not found:${NC} $CMD"
  echo -e "  Run ${CYAN}tools${NC} with no arguments to see the list\n"
  exit 1
fi

# ── TUI ───────────────────────────────────────────────────────────────────────

build_list() {
  for entry in "${SCRIPTS[@]}"; do
    local file="${entry%%|*}" name="${entry#*|}"
    local desc=$(get_meta "$file" "description")
    printf "%-22s  %s\n" "$name" "${desc:-(no description)}"
  done
}

echo -e "\n  ${BOLD}🛠  tools${NC}  ${DIM}— your scripts, always at hand${NC}\n"

SELECTED=$(build_list | fzf \
  --ansi \
  --no-sort \
  --prompt="  ❯ " \
  --pointer="▶" \
  --height=80% \
  --layout=reverse \
  --border=rounded \
  --preview="bash \"$0\" --preview {}" \
  --preview-window=right:45%:wrap \
  --header=$'  arrows to navigate · enter to run · esc to quit\n' \
  | awk '{print $1}')

[[ -z "$SELECTED" ]] && exit 0

# find the matching file
MATCH_FILE=""
for entry in "${SCRIPTS[@]}"; do
  [[ "${entry#*|}" == "$SELECTED" ]] && MATCH_FILE="${entry%%|*}" && break
done

# prompt arguments one by one reading @usage
USAGE=$(get_meta "$MATCH_FILE" "usage")
EXAMPLE=$(get_meta "$MATCH_FILE" "example")
ARGS=()

if [[ -n "$USAGE" ]]; then
  ARGS_RAW=$(echo "$USAGE" | sed 's/^[^ ]* //')
  while [[ -n "$ARGS_RAW" ]]; do
    if [[ "$ARGS_RAW" =~ ^(\<[^\>]+\>)(.*)$ ]]; then
      ARGS+=("${BASH_REMATCH[1]}"); ARGS_RAW="${BASH_REMATCH[2]# }"
    elif [[ "$ARGS_RAW" =~ ^(\[[^\]]+\])(.*)$ ]]; then
      ARGS+=("${BASH_REMATCH[1]}"); ARGS_RAW="${BASH_REMATCH[2]# }"
    else
      break
    fi
  done
fi

PARAMS=()
if [[ ${#ARGS[@]} -gt 0 ]]; then
  echo -e "\n  ${BOLD}$SELECTED${NC}"
  [[ -n "$EXAMPLE" ]] && echo -e "  ${DIM}example: tools $EXAMPLE${NC}"
  echo ""
  for arg in "${ARGS[@]}"; do
    if [[ "$arg" == \[* ]]; then
      label="${arg//[\[\]]/}"
      echo -ne "  ${DIM}$arg${NC}  ${CYAN}$label${NC} (enter to skip): "
    else
      label="${arg//[<>]/}"
      echo -ne "  $arg  ${CYAN}$label${NC}: "
    fi
    read -e -r val
    [[ -n "$val" ]] && PARAMS+=("$val")
  done
  echo ""
fi

run_script "$MATCH_FILE" "$SELECTED" "${PARAMS[@]}"