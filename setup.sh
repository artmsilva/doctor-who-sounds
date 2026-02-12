#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# Doctor Who Sounds - Setup & Validation Script
# Checks your environment and validates that sound files are in place.
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/config.json"

# --- Colors & formatting ----
if [[ -t 1 ]]; then
  BOLD="\033[1m"
  DIM="\033[2m"
  RED="\033[31m"
  GREEN="\033[32m"
  YELLOW="\033[33m"
  BLUE="\033[34m"
  CYAN="\033[36m"
  RESET="\033[0m"
else
  BOLD="" DIM="" RED="" GREEN="" YELLOW="" BLUE="" CYAN="" RESET=""
fi

info()    { printf "${BLUE}[info]${RESET}  %s\n" "$*"; }
ok()      { printf "${GREEN}[ok]${RESET}    %s\n" "$*"; }
warn()    { printf "${YELLOW}[warn]${RESET}  %s\n" "$*"; }
fail()    { printf "${RED}[fail]${RESET}  %s\n" "$*"; }
section() { printf "\n${BOLD}%s${RESET}\n" "$*"; }

# ============================================================================
# 1. Platform detection
# ============================================================================
section "Platform Detection"

PLATFORM="unknown"
if [[ "$OSTYPE" == darwin* ]]; then
  PLATFORM="macos"
  ok "macOS detected"
elif grep -qi microsoft /proc/version 2>/dev/null; then
  PLATFORM="wsl"
  ok "WSL (Windows Subsystem for Linux) detected"
elif [[ "$OSTYPE" == linux* ]]; then
  PLATFORM="linux"
  ok "Linux detected"
else
  warn "Unrecognized platform: $OSTYPE"
fi

# ============================================================================
# 2. Required tools
# ============================================================================
section "Required Tools"

MISSING_TOOLS=0

for tool in jq curl; do
  if command -v "$tool" &>/dev/null; then
    ok "$tool found: $(command -v "$tool")"
  else
    fail "$tool is not installed"
    MISSING_TOOLS=$((MISSING_TOOLS + 1))
  fi
done

if [[ $MISSING_TOOLS -gt 0 ]]; then
  echo ""
  warn "Install missing tools before continuing:"
  case "$PLATFORM" in
    macos) info "  brew install jq curl" ;;
    linux|wsl) info "  sudo apt install jq curl   # Debian/Ubuntu"
               info "  sudo dnf install jq curl   # Fedora" ;;
  esac
  echo ""
  fail "Cannot continue without required tools. Exiting."
  exit 1
fi

# ============================================================================
# 3. Audio player
# ============================================================================
section "Audio Player"

AUDIO_PLAYER=""

if command -v afplay &>/dev/null; then
  AUDIO_PLAYER="afplay"
  ok "afplay found (macOS built-in)"
elif command -v paplay &>/dev/null; then
  AUDIO_PLAYER="paplay"
  ok "paplay found (PulseAudio)"
elif command -v mpv &>/dev/null; then
  AUDIO_PLAYER="mpv"
  ok "mpv found"
elif command -v aplay &>/dev/null; then
  AUDIO_PLAYER="aplay"
  ok "aplay found (ALSA)"
else
  warn "No supported audio player found."
  warn "Install one of: afplay (macOS), paplay, mpv, or aplay"
  case "$PLATFORM" in
    linux|wsl) info "  sudo apt install mpv        # recommended"
               info "  sudo apt install pulseaudio  # for paplay" ;;
  esac
fi

# ============================================================================
# 4. Read config
# ============================================================================
section "Configuration"

if [[ ! -f "$CONFIG_FILE" ]]; then
  fail "config.json not found at $CONFIG_FILE"
  exit 1
fi

ACTIVE_PACK=$(jq -r '.active_pack // empty' "$CONFIG_FILE")
if [[ -z "$ACTIVE_PACK" ]]; then
  fail "No active_pack set in config.json"
  exit 1
fi

ENABLED=$(jq -r '.enabled // false' "$CONFIG_FILE")
VOLUME=$(jq -r '.volume // 0.5' "$CONFIG_FILE")

ok "Active pack: ${ACTIVE_PACK}"
ok "Sounds enabled: ${ENABLED}"
ok "Volume: ${VOLUME}"

# Show category status
info "Category status:"
for category in greeting acknowledge complete alert; do
  status=$(jq -r ".categories.${category} // false" "$CONFIG_FILE")
  if [[ "$status" == "true" ]]; then
    printf "  ${GREEN}+${RESET} %-12s enabled\n" "$category"
  else
    printf "  ${DIM}-${RESET} %-12s ${DIM}disabled${RESET}\n" "$category"
  fi
done

# ============================================================================
# 5. Read pack manifest & validate sounds
# ============================================================================
section "Sound Files"

MANIFEST="${SCRIPT_DIR}/packs/${ACTIVE_PACK}/manifest.json"
if [[ ! -f "$MANIFEST" ]]; then
  fail "Pack manifest not found: $MANIFEST"
  exit 1
fi

PACK_NAME=$(jq -r '.name // "unknown"' "$MANIFEST")
info "Validating pack: ${PACK_NAME}"
echo ""

SOUNDS_DIR="${SCRIPT_DIR}/sounds"
mkdir -p "$SOUNDS_DIR"

TOTAL=0
FOUND=0
MISSING=0
MISSING_FILES=()
FIRST_FOUND=""

# Iterate over every category and every sound file in the manifest
for category in $(jq -r '.sounds | keys[]' "$MANIFEST"); do
  for sound_file in $(jq -r ".sounds.${category}[]" "$MANIFEST"); do
    TOTAL=$((TOTAL + 1))
    sound_path="${SOUNDS_DIR}/${sound_file}"

    if [[ -f "$sound_path" ]]; then
      FOUND=$((FOUND + 1))
      ok "[${category}] ${sound_file}"
      if [[ -z "$FIRST_FOUND" ]]; then
        FIRST_FOUND="$sound_path"
      fi
    else
      MISSING=$((MISSING + 1))
      MISSING_FILES+=("$sound_file")
      fail "[${category}] ${sound_file} -- MISSING"
    fi
  done
done

# ============================================================================
# 6. Summary
# ============================================================================
section "Summary"

echo ""
printf "  Total sounds:   %d\n" "$TOTAL"
printf "  ${GREEN}Found:          %d${RESET}\n" "$FOUND"
if [[ $MISSING -gt 0 ]]; then
  printf "  ${RED}Missing:        %d${RESET}\n" "$MISSING"
else
  printf "  Missing:        %d\n" "$MISSING"
fi
echo ""

if [[ $MISSING -eq 0 ]]; then
  ok "All sound files are present!"
else
  warn "${MISSING} sound file(s) still needed."
  echo ""
  info "Missing files:"
  for f in "${MISSING_FILES[@]}"; do
    printf "    - sounds/%s\n" "$f"
  done
fi

# ============================================================================
# 7. Download guidance for missing sounds
# ============================================================================
if [[ $MISSING -gt 0 ]]; then
  section "Where to Find Sound Effects"

  printf "${DIM}%s${RESET}\n" "--------------------------------------------------------------"
  echo "The following sites offer free Doctor Who-style sound effects."
  echo "Search for the sound name and download an MP3 file."
  echo "Place downloaded files in: ${SOUNDS_DIR}/"
  printf "${DIM}%s${RESET}\n" "--------------------------------------------------------------"
  echo ""
  echo "  1. ${BOLD}BBC Sound Effects${RESET} (bbcsfx.acropolis.org.uk)"
  echo "     Free for personal use. Search for TARDIS, Dalek, etc."
  echo ""
  echo "  2. ${BOLD}Pixabay Sound Effects${RESET} (pixabay.com/sound-effects)"
  echo "     Royalty-free. Search for 'doctor who', 'tardis', 'sci-fi'."
  echo ""
  echo "  3. ${BOLD}Orange Free Sounds${RESET} (orangefreesounds.com)"
  echo "     Free sound effects. Search for 'doctor who' or 'sci-fi'."
  echo ""
  echo "  4. ${BOLD}Freesound${RESET} (freesound.org)"
  echo "     Community-contributed sounds. Requires free account."
  echo ""

  info "File naming guide:"
  for f in "${MISSING_FILES[@]}"; do
    # Strip extension and replace hyphens with spaces for a search hint
    search_hint="${f%.mp3}"
    search_hint="${search_hint//-/ }"
    printf "    %-35s  -> search: \"%s\"\n" "sounds/${f}" "$search_hint"
  done
  echo ""
  info "After downloading, re-run this script to verify: ./setup.sh"
fi

# ============================================================================
# 8. Test playback
# ============================================================================
if [[ $FOUND -gt 0 && -n "$AUDIO_PLAYER" ]]; then
  section "Test Playback"

  FIRST_NAME=$(basename "$FIRST_FOUND")
  info "Playing test sound: ${FIRST_NAME}"

  case "$AUDIO_PLAYER" in
    afplay)
      afplay -v "$VOLUME" "$FIRST_FOUND" 2>/dev/null
      ;;
    paplay)
      paplay_vol=$(echo "$VOLUME * 65536" | bc | cut -d. -f1)
      paplay --volume="$paplay_vol" "$FIRST_FOUND" 2>/dev/null
      ;;
    mpv)
      mpv_vol=$(echo "$VOLUME * 100" | bc | cut -d. -f1)
      mpv --no-terminal --volume="$mpv_vol" "$FIRST_FOUND" 2>/dev/null
      ;;
    aplay)
      aplay -q "$FIRST_FOUND" 2>/dev/null
      ;;
  esac

  if [[ $? -eq 0 ]]; then
    ok "Playback test complete."
  else
    warn "Playback failed. Check your audio output settings."
  fi
elif [[ $FOUND -gt 0 && -z "$AUDIO_PLAYER" ]]; then
  warn "Skipping playback test -- no audio player available."
elif [[ $FOUND -eq 0 ]]; then
  info "Skipping playback test -- no sound files found yet."
fi

# ============================================================================
# Done
# ============================================================================
echo ""
if [[ $MISSING -eq 0 && -n "$AUDIO_PLAYER" ]]; then
  printf "${GREEN}${BOLD}Setup complete!${RESET} The Doctor Who Sounds plugin is ready.\n"
elif [[ $MISSING -eq 0 ]]; then
  printf "${YELLOW}${BOLD}Almost ready.${RESET} Install an audio player to enable sound playback.\n"
else
  printf "${YELLOW}${BOLD}Setup incomplete.${RESET} Add the missing sound files and re-run ./setup.sh\n"
fi
echo ""
