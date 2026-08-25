#!/usr/bin/env bash
set -Eeuo pipefail

# Generate an untuned TI default DCC profile for IMX415 full-array RAW10.
# This is a pre-hardware bring-up profile, not production IQ tuning.
# R0 uses DCC ID 219 only as an available registry slot; AE/AWB stay disabled.

[[ "$(uname -m)" == x86_64 ]] || {
  echo "TI's supplied dcc_gen_linux workflow is expected on an x86_64 Linux host." >&2
  exit 1
}

for cmd in git python3 find cp chmod file sha256sum; do
  command -v "$cmd" >/dev/null || { echo "Missing required host command: $cmd" >&2; exit 1; }
done

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
WORK=${WORK:-$SCRIPT_DIR/work}
OUT=${OUT:-$SCRIPT_DIR/out-imx415}
IMAGING_DIR=${IMAGING_DIR:-$WORK/imaging}
IMAGING_REF=${IMAGING_REF:-REL.PSDK.ANALYTICS.11.02.01.02}
SENSOR_TREE=imx415_openhd_compat219
CONFIG_NAME=imx415_openhd_3864x2192_properties.txt

mkdir -p "$WORK" "$OUT"

if [[ ! -d "$IMAGING_DIR/.git" ]]; then
  echo "Cloning TI imaging ref $IMAGING_REF ..."
  if ! git clone --depth 1 --branch "$IMAGING_REF" https://git.ti.com/git/processor-sdk/imaging.git "$IMAGING_DIR"; then
    rm -rf "$IMAGING_DIR"
    git clone --depth 1 --branch "$IMAGING_REF" git://git.ti.com/processor-sdk/imaging.git "$IMAGING_DIR"
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
SENSOR_NAME IMX415
SENSOR_DCC_NAME SENSOR_SONY_IMX415_OPENHD_COMPAT219
SENSOR_WIDTH 3864
SENSOR_HEIGHT 2192
COLOR_PATTERN 2
WDR_MODE 0
BIT_DEPTH 10
WDR_BIT_DEPTH 20
WDR_KNEE_X 0,1023
WDR_KNEE_Y 0,1023
BLACK_PRE 50
BLACK_POST 0
GAMMA_PRE 0
H3A_INPUT_LSB 0
CFG
else
  cat > "$CFG" <<CFG
WIDTH 3864
HEIGHT 2192
BIT_DEPTH 10
BAYER_PATTERN 2
SENSOR_ID 219
PRJ_DIR $PRJ_DIR
SENSOR_NAME IMX415
SENSOR_DCC_NAME SENSOR_SONY_IMX415_OPENHD_COMPAT219
CFG
fi

echo "Generating default DCC XMLs..."
(
  cd "$GEN_DIR/scripts"
  python3 ctt_def_xml_gen.py "../configs/$CONFIG_NAME"
)

SENSOR_ROOT="$IMAGING_DIR/sensor_drv/src/$SENSOR_TREE"
GEN_SH=$(find "$SENSOR_ROOT" -type f -name generate_dcc.sh | head -n1 || true)
[[ -n "$GEN_SH" && -f "$GEN_SH" ]] || { echo "Generator did not produce generate_dcc.sh under $SENSOR_ROOT" >&2; exit 1; }

DCC_TOOL="$IMAGING_DIR/tools/dcc_tools/dcc_gen_linux"
[[ -e "$DCC_TOOL" ]] && echo "DCC tool: $(file "$DCC_TOOL")"

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

cp -f "$VISS" "$OUT/dcc_viss_3864x2192.bin"
cp -f "$A2" "$OUT/dcc_2a_3864x2192.bin"

cat > "$OUT/PROFILE.txt" <<META
profile=IMX415 Arducam B0569 default/untuned pre-hardware bring-up
width=3864
height=2192
raw=gbrg10
bit_depth=10
format_msb=9
bayer_pattern=GBRG
black_level_10bit=50
dcc_compat_id=219
ae_awb=disabled during R0
imaging_ref=$IMAGING_REF
source_viss=$VISS
source_2a=$A2
META

sha256sum "$OUT/dcc_viss_3864x2192.bin" "$OUT/dcc_2a_3864x2192.bin" | tee "$OUT/SHA256SUMS"
echo
echo "Generated files are in: $OUT"
