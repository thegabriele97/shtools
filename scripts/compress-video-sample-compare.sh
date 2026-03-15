#!/bin/bash
# @description Generate compressed clips at different CRF values and extract frames for visual comparison
# @usage compress-video-sample-compare <input_file> <output_dir> <preset> <crf1,crf2,...>
# @example compress-video-sample-compare film.mp4 /tmp/compare h265 18,22,28,34
# @deps ffmpeg

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

CLIP_DURATION=120

# ── check deps ────────────────────────────────────────────────────────────────

if ! command -v ffmpeg &>/dev/null; then
  echo -e "\n  ${RED}✗ ffmpeg not found${NC}\n"
  echo -e "  ${CYAN}macOS${NC}          brew install ffmpeg"
  echo -e "  ${CYAN}Ubuntu/Debian${NC}  sudo apt install ffmpeg\n"
  exit 1
fi

# ── args ──────────────────────────────────────────────────────────────────────

if [[ $# -lt 4 ]]; then
  echo -e "\n  ${BOLD}Usage:${NC} tools compress-video-sample-compare <input_file> <output_dir> <preset> <crf1,crf2,...>\n"
  echo -e "  ${DIM}Presets: h264 · h265${NC}"
  echo -e "  ${DIM}e.g: compress-video-sample-compare film.mp4 /tmp/compare h265 18,22,28,34${NC}\n"
  exit 1
fi

INPUT="$1"
OUTPUT_DIR="${2%/}"
PRESET="$3"
CRF_ARG="$4"

if [[ ! -f "$INPUT" ]]; then
  echo -e "\n  ${RED}✗ file not found:${NC} $INPUT\n"; exit 1
fi

# ── preset config ─────────────────────────────────────────────────────────────

case "$PRESET" in
  h264)
    CODEC="libx264"
    EXT="mp4"
    EXTRA="-preset slow"
    ;;
  h265)
    CODEC="libx265"
    EXT="mp4"
    EXTRA="-preset slow"
    ;;
  *)
    echo -e "\n  ${RED}✗ unknown preset:${NC} $PRESET"
    echo -e "  Available: h264 · h265\n"
    exit 1
    ;;
esac

# ── parse CRF list ────────────────────────────────────────────────────────────

IFS=',' read -ra CRFS <<< "$CRF_ARG"

# ── get actual clip duration (video might be shorter than 120s) ───────────────

VIDEO_DURATION=$(ffprobe -v error -show_entries format=duration \
  -of default=noprint_wrappers=1:nokey=1 "$INPUT" 2>/dev/null | cut -d. -f1)

if [[ "$VIDEO_DURATION" -lt "$CLIP_DURATION" ]]; then
  CLIP_DURATION="$VIDEO_DURATION"
fi

# ── pick 3 random timestamps (min 10s apart) ──────────────────────────────────

MIN_SEP=10
TIMESTAMPS=()
MAX_ATTEMPTS=100
ATTEMPTS=0

while [[ ${#TIMESTAMPS[@]} -lt 3 ]]; do
  (( ATTEMPTS++ ))
  if [[ $ATTEMPTS -gt $MAX_ATTEMPTS ]]; then
    echo -e "\n  ${RED}✗ could not find 3 timestamps with ${MIN_SEP}s separation in ${CLIP_DURATION}s clip${NC}\n"
    exit 1
  fi
  T=$(( RANDOM % CLIP_DURATION ))
  OK=1
  for existing in "${TIMESTAMPS[@]}"; do
    diff=$(( T - existing ))
    [[ $diff -lt 0 ]] && diff=$(( -diff ))
    if [[ $diff -lt $MIN_SEP ]]; then
      OK=0
      break
    fi
  done
  [[ $OK -eq 1 ]] && TIMESTAMPS+=("$T")
done

# ── setup output dirs ─────────────────────────────────────────────────────────

CLIPS_DIR="$OUTPUT_DIR/clips"
IMG_DIR="$OUTPUT_DIR/img"
mkdir -p "$CLIPS_DIR"
for T in "${TIMESTAMPS[@]}"; do
  mkdir -p "$IMG_DIR/${T}s"
done

echo ""
echo -e "  ${BOLD}🎬 compress-video-sample-compare${NC}"
echo -e "  ${DIM}input:     $INPUT${NC}"
echo -e "  ${DIM}output:    $OUTPUT_DIR${NC}"
echo -e "  ${DIM}preset:    $PRESET${NC}"
echo -e "  ${DIM}crfs:      ${CRFS[*]}${NC}"
echo -e "  ${DIM}duration:  ${CLIP_DURATION}s${NC}"
echo -e "  ${DIM}frames at: ${TIMESTAMPS[*]} s${NC}"
echo ""
echo -e "  $(printf '─%.0s' {1..60})"
echo ""

DONE=0
FAIL=0

# ── extract frames from original ──────────────────────────────────────────────

echo -e "  ${BOLD}original${NC}"
for T in "${TIMESTAMPS[@]}"; do
  FRAME="$IMG_DIR/${T}s/original.jpg"
  ffmpeg -y -ss "$T" -i "$INPUT" \
    -frames:v 1 -q:v 2 \
    "$FRAME" \
    -loglevel error 2>&1

  if [[ $? -eq 0 ]]; then
    echo -e "  ${GREEN}✓${NC} ${DIM}frame ${T}s  ↳ $FRAME${NC}"
  else
    echo -e "  ${RED}✗${NC} ${DIM}frame ${T}s failed${NC}"
  fi
done
echo ""

# ── encode clips and extract frames ───────────────────────────────────────────

for CRF in "${CRFS[@]}"; do
  NAME="${PRESET}_crf${CRF}"
  CLIP="$CLIPS_DIR/${NAME}.${EXT}"

  echo -e "  ${BOLD}$NAME${NC}"

  ffmpeg -y -t "$CLIP_DURATION" -i "$INPUT" \
    -c:v "$CODEC" -crf "$CRF" $EXTRA \
    -c:a copy \
    "$CLIP" \
    -loglevel error -stats 2>&1

  if [[ $? -ne 0 ]]; then
    echo -e "  ${RED}✗ encoding failed${NC}\n"
    ((FAIL++))
    continue
  fi

  clip_size=$(du -sh "$CLIP" 2>/dev/null | cut -f1)
  echo -e "  ${GREEN}✓${NC} ${DIM}clip: $clip_size  ↳ $CLIP${NC}"

  for T in "${TIMESTAMPS[@]}"; do
    FRAME="$IMG_DIR/${T}s/${NAME}.jpg"
    ffmpeg -y -ss "$T" -i "$CLIP" \
      -frames:v 1 -q:v 2 \
      "$FRAME" \
      -loglevel error 2>&1

    if [[ $? -eq 0 ]]; then
      echo -e "  ${GREEN}✓${NC} ${DIM}frame ${T}s  ↳ $FRAME${NC}"
    else
      echo -e "  ${RED}✗${NC} ${DIM}frame ${T}s failed${NC}"
    fi
  done

  echo ""
  ((DONE++))
done

# ── summary ───────────────────────────────────────────────────────────────────

echo -e "  $(printf '─%.0s' {1..60})"
echo ""
echo -e "  ${BOLD}Results${NC}  ${#CRFS[@]} variants"
echo ""
echo -e "  ${GREEN}✓ done    ${BOLD}$DONE${NC}"
[[ $FAIL -gt 0 ]] && echo -e "  ${RED}✗ failed  ${BOLD}$FAIL${NC}"
echo -e "  ${DIM}clips:    $CLIPS_DIR${NC}"
echo -e "  ${DIM}frames:   $IMG_DIR${NC}"
echo ""