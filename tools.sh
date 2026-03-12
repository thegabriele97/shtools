#!/bin/bash

# ── config ─────────────────────────────────────────────────────────────────────
BASE_URL="https://raw.githubusercontent.com/TUONOME/tools/main/scripts"
# ───────────────────────────────────────────────────────────────────────────────

# ── colori ─────────────────────────────────────────────────────────────────────
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'
# ───────────────────────────────────────────────────────────────────────────────

# ── check fzf ──────────────────────────────────────────────────────────────────
if ! command -v fzf &>/dev/null; then
  echo ""
  echo -e "  ${RED}${BOLD}✗ fzf non trovato${NC}"
  echo ""
  echo -e "  ${BOLD}Installalo con:${NC}"
  echo ""
  echo -e "  ${CYAN}# macOS${NC}"
  echo -e "    brew install fzf"
  echo ""
  echo -e "  ${CYAN}# Ubuntu / Debian${NC}"
  echo -e "    sudo apt install fzf"
  echo ""
  echo -e "  ${CYAN}# Arch${NC}"
  echo -e "    sudo pacman -S fzf"
  echo ""
  echo -e "  ${CYAN}# Fedora${NC}"
  echo -e "    sudo dnf install fzf"
  echo ""
  exit 1
fi
# ───────────────────────────────────────────────────────────────────────────────

# ── funzioni helper ─────────────────────────────────────────────────────────────

# trova lo script: prima remote, poi locale
resolve_script() {
  local script="$1"
  local local_path="./scripts/$script"

  if [[ -f "$local_path" ]]; then
    echo "local:$local_path"
    return
  fi

  # prova remote
  local http_code
  http_code=$(curl -sL -o /dev/null -w "%{http_code}" "$BASE_URL/$script" 2>/dev/null)
  if [[ "$http_code" == "200" ]]; then
    echo "remote:$BASE_URL/$script"
    return
  fi

  echo "notfound"
}

# estrae un tag (@description, @usage, ecc.) da uno script
get_meta() {
  local script="$1"
  local tag="$2"
  local source
  source=$(resolve_script "$script")

  if [[ "$source" == local:* ]]; then
    grep "^# @${tag}" "${source#local:}" | sed "s/^# @${tag} //"
  elif [[ "$source" == remote:* ]]; then
    curl -sL "${source#remote:}" 2>/dev/null | grep "^# @${tag}" | sed "s/^# @${tag} //"
  fi
}

# esegui uno script con i parametri passati
# $1 = nome file (compress-video.sh), $2 = nome comando (compress-video), resto = parametri
run_script() {
  local script="$1"
  local cmd_name="$2"
  shift 2
  local source
  source=$(resolve_script "$script")

  local cmd_display="tools $cmd_name $*"
  if [[ "$source" == local:* ]]; then
    echo -e "  ${DIM}↳ ${CYAN}$cmd_display${NC}"
    echo -e "  ${DIM}   (locale: ${source#local:})${NC}\n"
    bash "${source#local:}" "$@"
  elif [[ "$source" == remote:* ]]; then
    echo -e "  ${DIM}↳ ${CYAN}$cmd_display${NC}"
    echo -e "  ${DIM}   (remoto: ${source#remote:})${NC}\n"
    bash <(curl -sL "${source#remote:}") "$@"
  else
    echo -e "\n  ${RED}✗ script non trovato né in remoto né in ./scripts/${NC}\n"
    exit 1
  fi
}

# ── lista script disponibili ───────────────────────────────────────────────────
# Aggiungi qui i tuoi script: "nomefile.sh|Nome leggibile"
SCRIPTS=(
  "compress-video.sh|compress-video"
  "compress-images.sh|compress-images"
  "organize-files.sh|organize-files"
)

# ── modalità diretta (es: tools compress-video input.mp4) ─────────────────────
if [[ -n "$1" ]]; then
  COMMAND="$1"
  shift
  MATCH=""
  for entry in "${SCRIPTS[@]}"; do
    name="${entry#*|}"
    file="${entry%%|*}"
    if [[ "$name" == "$COMMAND" ]]; then
      MATCH="$file"
      break
    fi
  done
  if [[ -z "$MATCH" ]]; then
    echo -e "\n  ${RED}Comando non trovato:${NC} $COMMAND"
    echo -e "  Lancia ${CYAN}tools${NC} senza argomenti per vedere la lista\n"
    exit 1
  fi
  run_script "$MATCH" "$COMMAND" "$@"
  exit $?
fi

# ── TUI con fzf ───────────────────────────────────────────────────────────────

# costruisce la lista "nome | descrizione" per fzf
build_list() {
  for entry in "${SCRIPTS[@]}"; do
    file="${entry%%|*}"
    name="${entry#*|}"
    desc=$(get_meta "$file" "description")
    printf "%-22s  %s\n" "$name" "${desc:-(nessuna descrizione)}"
  done
}

# genera il pannello preview dato il nome comando
preview_script() {
  local name="$1"
  local file="${name}.sh"  # convenzione: nome comando = nome file senza .sh

  local desc usage example deps
  desc=$(get_meta "$file" "description")
  usage=$(get_meta "$file" "usage")
  example=$(get_meta "$file" "example")
  deps=$(get_meta "$file" "deps")

  echo ""
  echo "  📄 $name"
  echo "  ──────────────────────────────"
  echo ""
  [[ -n "$desc" ]]    && echo "  $desc" && echo ""
  [[ -n "$usage" ]]   && echo "  USAGE"    && echo "  tools $usage"   && echo ""
  [[ -n "$example" ]] && echo "  EXAMPLE"  && echo "  tools $example" && echo ""
  [[ -n "$deps" ]]    && echo "  DIPENDENZE"  && echo "  $deps"        && echo ""
}

export -f preview_script get_meta resolve_script
export BASE_URL

# header
echo -e "\n  ${BOLD}🛠  tools${NC}  ${DIM}— i tuoi script, sempre a portata${NC}\n"

# lancia fzf
SELECTED=$(build_list | fzf \
  --ansi \
  --no-sort \
  --prompt="  ❯ " \
  --pointer="▶" \
  --height=80% \
  --layout=reverse \
  --border=rounded \
  --preview='preview_script "$(echo {} | awk "{print \$1}")"' \
  --preview-window=right:45%:wrap \
  --header=$'  frecce per navigare · invio per eseguire · esc per uscire\n' \
  | awk '{print $1}')

[[ -z "$SELECTED" ]] && exit 0

# chiede i parametri se lo script li richiede
MATCH_FILE=""
for entry in "${SCRIPTS[@]}"; do
  n="${entry#*|}"
  f="${entry%%|*}"
  if [[ "$n" == "$SELECTED" ]]; then
    MATCH_FILE="$f"
    break
  fi
done

USAGE=$(get_meta "$MATCH_FILE" "usage")
EXAMPLE=$(get_meta "$MATCH_FILE" "example")

# estrae blocchi <...> e [...] come token singoli
ARGS=()
if [[ -n "$USAGE" ]]; then
  ARGS_RAW=$(echo "$USAGE" | sed 's/^[^ ]* //')
  while [[ -n "$ARGS_RAW" ]]; do
    if [[ "$ARGS_RAW" =~ ^(\<[^\>]+\>)(.*)$ ]]; then
      ARGS+=("${BASH_REMATCH[1]}")
      ARGS_RAW="${BASH_REMATCH[2]# }"
    elif [[ "$ARGS_RAW" =~ ^(\[[^\]]+\])(.*)$ ]]; then
      ARGS+=("${BASH_REMATCH[1]}")
      ARGS_RAW="${BASH_REMATCH[2]# }"
    else
      break
    fi
  done
fi

PARAMS=()
if [[ ${#ARGS[@]} -gt 0 ]]; then
  echo ""
  echo -e "  ${BOLD}$SELECTED${NC}"
  [[ -n "$EXAMPLE" ]] && echo -e "  ${DIM}esempio: tools $EXAMPLE${NC}"
  echo ""

  for arg in "${ARGS[@]}"; do
    # opzionale se inizia con [
    if [[ "$arg" == \[* ]]; then
      label="${arg//[\[\]]/}"
      echo -ne "  ${DIM}$arg${NC}  ${CYAN}$label${NC} (invio per saltare): "
    else
      label="${arg//[<>]/}"
      echo -ne "  ${arg}  ${CYAN}$label${NC}: "
    fi

    read -r val
    [[ -n "$val" ]] && PARAMS+=("$val")
  done
  echo ""
fi

run_script "$MATCH_FILE" "$SELECTED" "${PARAMS[@]}"