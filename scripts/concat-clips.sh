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

export LC_NUMERIC=C # ensure consistent decimal point for awk across locales

# ── helpers ───────────────────────────────────────────────────────────────────

fmt_ts() {
  # formats seconds (float) as 1h2m5s / 2m5s / 47s
  echo "$1" | awk '{
    t=int($1)
    h=int(t/3600); m=int((t%3600)/60); s=t%60
    if (h>0) printf "%dh%dm%ds", h, m, s
    else if (m>0) printf "%dm%ds", m, s
    else printf "%ds", s
  }'
}

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

# ── A — inspect FPS + resolution + audio offset ───────────────────────────────

echo ""
echo -e "  $(printf '─%.0s' {1..60})"
echo ""
echo -e "  ${BOLD}A — clip inspection${NC}"
echo ""

declare -A CLIP_FPS
declare -A CLIP_RES
declare -A CLIP_AUDIO_OFFSET
ALL_FPS_SAME=true
ALL_RES_SAME=true
FIRST_FPS=""
FIRST_RES=""

for clip in "${CLIPS[@]}"; do
  name=$(basename "$clip")

  fps=$(ffprobe -v error -show_entries stream=r_frame_rate \
    -select_streams v:0 \
    -of default=noprint_wrappers=1:nokey=1 "$clip" 2>/dev/null | head -1)
  fps_display=$(echo "$fps" | awk -F'/' '{if($2==1) print $1; else printf "%.2f", $1/$2}')
  CLIP_FPS["$clip"]="$fps"

  width=$(ffprobe -v error -show_entries stream=width \
    -select_streams v:0 \
    -of default=noprint_wrappers=1:nokey=1 "$clip" 2>/dev/null)
  height=$(ffprobe -v error -show_entries stream=height \
    -select_streams v:0 \
    -of default=noprint_wrappers=1:nokey=1 "$clip" 2>/dev/null)
  res="${width}x${height}"
  CLIP_RES["$clip"]="$res"

  audio_pts=$(ffprobe -v error -show_entries stream=start_pts \
    -select_streams a:0 \
    -of default=noprint_wrappers=1:nokey=1 "$clip" 2>/dev/null)
  audio_start=$(ffprobe -v error -show_entries stream=start_time \
    -select_streams a:0 \
    -of default=noprint_wrappers=1:nokey=1 "$clip" 2>/dev/null)
  CLIP_AUDIO_OFFSET["$clip"]="$audio_pts"

  if [[ -z "$FIRST_FPS" ]]; then
    FIRST_FPS="$fps"
  elif [[ "$fps" != "$FIRST_FPS" ]]; then
    ALL_FPS_SAME=false
  fi

  if [[ -z "$FIRST_RES" ]]; then
    FIRST_RES="$res"
  elif [[ "$res" != "$FIRST_RES" ]]; then
    ALL_RES_SAME=false
  fi

  # fps color
  denom=$(echo "$fps" | cut -d'/' -f2)
  if [[ "$denom" != "1" && "$denom" != "" ]]; then
    fps_label="${YELLOW}fps: $fps_display ($fps)${NC}"
  else
    fps_label="${GREEN}fps: $fps_display${NC}"
  fi

  # resolution color (compare against first seen)
  if [[ "$res" == "$FIRST_RES" ]]; then
    res_label="${GREEN}res: $res${NC}"
  else
    res_label="${YELLOW}res: $res${NC}"
  fi

  # audio offset color
  if [[ "$audio_pts" == "0" || -z "$audio_pts" ]]; then
    offset_label="${GREEN}audio start_pts: ${audio_pts:-0}${NC}"
  else
    offset_label="${YELLOW}audio start_pts: $audio_pts (${audio_start}s)${NC}"
  fi

  echo -e "  ${BOLD}$name${NC}"
  echo -e "    ${fps_label}   ${res_label}   ${offset_label}"
  echo ""
done

# summary
NEED_CLEAN=false

if [[ "$ALL_FPS_SAME" == true ]]; then
  fps_display=$(echo "$FIRST_FPS" | awk -F'/' '{if($2==1) print $1; else printf "%.2f", $1/$2}')
  echo -e "  ${GREEN}✓ FPS uniform ($fps_display)${NC}"
else
  echo -e "  ${YELLOW}⚠ FPS non-uniform — normalization needed${NC}"
  NEED_CLEAN=true
fi

# check irregular framerates
for clip in "${CLIPS[@]}"; do
  fps="${CLIP_FPS[$clip]}"
  denom=$(echo "$fps" | cut -d'/' -f2)
  if [[ "$denom" != "1" && "$denom" != "" ]]; then
    NEED_CLEAN=true
    break
  fi
done

if [[ "$ALL_RES_SAME" == true ]]; then
  echo -e "  ${GREEN}✓ resolution uniform ($FIRST_RES)${NC}"
else
  echo -e "  ${YELLOW}⚠ resolution non-uniform — normalization needed${NC}"
  NEED_CLEAN=true
fi

echo ""

if [[ "$NEED_CLEAN" == true ]]; then
  # target FPS = most common
  TARGET_FPS=$(for clip in "${CLIPS[@]}"; do
    echo "${CLIP_FPS[$clip]}" | awk -F'/' '{if($2==1) print $1; else printf "%.0f", $1/$2}'
  done | sort | uniq -c | sort -rn | head -1 | awk '{print $2}')

  # target resolution = most common
  TARGET_RES=$(for clip in "${CLIPS[@]}"; do
    echo "${CLIP_RES[$clip]}"
  done | sort | uniq -c | sort -rn | head -1 | awk '{print $2}')
  TARGET_W=$(echo "$TARGET_RES" | cut -d'x' -f1)
  TARGET_H=$(echo "$TARGET_RES" | cut -d'x' -f2)

  echo -e "  ${DIM}target fps:        ${TARGET_FPS}${NC}"
  echo -e "  ${DIM}target resolution: ${TARGET_RES}${NC}"
  echo ""
  read -e -p "  $(printf "\033[0;36m")normalize all clips to ${TARGET_FPS}fps / ${TARGET_RES}? [y/N]$(printf "\033[0m") " confirm
  if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
    echo -e "\n  ${YELLOW}skipping normalization — concat may produce issues${NC}\n"
    NEED_CLEAN=false
  fi
fi

# ── B — normalize ─────────────────────────────────────────────────────────────

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
      -vf "scale=${TARGET_W}:${TARGET_H}:flags=lanczos" \
      -c:v libx264 -crf 1 -preset medium \
      -r "$TARGET_FPS" -vsync cfr \
      -c:a aac -b:a 192k \
      -af aresample=async=1000 \
      "$out" \
      -loglevel error -stats 2>&1

    if [[ $? -eq 0 ]]; then
      fps_out=$(ffprobe -v error -show_entries stream=r_frame_rate \
        -select_streams v:0 \
        -of default=noprint_wrappers=1:nokey=1 "$out" 2>/dev/null | head -1)
      fps_display=$(echo "$fps_out" | awk -F'/' '{if($2==1) print $1; else printf "%.2f", $1/$2}')
      res_out=$(ffprobe -v error -show_entries stream=width,height \
        -select_streams v:0 \
        -of default=noprint_wrappers=1:nokey=1 "$out" 2>/dev/null \
        | tr '\n' 'x' | sed 's/x$//')
      echo -e "  ${GREEN}✓${NC} ${DIM}fps: $fps_display  res: $res_out  ↳ $out${NC}"
      CLEAN_CLIPS+=("$out")
    else
      echo -e "  ${RED}✗ failed${NC}"
    fi
    echo ""
  done

  SOURCE_CLIPS=("${CLEAN_CLIPS[@]}")
fi

# ── C — concat ────────────────────────────────────────────────────────────────

echo ""
echo -e "  $(printf '─%.0s' {1..60})"
echo ""
echo -e "  ${BOLD}C — concat${NC}"
echo ""

N=${#SOURCE_CLIPS[@]}

INPUTS=()
FILTER=""
for i in "${!SOURCE_CLIPS[@]}"; do
  INPUTS+=(-i "${SOURCE_CLIPS[$i]}")
  FILTER+="[${i}:v][${i}:a]"
done
FILTER+="concat=n=${N}:v=1:a=1[v][a]"

ffmpeg -y \
  "${INPUTS[@]}" \
  -filter_complex "$FILTER" \
  -map "[v]" -map "[a]" \
  -c:v libx264 -crf 10 -preset slow \
  -c:a aac -b:a 192k \
  -movflags +faststart \
  "$OUTPUT_FILE" \
  -loglevel error -stats 2>&1

if [[ $? -ne 0 ]]; then
  echo -e "\n  ${RED}✗ concat failed${NC}\n"
  exit 1
fi

# ── D — metadata verification ─────────────────────────────────────────────────

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

DUR_DIFF=$(echo "$VIDEO_DUR $AUDIO_DUR" | awk '{d=$1-$2; if(d<0)d=-d; printf "%.2f", d}')
DUR_OK=$(echo "$DUR_DIFF" | awk '{print ($1 < 1.0) ? "yes" : "no"}')

echo -e "  ${DIM}file:        $OUTPUT_FILE${NC}"
echo -e "  ${DIM}size:        $SIZE${NC}"
echo -e "  ${DIM}codec:       $CODEC_OUT${NC}"
echo -e "  ${DIM}resolution:  $RESOLUTION${NC}"
echo -e "  ${DIM}fps:         $fps_display${NC}"
echo -e "  ${DIM}video dur:   $(fmt_ts "$VIDEO_DUR")${NC}"
echo -e "  ${DIM}audio dur:   $(fmt_ts "$AUDIO_DUR")${NC}"

if [[ "$DUR_OK" == "yes" ]]; then
  echo -e "  ${GREEN}✓${NC} ${DIM}a/v diff:    ${DUR_DIFF}s — ok${NC}"
else
  echo -e "  ${RED}✗${NC} ${DIM}a/v diff:    ${DUR_DIFF}s — audio and video are out of sync${NC}"
fi

# ── E — clip-by-clip sync verification ───────────────────────────────────────

echo ""
echo -e "  $(printf '─%.0s' {1..60})"
echo ""
echo -e "  ${BOLD}E — clip sync verification${NC}"
echo ""

TMPDIR_VERIFY=$(mktemp -d /tmp/verify_concat_XXXXXX)
trap "rm -rf $TMPDIR_VERIFY" EXIT

OFFSET=0
ALL_SYNC_OK=true

for i in "${!SOURCE_CLIPS[@]}"; do
  clip="${SOURCE_CLIPS[$i]}"
  name=$(basename "$clip")

  echo -e "  ${BOLD}clip $((i+1)) — $name${NC}"

  dur=$(ffprobe -v error -show_entries format=duration \
    -of default=noprint_wrappers=1:nokey=1 "$clip" 2>/dev/null)

  if [[ -z "$dur" || "$dur" == "N/A" ]]; then
    echo -e "  ${YELLOW}⚠ could not read duration, skipping${NC}"
    echo ""
    continue
  fi

  # random timestamp between 50% and 90% of clip duration
  T=$(echo "$dur" | awk '{srand(); min=$1*0.50; max=$1*0.90; printf "%.2f", min+rand()*(max-min)}')
  T_MID=$(echo "$T" | awk '{printf "%.2f", $1+2.5}')
  T_OUT=$(echo "$OFFSET $T" | awk '{printf "%.2f", $1+$2}')
  T_OUT_MID=$(echo "$T_OUT" | awk '{printf "%.2f", $1+2.5}')

  echo -e "  ${DIM}clip timestamp:    $(fmt_ts "$T")  (midpoint: $(fmt_ts "$T_MID"))${NC}"
  echo -e "  ${DIM}output timestamp:  $(fmt_ts "$T_OUT")  (midpoint: $(fmt_ts "$T_OUT_MID"))${NC}"

  # extract audio segments
  SRC_WAV="$TMPDIR_VERIFY/src_${i}.wav"
  OUT_WAV="$TMPDIR_VERIFY/out_${i}.wav"

  ffmpeg -y -ss "$T" -t 5 -i "$clip" \
    -vn -acodec pcm_s16le -ar 44100 -ac 1 \
    "$SRC_WAV" -loglevel error 2>&1

  ffmpeg -y -ss "$T_OUT" -t 5 -i "$OUTPUT_FILE" \
    -vn -acodec pcm_s16le -ar 44100 -ac 1 \
    "$OUT_WAV" -loglevel error 2>&1

  # audio RMS diff
  RMS_SRC=$(ffmpeg -i "$SRC_WAV" -af astats -f null - 2>&1 \
    | grep "RMS level" | head -1 | awk '{print $NF}')
  RMS_OUT=$(ffmpeg -i "$OUT_WAV" -af astats -f null - 2>&1 \
    | grep "RMS level" | head -1 | awk '{print $NF}')

  AUDIO_DIFF=$(echo "$RMS_SRC $RMS_OUT" | awk '{d=$1-$2; if(d<0)d=-d; printf "%.2f", d}')
  AUDIO_OK=$(echo "$AUDIO_DIFF" | awk '{print ($1 < 2.0) ? "yes" : "no"}')

  if [[ "$AUDIO_OK" == "yes" ]]; then
    echo -e "  ${GREEN}✓${NC} ${DIM}audio RMS diff: ${AUDIO_DIFF} dB — ok${NC}"
  else
    echo -e "  ${RED}✗${NC} ${DIM}audio RMS diff: ${AUDIO_DIFF} dB — mismatch${NC}"
    ALL_SYNC_OK=false
  fi

  # extract video frames at midpoint
  SRC_FRAME="$TMPDIR_VERIFY/src_${i}.png"
  OUT_FRAME="$TMPDIR_VERIFY/out_${i}.png"

  ffmpeg -y -ss "$T_MID" -i "$clip" \
    -frames:v 1 "$SRC_FRAME" -loglevel error 2>&1

  ffmpeg -y -ss "$T_OUT_MID" -i "$OUTPUT_FILE" \
    -frames:v 1 "$OUT_FRAME" -loglevel error 2>&1

  # video SSIM
  SSIM=$(ffmpeg -y \
    -i "$SRC_FRAME" -i "$OUT_FRAME" \
    -filter_complex "[0:v][1:v]ssim" \
    -f null - 2>&1 | grep "SSIM" | grep -oP 'All:\K[0-9.]+')

  # fallback: scale both to same resolution first
  if [[ -z "$SSIM" ]]; then
    SSIM=$(ffmpeg -y \
      -i "$SRC_FRAME" -i "$OUT_FRAME" \
      -filter_complex "[0:v]scale=1280:720[a];[1:v]scale=1280:720[b];[a][b]ssim" \
      -f null - 2>&1 | grep "SSIM" | grep -oP 'All:\K[0-9.]+')
  fi

  SSIM_OK=$(echo "$SSIM" | awk '{print ($1 >= 0.80) ? "yes" : "no"}')

  if [[ "$SSIM_OK" == "yes" ]]; then
    echo -e "  ${GREEN}✓${NC} ${DIM}video SSIM:     ${SSIM} — ok${NC}"
  else
    echo -e "  ${RED}✗${NC} ${DIM}video SSIM:     ${SSIM:-N/A} — mismatch${NC}"
    ALL_SYNC_OK=false
  fi

  # ── extract compare clips on any failure ─────────────────────────────────

  if [[ "$AUDIO_OK" != "yes" || "$SSIM_OK" != "yes" ]]; then
    COMPARE_DIR="$(dirname "$OUTPUT_FILE")/compare"
    mkdir -p "$COMPARE_DIR"

    stem="${name%.*}"
    T_LABEL=$(fmt_ts "$T")
    T_OUT_LABEL=$(fmt_ts "$T_OUT")

    SRC_CMP="$COMPARE_DIR/clip$((i+1))_${stem}_src_${T_LABEL}.mp4"
    OUT_CMP="$COMPARE_DIR/clip$((i+1))_${stem}_out_${T_OUT_LABEL}.mp4"

    ffmpeg -y -ss "$T" -t 5 -i "$clip" \
      -c copy "$SRC_CMP" -loglevel error 2>&1

    ffmpeg -y -ss "$T_OUT" -t 5 -i "$OUTPUT_FILE" \
      -c copy "$OUT_CMP" -loglevel error 2>&1

    echo ""
    echo -e "  ${YELLOW}↳ compare clips saved:${NC}"
    echo -e "    ${DIM}src: $SRC_CMP${NC}"
    echo -e "    ${DIM}out: $OUT_CMP${NC}"
  fi

  echo ""

  OFFSET=$(echo "$OFFSET $dur" | awk '{printf "%.2f", $1+$2}')
done

# ── summary ───────────────────────────────────────────────────────────────────

echo -e "  $(printf '─%.0s' {1..60})"
echo ""
if [[ "$ALL_SYNC_OK" == "true" ]]; then
  echo -e "  ${GREEN}✓ all clips verified — output looks correct${NC}"
else
  echo -e "  ${RED}✗ some clips failed verification — check output manually${NC}"
fi

echo ""
echo -e "  ${GREEN}✓ done:${NC} $OUTPUT_FILE"
echo ""
