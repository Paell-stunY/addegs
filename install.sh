#!/bin/bash

# ============================================================
#   AUTO UPLOAD EGG - Pterodactyl Panel
#   Taruh script ini se-folder sama folder "egg/"
# ============================================================

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

# ─── INPUT INTERAKTIF ────────────────────────────────────────
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

# Folder egg relatif ke lokasi script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EGG_PATH="$SCRIPT_DIR/egg"

echo ""
echo -e "${DIM}────────────────────────────────────────────${NC}"
echo -e "    Panel URL  : ${PANEL_URL}"
echo -e "    API Key    : ${API_KEY:0:10}**********"
echo -e "    Nest ID    : ${NEST_ID}"
echo -e "    Folder egg : ${EGG_PATH}"
echo -e "${DIM}────────────────────────────────────────────${NC}\n"

read -rp "$(echo -e "${YELLOW}Lanjut upload? (y/n): ${NC}")" CONFIRM
[[ ! "$CONFIRM" =~ ^[Yy]$ ]] && echo -e "${RED}Dibatalkan.${NC}" && exit 0

echo ""

# ─── CEK FOLDER EGG ──────────────────────────────────────────
if [[ ! -d "$EGG_PATH" ]]; then
  echo -e "${RED}[✗] Folder 'egg/' tidak ditemukan di ${SCRIPT_DIR}"
  echo -e "    Pastiin struktur foldernya:${NC}"
  echo -e "    ${DIM}."
  echo -e "    ├── auto_upload_eggs.sh"
  echo -e "    └── egg/"
  echo -e "        ├── egg-satu.json"
  echo -e "        └── egg-dua.json${NC}"
  exit 1
fi

mapfile -t EGG_FILES < <(find "$EGG_PATH" -maxdepth 2 -name "*.json" | sort)
TOTAL=${#EGG_FILES[@]}

if [[ $TOTAL -eq 0 ]]; then
  echo -e "${RED}[✗] Tidak ada file .json di folder egg/${NC}"
  exit 1
fi

echo -e "${GREEN}[✓] Ditemukan ${BOLD}${TOTAL}${NC}${GREEN} file egg${NC}\n"

# ─── CEK KONEKSI KE PANEL ────────────────────────────────────
echo -e "${YELLOW}[*] Mengecek koneksi ke panel...${NC}"
HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
  -H "Authorization: Bearer $API_KEY" \
  -H "Accept: application/json" \
  "${PANEL_URL}/api/application/nests/${NEST_ID}/eggs")

if [[ "$HTTP_STATUS" != "200" ]]; then
  echo -e "${RED}[✗] Gagal konek ke panel (HTTP $HTTP_STATUS)"
  echo -e "    Cek lagi URL, API Key, dan Nest ID lo!${NC}"
  exit 1
fi
echo -e "${GREEN}[✓] Koneksi berhasil!${NC}\n"

# ─── AMBIL EGG EXISTING ──────────────────────────────────────
EXISTING_NAMES=$(curl -s \
  -H "Authorization: Bearer $API_KEY" \
  -H "Accept: application/json" \
  "${PANEL_URL}/api/application/nests/${NEST_ID}/eggs" \
  | jq -r '.data[].attributes.name' 2>/dev/null)

# ─── UPLOAD ──────────────────────────────────────────────────
SUCCESS=0; FAILED=0; SKIPPED=0

echo -e "${CYAN}${BOLD}[*] Mulai upload...${NC}"
echo -e "${DIM}────────────────────────────────────────────${NC}"

for EGG_FILE in "${EGG_FILES[@]}"; do
  FILENAME=$(basename "$EGG_FILE")

  if ! jq empty "$EGG_FILE" 2>/dev/null; then
    echo -e "  ${YELLOW}[~] SKIP${NC} $FILENAME ${DIM}(JSON tidak valid)${NC}"
    ((SKIPPED++)); continue
  fi

  EGG_NAME=$(jq -r '.name // empty' "$EGG_FILE")
  META_VER=$(jq -r '.meta.version // "PTDL_v1"' "$EGG_FILE")

  if [[ -z "$EGG_NAME" ]]; then
    echo -e "  ${YELLOW}[~] SKIP${NC} $FILENAME ${DIM}(nama egg tidak ditemukan)${NC}"
    ((SKIPPED++)); continue
  fi

  if echo "$EXISTING_NAMES" | grep -qFx "$EGG_NAME"; then
    echo -e "  ${YELLOW}[~] SKIP${NC} '${EGG_NAME}' ${DIM}(sudah ada)${NC}"
    ((SKIPPED++)); continue
  fi

  echo -ne "  ${CYAN}[↑]${NC} '${BOLD}${EGG_NAME}${NC}' ${DIM}[${META_VER}]${NC}... "

  RESPONSE=$(curl -s -w "\n%{http_code}" -X POST \
    -H "Authorization: Bearer $API_KEY" \
    -H "Accept: application/json" \
    -F "import_file=@${EGG_FILE};type=application/json" \
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
