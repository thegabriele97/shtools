#!/bin/bash
# @description Copy EXIF metadata (dates, GPS, camera info) from originals to converted images
# @usage copy-exif <original_dir> <converted_dir>
# @example copy-exif /photos/original /photos/converted
# @deps exiftool

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# ── check deps ────────────────────────────────────────────────────────────────

if ! command -v exiftool &>/dev/null; then
  echo -e "\n  ${RED}✗ exiftool not found${NC}\n"
  echo -e "  ${CYAN}macOS${NC}          brew install exiftool"
  echo -e "  ${CYAN}Ubuntu/Debian${NC}  sudo apt install libimage-exiftool-perl\n"
  exit 1
fi

# ── args ──────────────────────────────────────────────────────────────────────

if [[ $# -lt 2 ]]; then
  echo -e "\n  ${BOLD}Usage:${NC} tools copy-exif <original_dir> <converted_dir>\n"
  exit 1
fi

ORIGINAL_DIR="${1%/}"
CONVERTED_DIR="${2%/}"

if [[ ! -d "$ORIGINAL_DIR" ]]; then
  echo -e "\n  ${RED}✗ directory not found:${NC} $ORIGINAL_DIR\n"; exit 1
fi
if [[ ! -d "$CONVERTED_DIR" ]]; then
  echo -e "\n  ${RED}✗ directory not found:${NC} $CONVERTED_DIR\n"; exit 1
fi

# ── scan ──────────────────────────────────────────────────────────────────────

mapfile -t FILES < <(find "$CONVERTED_DIR" -maxdepth 1 -type f \
  \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" \
     -o -iname "*.webp" -o -iname "*.heic" -o -iname "*.tiff" \) | sort)
TOTAL=${#FILES[@]}

if [[ $TOTAL -eq 0 ]]; then
  echo -e "\n  ${YELLOW}⚠ no image files found in:${NC} $CONVERTED_DIR\n"
  exit 0
fi

echo ""
echo -e "  ${BOLD}📅 copy-exif${NC}"
echo -e "  ${DIM}original:   $ORIGINAL_DIR${NC}"
echo -e "  ${DIM}converted:  $CONVERTED_DIR${NC}"
echo -e "  ${DIM}files:      $TOTAL${NC}"
echo ""
echo -e "  $(printf '─%.0s' {1..60})"
echo ""

OK=0
SKIP=0
FAIL=0

for conv_file in "${FILES[@]}"; do
  base=$(basename "$conv_file")
  base_noext="${base%.*}"
  original=$(find "$ORIGINAL_DIR" -maxdepth 1 -iname "${base_noext}.*" ! -iname "$base" | head -n 1)

  if [[ -z "$original" ]]; then
    echo -e "  ${YELLOW}⚠${NC}  ${BOLD}$base${NC}"
    echo -e "     ${DIM}no original found — skipped${NC}"
    echo ""
    ((SKIP++))
    continue
  fi

  exiftool -overwrite_original \
    -TagsFromFile "$original" \
    "-AllDates" \
    "-GPS:all" \
    "-EXIF:Make" "-EXIF:Model" \
    "-EXIF:LensModel" "-EXIF:LensInfo" "-EXIF:LensMake" \
    "-EXIF:ISO" "-EXIF:ExposureTime" "-EXIF:FNumber" \
    "-EXIF:FocalLength" "-EXIF:FocalLengthIn35mmFormat" \
    "-EXIF:Flash" "-EXIF:WhiteBalance" \
    "-EXIF:ExposureProgram" "-EXIF:MeteringMode" \
    "-FileModifyDate" \
    "$conv_file" -q 2>/dev/null

  if [[ $? -eq 0 ]]; then
    date=$(exiftool -s3 -DateTimeOriginal "$conv_file" 2>/dev/null)
    gps=$(exiftool -s3 -GPSPosition "$conv_file" 2>/dev/null)
    model=$(exiftool -s3 -Model "$conv_file" 2>/dev/null)

    echo -e "  ${GREEN}✓${NC}  ${BOLD}$base${NC}  ${DIM}← $(basename "$original")${NC}"
    [[ -n "$date" ]]  && echo -e "     ${DIM}📅 $date${NC}"
    [[ -n "$gps" ]]   && echo -e "     ${DIM}📍 $gps${NC}"
    [[ -n "$model" ]] && echo -e "     ${DIM}📷 $model${NC}"
    echo ""
    ((OK++))
  else
    echo -e "  ${RED}✗${NC}  ${BOLD}$base${NC}"
    echo -e "     ${DIM}exiftool failed${NC}"
    echo ""
    ((FAIL++))
  fi
done

# ── summary ───────────────────────────────────────────────────────────────────

echo -e "  $(printf '─%.0s' {1..60})"
echo ""
echo -e "  ${BOLD}Results${NC}  $TOTAL files checked"
echo ""
echo -e "  ${GREEN}✓ done      ${BOLD}$OK${NC}"
[[ $SKIP -gt 0 ]] && echo -e "  ${YELLOW}⚠ skipped   ${BOLD}$SKIP${NC}"
[[ $FAIL -gt 0 ]] && echo -e "  ${RED}✗ failed    ${BOLD}$FAIL${NC}"
echo ""