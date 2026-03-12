#!/bin/bash
# @description Compress images to WebP preserving folder structure
# @usage compress-images <input_dir> <output_dir> [preset]
# @example compress-images /photos/raw /photos/web high
# @deps cwebp parallel
# @preset lossless   cwebp -lossless -z 9 — zero quality loss, larger files
# @preset high       cwebp -q 90          — visually lossless, good compression
# @preset medium     cwebp -q 80          — balanced quality and size
# @preset low        cwebp -q 60          — smallest size, visible compression

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# ── check deps ────────────────────────────────────────────────────────────────

for cmd in cwebp parallel; do
  if ! command -v "$cmd" &>/dev/null; then
    echo -e "\n  ${RED}✗ $cmd not found${NC}\n"
    case "$cmd" in
      cwebp)
        echo -e "  ${CYAN}macOS${NC}          brew install webp"
        echo -e "  ${CYAN}Ubuntu/Debian${NC}  sudo apt install webp\n"
        ;;
      parallel)
        echo -e "  ${CYAN}macOS${NC}          brew install parallel"
        echo -e "  ${CYAN}Ubuntu/Debian${NC}  sudo apt install parallel\n"
        ;;
    esac
    exit 1
  fi
done

# ── args ──────────────────────────────────────────────────────────────────────

if [[ $# -lt 2 ]]; then
  echo -e "\n  ${BOLD}Usage:${NC} tools compress-images <input_dir> <output_dir> [preset]\n"
  echo -e "  ${DIM}Presets: lossless · high · medium · low  (default: lossless)${NC}\n"
  exit 1
fi

INPUT_DIR="${1%/}"
OUTPUT_DIR="$2"
PRESET="${3:-lossless}"

if [[ ! -d "$INPUT_DIR" ]]; then
  echo -e "\n  ${RED}✗ input directory not found:${NC} $INPUT_DIR\n"; exit 1
fi

# ── preset config ─────────────────────────────────────────────────────────────

case "$PRESET" in
  lossless)
    CWEBP_OPTS="-lossless -z 9"
    PRESET_DESC="lossless (cwebp -lossless -z 9)"
    ;;
  high)
    CWEBP_OPTS="-q 90"
    PRESET_DESC="high quality (q 90)"
    ;;
  medium)
    CWEBP_OPTS="-q 80"
    PRESET_DESC="medium quality (q 80)"
    ;;
  low)
    CWEBP_OPTS="-q 60"
    PRESET_DESC="low quality (q 60)"
    ;;
  *)
    echo -e "\n  ${RED}✗ unknown preset:${NC} $PRESET"
    echo -e "  Available: lossless · high · medium · low\n"
    exit 1
    ;;
esac

# ── parallel jobs ─────────────────────────────────────────────────────────────

RAM_GB=$(awk '/MemAvailable/ {printf "%.0f", $2/1024/1024}' /proc/meminfo 2>/dev/null \
  || sysctl -n hw.memsize 2>/dev/null | awk '{printf "%.0f", $1/1024/1024/1024}')
JOBS_BY_RAM=$(( RAM_GB / 2 ))
JOBS_BY_CPU=$(nproc 2>/dev/null || sysctl -n hw.logicalcpu 2>/dev/null || echo 1)
JOBS=$(( JOBS_BY_RAM < JOBS_BY_CPU ? JOBS_BY_RAM : JOBS_BY_CPU ))
[[ "$JOBS" -lt 1 ]] && JOBS=1

# ── scan ──────────────────────────────────────────────────────────────────────

mapfile -t ALL_FILES < <(find "$INPUT_DIR" -type f \( -iname "*.png" -o -iname "*.jpg" -o -iname "*.jpeg" \) | sort)

TODO=()
SKIPPED=0
for f in "${ALL_FILES[@]}"; do
  rel="${f#$INPUT_DIR/}"
  out="$OUTPUT_DIR/${rel%.*}.webp"
  if [[ -f "$out" ]]; then
    (( SKIPPED++ ))
  else
    TODO+=("$f")
  fi
done

TOTAL=${#TODO[@]}

if [[ ${#ALL_FILES[@]} -eq 0 ]]; then
  echo -e "\n  ${YELLOW}⚠ no image files found in:${NC} $INPUT_DIR\n"
  exit 0
fi

mkdir -p "$OUTPUT_DIR"

echo ""
echo -e "  ${BOLD}🖼  compress-images${NC}"
echo -e "  ${DIM}input:   $INPUT_DIR${NC}"
echo -e "  ${DIM}output:  $OUTPUT_DIR${NC}"
echo -e "  ${DIM}preset:  $PRESET_DESC${NC}"
echo -e "  ${DIM}jobs:    $JOBS (RAM: ${RAM_GB}GB, CPU: ${JOBS_BY_CPU} cores)${NC}"
echo -e "  ${DIM}found:   ${#ALL_FILES[@]} files  ($SKIPPED already converted, $TOTAL to process)${NC}"
echo ""
echo -e "  $(printf '─%.0s' {1..60})"
echo ""

if [[ $TOTAL -eq 0 ]]; then
  echo -e "  ${GREEN}✓ nothing to do — all files already converted${NC}\n"
  exit 0
fi

# ── convert function (called by parallel) ─────────────────────────────────────

export OUTPUT_DIR INPUT_DIR CWEBP_OPTS

convert_file() {
  f="$1"
  rel="${f#$INPUT_DIR/}"
  out="$OUTPUT_DIR/${rel%.*}.webp"

  mkdir -p "$(dirname "$out")"

  cwebp $CWEBP_OPTS "$f" -o "$out" 2>/dev/null

  if [[ $? -eq 0 ]]; then
    size_in=$(stat -c%s "$f" 2>/dev/null || stat -f%z "$f")
    size_out=$(stat -c%s "$out" 2>/dev/null || stat -f%z "$out")
    saved=$(( (size_in - size_out) * 100 / size_in ))
    echo "OK|$saved|$(basename "$f")|$out"
  else
    [[ -f "$out" ]] && rm "$out"
    echo "ERR|$(basename "$f")"
  fi
}
export -f convert_file

# ── run ───────────────────────────────────────────────────────────────────────

START_TIME=$(date +%s)

RESULTS=$(printf '%s\n' "${TODO[@]}" | \
  parallel --bar --eta -j"$JOBS" convert_file {})

END_TIME=$(date +%s)
ELAPSED=$(( END_TIME - START_TIME ))
MINS=$(( ELAPSED / 60 ))
SECS=$(( ELAPSED % 60 ))

# ── per-file output ───────────────────────────────────────────────────────────

echo ""
while IFS='|' read -r status rest; do
  case "$status" in
    OK)
      saved=$(echo "$rest" | cut -d'|' -f1)
      name=$(echo "$rest"  | cut -d'|' -f2)
      dest=$(echo "$rest"  | cut -d'|' -f3)
      echo -e "  ${GREEN}✓${NC} ${BOLD}$name${NC}  ${DIM}-${saved}%  ↳ $dest${NC}"
      ;;
    ERR)
      name=$(echo "$rest" | cut -d'|' -f1)
      echo -e "  ${RED}✗ failed:${NC} $name"
      ;;
  esac
done <<< "$RESULTS"

# ── summary ───────────────────────────────────────────────────────────────────

DONE=$(echo "$RESULTS"   | grep -c "^OK"  || true)
FAILED=$(echo "$RESULTS" | grep -c "^ERR" || true)
AVG_SAVED=$(echo "$RESULTS" | awk -F'|' '/^OK/{sum+=$2; n++} END{if(n>0) printf "%.1f", sum/n; else print "0"}')

echo ""
echo -e "  $(printf '─%.0s' {1..60})"
echo ""
echo -e "  ${BOLD}Results${NC}  $TOTAL files processed"
echo ""
echo -e "  ${GREEN}✓ done      ${BOLD}$DONE${NC}"
echo -e "  ${DIM}📉 avg saved  ${AVG_SAVED}%${NC}"
[[ $SKIPPED -gt 0 ]] && echo -e "  ${DIM}⏭ skipped    $SKIPPED${NC}"
[[ $FAILED  -gt 0 ]] && echo -e "  ${RED}✗ failed    ${BOLD}$FAILED${NC}"
echo -e "  ${DIM}⏱  time      ${MINS}m ${SECS}s${NC}"
echo ""