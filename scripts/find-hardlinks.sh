#!/bin/bash
# @description Cerca file in un path e verifica se hanno un hard link in un secondo path (confronto per inode)
# @usage find-hardlinks <base_path> <search_path> [ext1,ext2,...]
# @example find-hardlinks /media/films /mnt/backup mkv,mp4
# @deps find, ls

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# ── args ───────────────────────────────────────────────────────────────────────

if [[ $# -lt 2 ]]; then
  echo -e "\n  ${BOLD}Usage:${NC} tools find-hardlinks <base_path> <search_path> [ext1,ext2,...]\n"
  echo -e "  ${DIM}es: find-hardlinks /media/films /mnt/backup mkv,mp4${NC}"
  echo -e "  ${DIM}    find-hardlinks /documenti /mnt/backup pdf,docx${NC}"
  echo -e "  ${DIM}    se ometti le estensioni usa mkv,mp4 come default${NC}\n"
  exit 1
fi

BASE_PATH="$1"
SEARCH_PATH="$2"
EXT_ARG="${3:-mkv,mp4}"

if [[ ! -d "$BASE_PATH" ]]; then
  echo -e "\n  ${RED}✗ path non trovato:${NC} $BASE_PATH\n"; exit 1
fi
if [[ ! -d "$SEARCH_PATH" ]]; then
  echo -e "\n  ${RED}✗ path non trovato:${NC} $SEARCH_PATH\n"; exit 1
fi

# ── scan ───────────────────────────────────────────────────────────────────────

# costruisce array di predicati find senza eval
FIND_ARGS=()
IFS=',' read -ra EXTS <<< "$EXT_ARG"
for ext in "${EXTS[@]}"; do
  ext="${ext// /}"
  [[ ${#FIND_ARGS[@]} -gt 0 ]] && FIND_ARGS+=("-o")
  FIND_ARGS+=("-iname" "*.${ext}")
done

mapfile -t FILES < <(find "$BASE_PATH" -type f \( "${FIND_ARGS[@]}" \) | sort)
TOTAL=${#FILES[@]}
EXT_DISPLAY="${EXT_ARG//,/, }"

if [[ $TOTAL -eq 0 ]]; then
  echo -e "\n  ${YELLOW}⚠ nessun file [$EXT_DISPLAY] trovato in:${NC} $BASE_PATH\n"
  exit 0
fi

echo ""
echo -e "  ${BOLD}🔍 find-hardlinks${NC}"
echo -e "  ${DIM}base:        $BASE_PATH${NC}"
echo -e "  ${DIM}search:      $SEARCH_PATH${NC}"
echo -e "  ${DIM}estensioni:  $EXT_DISPLAY${NC}"
echo -e "  ${DIM}file:        $TOTAL${NC}"
echo ""
echo -e "  $(printf '─%.0s' {1..60})"
echo ""

FOUND=0
NOT_FOUND=0

for file in "${FILES[@]}"; do
  inode=$(ls -i "$file" | awk '{print $1}')
  match=$(find "$SEARCH_PATH" -inum "$inode" 2>/dev/null)
  name=$(basename "$file")
  dir=$(dirname "$file" | sed "s|^$BASE_PATH||" | sed 's|^/||')

  if [[ -n "$match" ]]; then
    echo -e "  ${GREEN}✓${NC}  ${BOLD}$name${NC}"
    [[ -n "$dir" ]] && echo -e "     ${DIM}$dir${NC}"
    echo -e "     ${DIM}↳ $match${NC}"
    ((FOUND++))
  else
    echo -e "  ${RED}✗${NC}  ${BOLD}$name${NC}"
    [[ -n "$dir" ]] && echo -e "     ${DIM}$dir${NC}"
    ((NOT_FOUND++))
  fi
  echo ""
done

# ── summary ────────────────────────────────────────────────────────────────────

echo -e "  $(printf '─%.0s' {1..60})"
echo ""
echo -e "  ${BOLD}Risultati${NC}  $TOTAL file analizzati"
echo ""
echo -e "  ${GREEN}✓ trovati      ${BOLD}$FOUND${NC}"
echo -e "  ${RED}✗ non trovati  ${BOLD}$NOT_FOUND${NC}"
echo ""