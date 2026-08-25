#!/usr/bin/env bash
set -Eeuo pipefail

# Generate an untuned TI default DCC profile for the Arducam B0310 / IMX708.
# This is a bring-up profile, not production tuning.
#
# Compatibility detail: SENSOR_ID=219 is intentional. The installed J722S
# tiovx sensor library does not yet expose IMX708, so the board pipeline uses
# SENSOR_SONY_IMX219_RPI only as a numeric DCC registry slot. The actual DCC
# content generated here is for IMX708 geometry/RAW10 and AE/AWB are disabled.

MODE=1536x864

usage() {
  cat >&2 <<USAGE
Usage: $0 [--mode 1536x864|2304x1296]

Default: --mode 1536x864 (OpenHD 720p60 R2 source mode)
USAGE
  exit 2
}

while (($#)); do
  case "$1" in
    --mode) MODE=${2:?missing mode}; shift 2 ;;
    -h|--help) usage ;;
    *) usage ;;
  esac
done

case "$MODE" in
  1536x864)
    SENSOR_WIDTH=1536
    SENSOR_HEIGHT=864
    ;;
  2304x1296)
    SENSOR_WIDTH=2304
    SENSOR_HEIGHT=1296
    ;;
  *) usage ;;
esac

[[ "$(uname -m)" == x86_64 ]] || {
  echo "TI's supplied dcc_gen_linux workflow is expected on an x86_64 Linux host." >&2
  exit 1
}

for cmd in git python3 find cp chmod file sha256sum; do
  command -v "$cmd" >/dev/null || { echo "Missing required host command: $cmd" >&2; exit 1; }
done

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
WORK=${WORK:-$SCRIPT_DIR/work}
OUT=${OUT:-$SCRIPT_DIR/out/$MODE}
IMAGING_DIR=${IMAGING_DIR:-$WORK/imaging}
IMAGING_REF=${IMAGING_REF:-REL.PSDK.ANALYTICS.11.02.01.02}
SENSOR_TREE="imx708_openhd_${SENSOR_WIDTH}x${SENSOR_HEIGHT}_compat219"
CONFIG_NAME="imx708_openhd_${SENSOR_WIDTH}x${SENSOR_HEIGHT}_properties.txt"

mkdir -p "$WORK" "$OUT"

if [[ ! -d "$IMAGING_DIR/.git" ]]; then
  echo "Cloning TI imaging ref $IMAGING_REF ..."
  if ! git clone --depth 1 --branch "$IMAGING_REF" \
      https://git.ti.com/git/processor-sdk/imaging.git "$IMAGING_DIR"; then
    rm -rf "$IMAGING_DIR"
    git clone --depth 1 --branch "$IMAGING_REF" \
      git://git.ti.com/processor-sdk/imaging.git "$IMAGING_DIR"
  fi
fi

GEN_DIR="$IMAGING_DIR/tools/default_DCC_profile_gen"
GEN="$GEN_DIR/scripts/ctt_def_xml_gen.py"
[[ -f "$GEN" ]] || { echo "DCC generator not found: $GEN" >&2; exit 1; }

CFG="$GEN_DIR/configs/$CONFIG_NAME"
PRJ_DIR="../../../sensor_drv/src/$SENSOR_TREE"

if grep -q 'SENSOR_WIDTH' "$GEN"; then
  cat > "$CFG" <<CFG
SENSOR_ID 219
PRJ_DIR $PRJ_DIR
SENSOR_NAME IMX708
SENSOR_DCC_NAME SENSOR_SONY_IMX708_OPENHD_COMPAT219
SENSOR_WIDTH $SENSOR_WIDTH
SENSOR_HEIGHT $SENSOR_HEIGHT
COLOR_PATTERN 0
WDR_MODE 0
BIT_DEPTH 10
WDR_BIT_DEPTH 20
WDR_KNEE_X 0,1023
WDR_KNEE_Y 0,1023
BLACK_PRE 0
BLACK_POST 64
GAMMA_PRE 0
H3A_INPUT_LSB 0
CFG
else
  cat > "$CFG" <<CFG
WIDTH $SENSOR_WIDTH
HEIGHT $SENSOR_HEIGHT
BIT_DEPTH 10
BAYER_PATTERN 0
SENSOR_ID 219
PRJ_DIR $PRJ_DIR
SENSOR_NAME IMX708
SENSOR_DCC_NAME SENSOR_SONY_IMX708_OPENHD_COMPAT219
CFG
fi

echo "Generating default DCC XMLs for ${SENSOR_WIDTH}x${SENSOR_HEIGHT}..."
(
  cd "$GEN_DIR/scripts"
  python3 ctt_def_xml_gen.py "../configs/$CONFIG_NAME"
)

SENSOR_ROOT="$IMAGING_DIR/sensor_drv/src/$SENSOR_TREE"
GEN_SH=$(find "$SENSOR_ROOT" -type f -name generate_dcc.sh | head -n1 || true)
[[ -n "$GEN_SH" && -f "$GEN_SH" ]] || {
  echo "Generator did not produce generate_dcc.sh under $SENSOR_ROOT" >&2
  exit 1
}

DCC_TOOL="$IMAGING_DIR/tools/dcc_tools/dcc_gen_linux"
if [[ -e "$DCC_TOOL" ]]; then
  echo "DCC tool: $(file "$DCC_TOOL")"
fi

chmod +x "$GEN_SH"
echo "Compiling DCC binaries..."
(
  cd "$(dirname "$GEN_SH")"
  ./generate_dcc.sh
)

VISS=$(find "$SENSOR_ROOT" -type f -name 'dcc_viss*.bin' | head -n1 || true)
A2=$(find "$SENSOR_ROOT" -type f -name 'dcc_2a*.bin' | head -n1 || true)
[[ -n "$VISS" && -s "$VISS" ]] || { echo "No generated dcc_viss*.bin found." >&2; exit 1; }
[[ -n "$A2" && -s "$A2" ]] || { echo "No generated dcc_2a*.bin found." >&2; exit 1; }

cp -f "$VISS" "$OUT/dcc_viss_${SENSOR_WIDTH}x${SENSOR_HEIGHT}.bin"
cp -f "$A2" "$OUT/dcc_2a_${SENSOR_WIDTH}x${SENSOR_HEIGHT}.bin"

cat > "$OUT/PROFILE.txt" <<META
profile=IMX708 Arducam B0310 default/untuned bring-up
width=$SENSOR_WIDTH
height=$SENSOR_HEIGHT
raw=rggb10
bit_depth=10
format_msb=9
bayer_pattern=RGGB
dcc_compat_id=219
ae_awb=disabled
imaging_ref=$IMAGING_REF
source_viss=$VISS
source_2a=$A2
META

sha256sum "$OUT/dcc_viss_${SENSOR_WIDTH}x${SENSOR_HEIGHT}.bin" \
          "$OUT/dcc_2a_${SENSOR_WIDTH}x${SENSOR_HEIGHT}.bin" | tee "$OUT/SHA256SUMS"
echo
echo "Generated files are in: $OUT"
