#!/bin/bash
# @description Upload a file or folder to a Nextcloud public share via WebDAV
# @usage nextcloud-upload <url> <local_path>
# @example nextcloud-upload https://cloud.example.com/s/abc123 /photos/trip
# @deps curl

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# ── check deps ────────────────────────────────────────────────────────────────

if ! command -v curl &>/dev/null; then
  echo -e "\n  ${RED}✗ curl not found${NC}\n"
  echo -e "  ${CYAN}macOS${NC}          brew install curl"
  echo -e "  ${CYAN}Ubuntu/Debian${NC}  sudo apt install curl\n"
  exit 1
fi

# ── args ──────────────────────────────────────────────────────────────────────

if [[ $# -lt 2 ]]; then
  echo -e "\n  ${BOLD}Usage:${NC} tools nextcloud-upload <url> <local_path>\n"
  echo -e "  ${DIM}url is the public share URL (e.g. https://cloud.example.com/s/abc123)${NC}\n"
  exit 1
fi

SHARE_URL="${1%/}"
LOCAL_PATH="${2%/}"

if [[ ! -e "$LOCAL_PATH" ]]; then
  echo -e "\n  ${RED}✗ path not found:${NC} $LOCAL_PATH\n"; exit 1
fi

# ── extract token and build webdav base ───────────────────────────────────────

TOKEN=$(echo "$SHARE_URL" | sed 's|.*/s/||; s|/.*||')
if [[ -z "$TOKEN" ]]; then
  echo -e "\n  ${RED}✗ could not extract share token from URL${NC}\n"
  echo -e "  ${DIM}expected format: https://cloud.example.com/s/abc123${NC}\n"
  exit 1
fi

INSTANCE=$(echo "$SHARE_URL" | sed 's|\(https\?://[^/]*\).*|\1|')
WEBDAV_BASE="$INSTANCE/public.php/dav/files/$TOKEN"

# ── check if share is password protected ─────────────────────────────────────

echo ""
echo -e "  ${DIM}checking share...${NC}"

HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
  -u "anonymous:" \
  -X HEAD "$WEBDAV_BASE/" 2>/dev/null)

PASS=""
if [[ "$HTTP_CODE" == "401" ]]; then
  echo -e "  ${YELLOW}🔒 share is password protected${NC}"
  echo ""
  read -s -p "  $(printf "\033[0;36m")password$(printf "\033[0m"): " PASS
  echo ""

  # verify password
  HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
    -u "anonymous:$PASS" \
    -X HEAD "$WEBDAV_BASE/" 2>/dev/null)

  if [[ "$HTTP_CODE" == "401" ]]; then
    echo -e "\n  ${RED}✗ wrong password${NC}\n"; exit 1
  fi
elif [[ "$HTTP_CODE" != "200" && "$HTTP_CODE" != "405" && "$HTTP_CODE" != "207" ]]; then
  echo -e "\n  ${RED}✗ could not reach share (HTTP $HTTP_CODE)${NC}\n"; exit 1
fi

CREDS="anonymous:$PASS"

# ── collect files to upload ───────────────────────────────────────────────────

if [[ -f "$LOCAL_PATH" ]]; then
  mapfile -t FILES <<< "$LOCAL_PATH"
  BASE_DIR=$(dirname "$LOCAL_PATH")
  IS_SINGLE=true
else
  mapfile -t FILES < <(find "$LOCAL_PATH" -type f | sort)
  BASE_DIR="$LOCAL_PATH"
  IS_SINGLE=false
fi

TOTAL=${#FILES[@]}

echo ""
echo -e "  ${BOLD}☁  nextcloud-upload${NC}"
echo -e "  ${DIM}share:   $SHARE_URL${NC}"
echo -e "  ${DIM}upload:  $LOCAL_PATH${NC}"
echo -e "  ${DIM}files:   $TOTAL${NC}"
echo ""
echo -e "  $(printf '─%.0s' {1..60})"
echo ""

OK=0
FAIL=0

upload_file() {
  local file="$1"
  local name

  if [[ "$IS_SINGLE" == true ]]; then
    name=$(basename "$file")
  else
    name="${file#$BASE_DIR/}"
  fi

  # create parent directories if needed (for folder uploads)
  if [[ "$IS_SINGLE" == false ]]; then
    local dir
    dir=$(dirname "$name")
    if [[ "$dir" != "." ]]; then
      local parts=()
      IFS='/' read -ra parts <<< "$dir"
      local built=""
      for part in "${parts[@]}"; do
        built="${built:+$built/}$part"
        curl -s -o /dev/null \
          -u "$CREDS" \
          -X MKCOL "$WEBDAV_BASE/$built" 2>/dev/null
      done
    fi
  fi

  local http_code
  http_code=$(curl -s -o /dev/null -w "%{http_code}" \
    -u "$CREDS" \
    -T "$file" \
    "$WEBDAV_BASE/$name" 2>/dev/null)

  if [[ "$http_code" == "201" || "$http_code" == "204" ]]; then
    local size
    size=$(du -sh "$file" 2>/dev/null | cut -f1)
    echo -e "  ${GREEN}✓${NC}  ${BOLD}$name${NC}  ${DIM}$size${NC}"
    ((OK++))
  else
    echo -e "  ${RED}✗${NC}  ${BOLD}$name${NC}  ${DIM}HTTP $http_code${NC}"
    ((FAIL++))
  fi
}

for file in "${FILES[@]}"; do
  upload_file "$file"
done

# ── summary ───────────────────────────────────────────────────────────────────

echo ""
echo -e "  $(printf '─%.0s' {1..60})"
echo ""
echo -e "  ${BOLD}Results${NC}  $TOTAL files"
echo ""
echo -e "  ${GREEN}✓ uploaded  ${BOLD}$OK${NC}"
[[ $FAIL -gt 0 ]] && echo -e "  ${RED}✗ failed    ${BOLD}$FAIL${NC}"
echo ""