#!/bin/bash
# @description Inspect, normalize and concatenate video clips into a single file
# @usage concat-clips <clips_dir> <output_file>
# @example concat-clips /videos/clips final.mp4
# @deps ffmpeg ffprobe

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# ── check deps ────────────────────────────────────────────────────────────────

for cmd in ffmpeg ffprobe; do
  if ! command -v "$cmd" &>/dev/null; then
    echo -e "\n  ${RED}✗ $cmd not found${NC}\n"
    echo -e "  ${CYAN}macOS${NC}          brew install ffmpeg"
    echo -e "  ${CYAN}Ubuntu/Debian${NC}  sudo apt install ffmpeg\n"
    exit 1
  fi
done

# ── args ──────────────────────────────────────────────────────────────────────

if [[ $# -lt 2 ]]; then
  echo -e "\n  ${BOLD}Usage:${NC} tools concat-clips <clips_dir> <output_file>\n"
  exit 1
fi

CLIPS_DIR="${1%/}"
OUTPUT_FILE="$2"

if [[ ! -d "$CLIPS_DIR" ]]; then
  echo -e "\n  ${RED}✗ directory not found:${NC} $CLIPS_DIR\n"; exit 1
fi

# ── scan clips ────────────────────────────────────────────────────────────────

mapfile -t CLIPS < <(find "$CLIPS_DIR" -maxdepth 1 -type f \
  \( -iname "*.mp4" -o -iname "*.mkv" -o -iname "*.mov" \) | sort)

TOTAL=${#CLIPS[@]}

if [[ $TOTAL -eq 0 ]]; then
  echo -e "\n  ${YELLOW}⚠ no video files found in:${NC} $CLIPS_DIR\n"
  exit 0
fi

echo ""
echo -e "  ${BOLD}✂  concat-clips${NC}"
echo -e "  ${DIM}input:   $CLIPS_DIR${NC}"
echo -e "  ${DIM}output:  $OUTPUT_FILE${NC}"
echo ""
echo -e "  $(printf '─%.0s' {1..60})"
echo ""
echo -e "  ${BOLD}Clips found — concatenation order:${NC}"
echo ""

for i in "${!CLIPS[@]}"; do
  name=$(basename "${CLIPS[$i]}")
  duration=$(ffprobe -v error -show_entries format=duration \
    -of default=noprint_wrappers=1:nokey=1 "${CLIPS[$i]}" 2>/dev/null \
    | awk '{printf "%.1fs", $1}')
  size=$(du -sh "${CLIPS[$i]}" 2>/dev/null | cut -f1)
  echo -e "  ${DIM}$((i+1)).${NC} ${BOLD}$name${NC}  ${DIM}$duration  $size${NC}"
done

echo ""
read -e -p "  $(printf "\033[0;36m")proceed with these clips in this order? [y/N]$(printf "\033[0m") " confirm
if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
  echo -e "\n  ${YELLOW}aborted${NC}\n"
  exit 0
fi

# ── A — inspect FPS ───────────────────────────────────────────────────────────

echo ""
echo -e "  $(printf '─%.0s' {1..60})"
echo ""
echo -e "  ${BOLD}A — FPS check${NC}"
echo ""

declare -A CLIP_FPS
ALL_SAME=true
FIRST_FPS=""

for clip in "${CLIPS[@]}"; do
  name=$(basename "$clip")
  fps=$(ffprobe -v error -show_entries stream=r_frame_rate \
    -of default=noprint_wrappers=1:nokey=1 "$clip" 2>/dev/null | head -1)
  # simplify fraction if possible (e.g. 60/1 → 60, 30000/1001 → 29.97)
  fps_display=$(echo "$fps" | awk -F'/' '{if($2==1) print $1; else printf "%.2f", $1/$2}')
  CLIP_FPS["$clip"]="$fps"

  if [[ -z "$FIRST_FPS" ]]; then
    FIRST_FPS="$fps"
  elif [[ "$fps" != "$FIRST_FPS" ]]; then
    ALL_SAME=false
  fi

  # check if fps is a clean integer
  denom=$(echo "$fps" | cut -d'/' -f2)
  if [[ "$denom" != "1" && "$denom" != "" ]]; then
    echo -e "  ${YELLOW}⚠${NC}  ${BOLD}$name${NC}  ${DIM}fps: $fps_display (${fps})${NC}"
  else
    echo -e "  ${GREEN}✓${NC}  ${BOLD}$name${NC}  ${DIM}fps: $fps_display${NC}"
  fi
done

echo ""

NEED_CLEAN=false

if [[ "$ALL_SAME" == true ]]; then
  fps_display=$(echo "$FIRST_FPS" | awk -F'/' '{if($2==1) print $1; else printf "%.2f", $1/$2}')
  echo -e "  ${GREEN}✓ all clips have the same FPS ($fps_display) — normalization not needed${NC}"
else
  echo -e "  ${YELLOW}⚠ clips have different or irregular FPS — normalization recommended${NC}"
  NEED_CLEAN=true
fi

# also check for irregular framerates (non-integer denominator)
for clip in "${CLIPS[@]}"; do
  fps="${CLIP_FPS[$clip]}"
  denom=$(echo "$fps" | cut -d'/' -f2)
  if [[ "$denom" != "1" && "$denom" != "" ]]; then
    NEED_CLEAN=true
    break
  fi
done

if [[ "$NEED_CLEAN" == true ]]; then
  echo ""
  # detect target fps from most common value
  TARGET_FPS=$(for clip in "${CLIPS[@]}"; do
    echo "${CLIP_FPS[$clip]}" | awk -F'/' '{if($2==1) print $1; else printf "%.0f", $1/$2}'
  done | sort | uniq -c | sort -rn | head -1 | awk '{print $2}')

  echo -e "  ${DIM}target fps for normalization: ${TARGET_FPS}${NC}"
  echo ""
  read -e -p "  $(printf "\033[0;36m")normalize all clips to ${TARGET_FPS}fps? [y/N]$(printf "\033[0m") " confirm
  if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
    echo -e "\n  ${YELLOW}skipping normalization — concat may produce issues${NC}\n"
    NEED_CLEAN=false
  fi
fi

# ── B — normalize FPS ─────────────────────────────────────────────────────────

CLEANED_DIR="$CLIPS_DIR/cleaned"
SOURCE_CLIPS=("${CLIPS[@]}")

if [[ "$NEED_CLEAN" == true ]]; then
  mkdir -p "$CLEANED_DIR"

  echo ""
  echo -e "  $(printf '─%.0s' {1..60})"
  echo ""
  echo -e "  ${BOLD}B — normalization${NC}"
  echo ""

  CLEAN_CLIPS=()
  for clip in "${CLIPS[@]}"; do
    name=$(basename "$clip")
    out="$CLEANED_DIR/$name"

    echo -e "  ${BOLD}$name${NC}"
    ffmpeg -y \
      -fflags +discardcorrupt \
      -i "$clip" \
      -c:v libx264 -crf 14 -preset veryfast \
      -c:a aac -b:a 192k \
      -vsync cfr \
      -r "$TARGET_FPS" \
      "$out" \
      -loglevel error -stats 2>&1

    if [[ $? -eq 0 ]]; then
      fps_out=$(ffprobe -v error -show_entries stream=r_frame_rate \
        -of default=noprint_wrappers=1:nokey=1 "$out" 2>/dev/null | head -1)
      fps_display=$(echo "$fps_out" | awk -F'/' '{if($2==1) print $1; else printf "%.2f", $1/$2}')
      echo -e "  ${GREEN}✓${NC} ${DIM}fps: $fps_display  ↳ $out${NC}"
      CLEAN_CLIPS+=("$out")
    else
      echo -e "  ${RED}✗ failed${NC}"
    fi
    echo ""
  done

  # verify all cleaned clips have uniform fps
  echo -e "  ${BOLD}FPS after normalization:${NC}"
  echo ""
  for clip in "${CLEAN_CLIPS[@]}"; do
    name=$(basename "$clip")
    fps=$(ffprobe -v error -show_entries stream=r_frame_rate \
      -of default=noprint_wrappers=1:nokey=1 "$clip" 2>/dev/null | head -1)
    fps_display=$(echo "$fps" | awk -F'/' '{if($2==1) print $1; else printf "%.2f", $1/$2}')
    denom=$(echo "$fps" | cut -d'/' -f2)
    if [[ "$denom" == "1" ]]; then
      echo -e "  ${GREEN}✓${NC}  ${BOLD}$name${NC}  ${DIM}$fps_display${NC}"
    else
      echo -e "  ${YELLOW}⚠${NC}  ${BOLD}$name${NC}  ${DIM}$fps_display ($fps)${NC}"
    fi
  done

  SOURCE_CLIPS=("${CLEAN_CLIPS[@]}")
fi

# ── C — concat ────────────────────────────────────────────────────────────────

echo ""
echo -e "  $(printf '─%.0s' {1..60})"
echo ""
echo -e "  ${BOLD}C — concat${NC}"
echo ""

FILELIST=$(mktemp /tmp/concat_XXXXXX.txt)
for clip in "${SOURCE_CLIPS[@]}"; do
  echo "file '$clip'" >> "$FILELIST"
done

ffmpeg -y \
  -f concat -safe 0 -i "$FILELIST" \
  -c copy \
  -movflags +faststart \
  "$OUTPUT_FILE" \
  -loglevel error -stats 2>&1

rm -f "$FILELIST"

if [[ $? -ne 0 ]]; then
  echo -e "\n  ${RED}✗ concat failed${NC}\n"
  exit 1
fi

# ── D — final verification ────────────────────────────────────────────────────

echo ""
echo -e "  $(printf '─%.0s' {1..60})"
echo ""
echo -e "  ${BOLD}D — verification${NC}"
echo ""

VIDEO_DUR=$(ffprobe -v error -select_streams v:0 \
  -show_entries stream=duration \
  -of default=noprint_wrappers=1:nokey=1 "$OUTPUT_FILE" 2>/dev/null)
AUDIO_DUR=$(ffprobe -v error -select_streams a:0 \
  -show_entries stream=duration \
  -of default=noprint_wrappers=1:nokey=1 "$OUTPUT_FILE" 2>/dev/null)
FPS_OUT=$(ffprobe -v error -select_streams v:0 \
  -show_entries stream=r_frame_rate \
  -of default=noprint_wrappers=1:nokey=1 "$OUTPUT_FILE" 2>/dev/null)
RESOLUTION=$(ffprobe -v error -select_streams v:0 \
  -show_entries stream=width,height \
  -of default=noprint_wrappers=1:nokey=1 "$OUTPUT_FILE" 2>/dev/null \
  | tr '\n' 'x' | sed 's/x$//')
CODEC_OUT=$(ffprobe -v error -select_streams v:0 \
  -show_entries stream=codec_name \
  -of default=noprint_wrappers=1:nokey=1 "$OUTPUT_FILE" 2>/dev/null)
SIZE=$(du -sh "$OUTPUT_FILE" 2>/dev/null | cut -f1)

fps_display=$(echo "$FPS_OUT" | awk -F'/' '{if($2==1) print $1; else printf "%.2f", $1/$2}')

# duration diff
DUR_DIFF=$(echo "$VIDEO_DUR $AUDIO_DUR" | awk '{d=$1-$2; if(d<0)d=-d; printf "%.2f", d}')
DUR_OK=$(echo "$DUR_DIFF" | awk '{print ($1 < 1.0) ? "yes" : "no"}')

echo -e "  ${DIM}file:        $OUTPUT_FILE${NC}"
echo -e "  ${DIM}size:        $SIZE${NC}"
echo -e "  ${DIM}codec:       $CODEC_OUT${NC}"
echo -e "  ${DIM}resolution:  $RESOLUTION${NC}"
echo -e "  ${DIM}fps:         $fps_display${NC}"
echo -e "  ${DIM}video dur:   $(echo "$VIDEO_DUR" | awk '{printf "%.2fs", $1}')${NC}"
echo -e "  ${DIM}audio dur:   $(echo "$AUDIO_DUR" | awk '{printf "%.2fs", $1}')${NC}"

if [[ "$DUR_OK" == "yes" ]]; then
  echo -e "  ${GREEN}✓${NC} ${DIM}a/v diff:    ${DUR_DIFF}s — ok${NC}"
else
  echo -e "  ${RED}✗${NC} ${DIM}a/v diff:    ${DUR_DIFF}s — audio and video are out of sync${NC}"
fi

echo ""
echo -e "  ${GREEN}✓ done:${NC} $OUTPUT_FILE"
echo ""