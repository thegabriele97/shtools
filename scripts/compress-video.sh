#!/bin/bash
# @description Comprime video con ffmpeg mantenendo buona qualità
# @usage compress-video <file> [crf 18-51, default 28]
# @example compress-video film.mp4 28
# @deps ffmpeg

INPUT="$1"
CRF="${2:-28}"

if [[ -z "$INPUT" ]]; then
  echo "Usage: tools compress-video <file> [crf]"
  exit 1
fi

if ! command -v ffmpeg &>/dev/null; then
  echo "✗ ffmpeg non trovato. Installalo con: brew install ffmpeg / sudo apt install ffmpeg"
  exit 1
fi

OUTPUT="${INPUT%.*}_compressed.${INPUT##*.}"
ffmpeg -i "$INPUT" -vcodec libx264 -crf "$CRF" "$OUTPUT"
echo "✓ Salvato: $OUTPUT"