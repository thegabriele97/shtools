#!/bin/bash
# @description Compress video files in a folder while preserving all metadata
# @usage compress-video <input_dir> <output_dir> [preset] [crf]
# @example compress-video /videos/raw /videos/compressed h265 28
# @deps ffmpeg
# @preset lossless   h264 crf 0    — zero quality loss, large files
# @preset h264       libx264 crf 18 — visually lossless, best compatibility
# @preset h265       libx265 crf 22 — ~50% smaller than h264, same quality
# @preset av1        libsvtav1 crf 30 — smallest size, slow encode, modern only

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# ── check deps ────────────────────────────────────────────────────────────────

if ! command -v ffmpeg &>/dev/null; then
  echo -e "\n  ${RED}✗ ffmpeg not found${NC}\n"
  echo -e "  ${CYAN}macOS${NC}          brew install ffmpeg"
  echo -e "  ${CYAN}Ubuntu/Debian${NC}  sudo apt install ffmpeg\n"
  exit 1
fi

# ── args ──────────────────────────────────────────────────────────────────────

if [[ $# -lt 2 ]]; then
  echo -e "\n  ${BOLD}Usage:${NC} tools compress-video <input_dir> <output_dir> [preset]\n"
  echo -e "  ${DIM}Presets: lossless · h264 · h265 · av1  (default: h265)${NC}\n"
  exit 1
fi

INPUT_DIR="${1%/}"  # strip trailing slash
OUTPUT_DIR="$2"
PRESET="${3:-h265}"
CUSTOM_CRF="${4:-}"

if [[ ! -d "$INPUT_DIR" ]]; then
  echo -e "\n  ${RED}✗ input directory not found:${NC} $INPUT_DIR\n"; exit 1
fi

# ── preset config ─────────────────────────────────────────────────────────────

case "$PRESET" in
  lossless)
    CODEC="libx264"
    CRF="0"
    EXTRA="-preset ultrafast"
    PRESET_DESC="h264 lossless (crf 0)"
    ;;
  h264)
    CODEC="libx264"
    CRF="18"
    EXTRA="-preset slow"
    PRESET_DESC="h264 visually lossless (crf 18)"
    ;;
  h265)
    CODEC="libx265"
    CRF="22"
    EXTRA="-preset slow"
    PRESET_DESC="h265 high quality (crf 22)"
    ;;
  av1)
    CODEC="libsvtav1"
    CRF="30"
    EXTRA="-preset 4"
    PRESET_DESC="av1 high efficiency (crf 30)"
    ;;
  *)
    echo -e "\n  ${RED}✗ unknown preset:${NC} $PRESET"
    echo -e "  Available: lossless · h264 · h265 · av1\n"
    exit 1
    ;;
esac

# ── scan ──────────────────────────────────────────────────────────────────────

mapfile -t FILES < <(find "$INPUT_DIR" -type f \( -iname "*.mp4" -o -iname "*.mkv" -o -iname "*.mov" -o -iname "*.avi" -o -iname "*.webm" \) | sort)
TOTAL=${#FILES[@]}

if [[ $TOTAL -eq 0 ]]; then
  echo -e "\n  ${YELLOW}⚠ no video files found in:${NC} $INPUT_DIR\n"
  exit 0
fi

mkdir -p "$OUTPUT_DIR"

echo ""
echo -e "  ${BOLD}🎬 compress-video${NC}"
echo -e "  ${DIM}input:   $INPUT_DIR${NC}"
echo -e "  ${DIM}output:  $OUTPUT_DIR${NC}"
echo -e "  ${DIM}preset:  $PRESET_DESC${NC}"
echo -e "  ${DIM}files:   $TOTAL${NC}"
echo ""
echo -e "  $(printf '─%.0s' {1..60})"
echo ""

DONE=0
FAILED=0

for file in "${FILES[@]}"; do
  name=$(basename "$file")
  # preserve relative subfolder structure
  rel=$(dirname "$file" | sed "s|^$INPUT_DIR||" | sed 's|^/||')
  if [[ -n "$rel" ]]; then
    dest_dir="$OUTPUT_DIR/$rel"
  else
    dest_dir="$OUTPUT_DIR"
  fi
  mkdir -p "$dest_dir"

  # keep original extension for lossless/h264/h265, use mkv for av1 (best container support)
  ext="${file##*.}"
  [[ "$PRESET" == "av1" ]] && ext="mkv"
  output="$dest_dir/${name%.*}.$ext"

  echo -e "  ${BOLD}$name${NC}"
  [[ -n "$rel" ]] && echo -e "  ${DIM}$rel${NC}"

  # get original size
  orig_size=$(du -sh "$file" 2>/dev/null | cut -f1)

  FINAL_CRF="${CUSTOM_CRF:-$CRF}"
  ffmpeg -i "$file" \
    -c:v "$CODEC" -crf "$FINAL_CRF" $EXTRA \
    -c:a copy \
    -map_metadata 0 \
    -movflags use_metadata_tags \
    "$output" \
    -loglevel error -stats 2>&1

  if [[ $? -eq 0 ]]; then
    new_size=$(du -sh "$output" 2>/dev/null | cut -f1)

    # compute SSIM between original and compressed
    ssim_raw=$(ffmpeg -i "$file" -i "$output"       -lavfi ssim       -f null - 2>&1 | grep "SSIM" | grep -oP "All:\K[0-9.]+" | tail -1)

    if [[ -n "$ssim_raw" ]]; then
      # color code: green ≥0.98, yellow ≥0.95, red <0.95
      if (( $(echo "$ssim_raw >= 0.98" | bc -l) )); then
        ssim_color="$GREEN"
      elif (( $(echo "$ssim_raw >= 0.95" | bc -l) )); then
        ssim_color="$YELLOW"
      else
        ssim_color="$RED"
      fi
      ssim_display="${ssim_color}ssim $ssim_raw${NC}"
    else
      ssim_display="${DIM}ssim n/a${NC}"
    fi

    echo -e "  ${GREEN}✓${NC} ${DIM}$orig_size → $new_size${NC}  $ssim_display  ${DIM}↳ $output${NC}"
    ((DONE++))
  else
    echo -e "  ${RED}✗ failed${NC}"
    [[ -f "$output" ]] && rm "$output"
    ((FAILED++))
  fi
  echo ""
done

# ── summary ───────────────────────────────────────────────────────────────────

echo -e "  $(printf '─%.0s' {1..60})"
echo ""
echo -e "  ${BOLD}Results${NC}  $TOTAL files processed"
echo ""
echo -e "  ${GREEN}✓ done      ${BOLD}$DONE${NC}"
[[ $FAILED -gt 0 ]] && echo -e "  ${RED}✗ failed    ${BOLD}$FAILED${NC}"
echo ""