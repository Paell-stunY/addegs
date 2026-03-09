#!/bin/bash

# ============================================================
#   AUTO UPLOAD EGG - Pterodactyl Panel
#   Egg source: github.com/Paell-stunY/addegs
# ============================================================

GITHUB_API="https://api.github.com/repos/Paell-stunY/addegs/contents/egg"
GITHUB_RAW="https://raw.githubusercontent.com/Paell-stunY/addegs/main/egg"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

clear
echo -e "${CYAN}${BOLD}"
echo "╔══════════════════════════════════════════╗"
echo "║      AUTO UPLOAD EGG - PTERODACTYL      ║"
echo "║    Source: github.com/Paell-stunY/addegs ║"
echo "╚══════════════════════════════════════════╝"
echo -e "${NC}"

# ─── CEK DEPENDENCIES ────────────────────────────────────────
for dep in curl jq; do
  if ! command -v $dep &> /dev/null; then
    echo -e "${RED}[✗] '$dep' tidak ditemukan. Install: sudo apt install $dep${NC}"
    exit 1
  fi
done
echo -e "${GREEN}[✓] Dependencies OK${NC}\n"

# ─── INPUT ───────────────────────────────────────────────────
echo -e "${CYAN}${BOLD}[?] Masukkan konfigurasi panel:${NC}"
echo -e "${DIM}────────────────────────────────────────────${NC}"

while true; do
  read -rp "$(echo -e "    ${BOLD}Panel URL${NC} (contoh: https://panel.domain.com): ")" PANEL_URL
  PANEL_URL="${PANEL_URL%/}"
  [[ "$PANEL_URL" =~ ^https?:// ]] && break
  echo -e "  ${RED}[!] URL tidak valid${NC}"
done

while true; do
  read -rp "$(echo -e "    ${BOLD}API Key${NC} (ptla_...): ")" API_KEY
  [[ "$API_KEY" =~ ^ptla_ ]] && break
  echo -e "  ${RED}[!] API Key harus diawali 'ptla_'${NC}"
done

while true; do
  read -rp "$(echo -e "    ${BOLD}Nest ID${NC} [default: 1]: ")" NEST_ID
  NEST_ID="${NEST_ID:-1}"
  [[ "$NEST_ID" =~ ^[0-9]+$ ]] && break
  echo -e "  ${RED}[!] Nest ID harus angka${NC}"
done

echo ""
echo -e "${DIM}────────────────────────────────────────────${NC}"
echo -e "    Panel URL  : ${PANEL_URL}"
echo -e "    API Key    : ${API_KEY:0:10}**********"
echo -e "    Nest ID    : ${NEST_ID}"
echo -e "    Egg Source : github.com/Paell-stunY/addegs/egg"
echo -e "${DIM}────────────────────────────────────────────${NC}\n"

read -rp "$(echo -e "${YELLOW}Lanjut upload? (y/n): ${NC}")" CONFIRM
[[ ! "$CONFIRM" =~ ^[Yy]$ ]] && echo -e "${RED}Dibatalkan.${NC}" && exit 0

echo ""
TEMP_DIR=$(mktemp -d)
SUCCESS=0; FAILED=0; SKIPPED=0

# ─── AMBIL DAFTAR EGG DARI GITHUB ────────────────────────────
echo -e "${YELLOW}[*] Mengambil daftar egg dari GitHub...${NC}"
GITHUB_LISTING=$(curl -s "$GITHUB_API")

if echo "$GITHUB_LISTING" | jq -e 'type == "array"' &>/dev/null; then
  mapfile -t EGG_NAMES < <(echo "$GITHUB_LISTING" | jq -r '.[] | select(.name | endswith(".json")) | .name')
else
  echo -e "${RED}[✗] Gagal ambil daftar egg dari GitHub!"
  echo -e "    Cek koneksi internet atau repo mungkin private.${NC}"
  rm -rf "$TEMP_DIR"
  exit 1
fi

TOTAL=${#EGG_NAMES[@]}
if [[ $TOTAL -eq 0 ]]; then
  echo -e "${RED}[✗] Tidak ada file .json ditemukan di repo!${NC}"
  rm -rf "$TEMP_DIR"
  exit 1
fi

echo -e "${GREEN}[✓] Ditemukan ${BOLD}${TOTAL}${NC}${GREEN} file egg di GitHub${NC}\n"

# ─── CEK KONEKSI KE PANEL ────────────────────────────────────
echo -e "${YELLOW}[*] Mengecek koneksi ke panel...${NC}"
HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
  -H "Authorization: Bearer $API_KEY" \
  -H "Accept: application/json" \
  "${PANEL_URL}/api/application/nests/${NEST_ID}/eggs")

if [[ "$HTTP_STATUS" != "200" ]]; then
  echo -e "${RED}[✗] Gagal konek ke panel (HTTP $HTTP_STATUS)"
  echo -e "    Cek lagi URL, API Key, dan Nest ID!${NC}"
  rm -rf "$TEMP_DIR"
  exit 1
fi
echo -e "${GREEN}[✓] Koneksi ke panel berhasil!${NC}\n"

# ─── AMBIL EGG EXISTING ──────────────────────────────────────
EXISTING_NAMES=$(curl -s \
  -H "Authorization: Bearer $API_KEY" \
  -H "Accept: application/json" \
  "${PANEL_URL}/api/application/nests/${NEST_ID}/eggs" \
  | jq -r '.data[].attributes.name' 2>/dev/null)

# ─── DOWNLOAD & UPLOAD ───────────────────────────────────────
echo -e "${CYAN}${BOLD}[*] Mulai download & upload...${NC}"
echo -e "${DIM}────────────────────────────────────────────${NC}"

for EGG_NAME in "${EGG_NAMES[@]}"; do
  # Download egg dari GitHub
  RAW_URL="${GITHUB_RAW}/${EGG_NAME}"
  TMP_FILE="${TEMP_DIR}/${EGG_NAME}"

  curl -s "$RAW_URL" -o "$TMP_FILE"

  # Validasi JSON
  if ! jq empty "$TMP_FILE" 2>/dev/null; then
    echo -e "  ${YELLOW}[~] SKIP${NC} $EGG_NAME ${DIM}(JSON tidak valid)${NC}"
    ((SKIPPED++)); continue
  fi

  NAME=$(jq -r '.name // empty' "$TMP_FILE")
  META_VER=$(jq -r '.meta.version // "PTDL_v1"' "$TMP_FILE")

  if [[ -z "$NAME" ]]; then
    echo -e "  ${YELLOW}[~] SKIP${NC} $EGG_NAME ${DIM}(nama egg tidak ditemukan)${NC}"
    ((SKIPPED++)); continue
  fi

  # Cek duplikat
  if echo "$EXISTING_NAMES" | grep -qFx "$NAME"; then
    echo -e "  ${YELLOW}[~] SKIP${NC} '${NAME}' ${DIM}(sudah ada di panel)${NC}"
    ((SKIPPED++)); continue
  fi

  echo -ne "  ${CYAN}[↑]${NC} '${BOLD}${NAME}${NC}' ${DIM}[${META_VER}]${NC}... "

  RESPONSE=$(curl -s -w "\n%{http_code}" -X POST \
    -H "Authorization: Bearer $API_KEY" \
    -H "Accept: application/json" \
    -F "import_file=@${TMP_FILE};type=application/json" \
    "${PANEL_URL}/api/application/nests/${NEST_ID}/eggs/import")

  HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
  BODY=$(echo "$RESPONSE" | head -n -1)

  if [[ "$HTTP_CODE" == "200" || "$HTTP_CODE" == "201" ]]; then
    echo -e "${GREEN}✓ Berhasil!${NC}"
    ((SUCCESS++))
  else
    ERR=$(echo "$BODY" | jq -r '.errors[0].detail // .message // "Unknown error"' 2>/dev/null)
    echo -e "${RED}✗ Gagal (HTTP $HTTP_CODE: $ERR)${NC}"
    ((FAILED++))
  fi
done

rm -rf "$TEMP_DIR"

# ─── SUMMARY ─────────────────────────────────────────────────
echo ""
echo -e "${CYAN}${BOLD}"
echo "╔══════════════════════════════════════════╗"
echo "║                 SUMMARY                 ║"
echo "╠══════════════════════════════════════════╣"
printf "║  Total    : %-29s║\n" "$TOTAL egg"
printf "║  Berhasil : %-29s║\n" "$SUCCESS egg"
printf "║  Gagal    : %-29s║\n" "$FAILED egg"
printf "║  Dilewati : %-29s║\n" "$SKIPPED egg"
echo "╚══════════════════════════════════════════╝"
echo -e "${NC}"

[[ $FAILED -gt 0 ]] && exit 1 || exit 0
