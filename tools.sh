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
  "copy-exif.sh|copy-exif"
  "nextcloud-upload.sh|nextcloud-upload"
  "compress-video-sample-compare.sh|compress-video-sample-compare"
  "concat-clips.sh|concat-clips"
  "disk-health.sh|disk-health"
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

# ── collect args via usage string (shared by both TUI paths) ──────────────────

collect_args() {
  local match_file="$1" selected="$2"
  local usage example args_raw
  USAGE=$(get_meta "$match_file" "usage")
  EXAMPLE=$(get_meta "$match_file" "example")
  ARGS=()

  if [[ -n "$USAGE" ]]; then
    args_raw=$(echo "$USAGE" | sed 's/^[^ ]* //')
    while [[ -n "$args_raw" ]]; do
      if [[ "$args_raw" =~ ^(\<[^\>]+\>)(.*)$ ]]; then
        ARGS+=("${BASH_REMATCH[1]}"); args_raw="${BASH_REMATCH[2]# }"
      elif [[ "$args_raw" =~ ^(\[[^\]]+\])(.*)$ ]]; then
        ARGS+=("${BASH_REMATCH[1]}"); args_raw="${BASH_REMATCH[2]# }"
      else
        break
      fi
    done
  fi

  PARAMS=()
  if [[ ${#ARGS[@]} -gt 0 ]]; then
    echo -e "\n  ${BOLD}$selected${NC}"
    [[ -n "$EXAMPLE" ]] && echo -e "  ${DIM}example: tools $EXAMPLE${NC}"
    echo ""
    for arg in "${ARGS[@]}"; do
      if [[ "$arg" == \[* ]]; then
        label="${arg//[\[\]]/}"
        prompt=$(printf "  \033[2m$arg\033[0m  \001\033[0;36m\002$label\001\033[0m\002 (enter to skip): ")
      else
        label="${arg//[<>]/}"
        prompt=$(printf "  $arg  \001\033[0;36m\002$label\001\033[0m\002: ")
      fi
      read -e -p "$prompt" val
      [[ -n "$val" ]] && PARAMS+=("$val")
    done
    echo ""
  fi
}

# ── fallback TUI (no fzf) ─────────────────────────────────────────────────────

tui_fallback() {
  echo -e "\n  ${BOLD}🛠  tools${NC}  ${DIM}— your scripts, always at hand${NC}\n"

  local names=() files=()
  local i=1
  for entry in "${SCRIPTS[@]}"; do
    local file="${entry%%|*}" name="${entry#*|}"
    local desc
    desc=$(get_meta "$file" "description")
    printf "  ${CYAN}%2d)${NC}  %-30s  ${DIM}%s${NC}\n" "$i" "$name" "${desc:-(no description)}"
    names+=("$name")
    files+=("$file")
    (( i++ ))
  done

  echo ""
  local choice
  read -e -p "  Select a command (1-${#SCRIPTS[@]}, or q to quit): " choice
  echo ""

  [[ "$choice" == "q" || -z "$choice" ]] && exit 0

  if ! [[ "$choice" =~ ^[0-9]+$ ]] || (( choice < 1 || choice > ${#SCRIPTS[@]} )); then
    echo -e "  ${RED}Invalid selection.${NC}\n"
    exit 1
  fi

  local idx=$(( choice - 1 ))
  local selected="${names[$idx]}"
  local match_file="${files[$idx]}"

  # show inline preview
  local desc usage example deps presets
  desc=$(get_meta "$match_file" "description")
  usage=$(get_meta "$match_file" "usage")
  example=$(get_meta "$match_file" "example")
  deps=$(get_meta "$match_file" "deps")
  presets=$(get_meta "$match_file" "preset")

  echo -e "  ${BOLD}$selected${NC}"
  echo -e "  ──────────────────────────────"
  [[ -n "$desc" ]]    && echo -e "  $desc\n"
  [[ -n "$usage" ]]   && echo -e "  ${DIM}USAGE${NC}         tools $usage"
  [[ -n "$example" ]] && echo -e "  ${DIM}EXAMPLE${NC}       tools $example"
  [[ -n "$deps" ]]    && echo -e "  ${DIM}DEPS${NC}          $deps"
  if [[ -n "$presets" ]]; then
    echo -e "  ${DIM}PRESETS${NC}"
    echo "$presets" | while IFS= read -r line; do echo "    $line"; done
  fi
  echo ""

  collect_args "$match_file" "$selected"
  run_script "$match_file" "$selected" "${PARAMS[@]}"
}

# ── TUI ───────────────────────────────────────────────────────────────────────

build_list() {
  for entry in "${SCRIPTS[@]}"; do
    local file="${entry%%|*}" name="${entry#*|}"
    local desc
    desc=$(get_meta "$file" "description")
    printf "%-22s  %s\n" "$name" "${desc:-(no description)}"
  done
}

if ! command -v fzf &>/dev/null; then
  tui_fallback
  exit $?
fi

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

collect_args "$MATCH_FILE" "$SELECTED"
run_script "$MATCH_FILE" "$SELECTED" "${PARAMS[@]}"
