#!/usr/bin/env bash
set -Eeuo pipefail

usage()
{
    echo "Usage: $0 <TI-PSDK-RTOS-root> <output-staging-dir>" >&2
    echo "Required environment: PSDK_TOOLS_PATH" >&2
}

[[ $# -eq 2 ]] || { usage; exit 2; }
[[ -n ${PSDK_TOOLS_PATH:-} ]] || { echo 'ERROR: PSDK_TOOLS_PATH is not set' >&2; exit 1; }

SDK_ROOT="$(cd "$1" && pwd)"
OUT="$2"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
BUILD_SCRIPT="$SCRIPT_DIR/build-j722s-r2.sh"
MANIFEST="$REPO_ROOT/firmware/manifests/j722s-r2.env"
MCU="$SDK_ROOT/vision_apps/platform/j722s/rtos/mcu2_0"
INC="$MCU/concerto_mcu2_0_inc.mak"
DRIVERS="$MCU/generated/ti_drivers_config_openhd.c"
POWER="$MCU/generated/ti_power_clock_config_openhd.c"
MAIN="$MCU/main.c"

for file in "$BUILD_SCRIPT" "$MANIFEST" "$INC" "$DRIVERS" "$POWER" "$MAIN"; do
    [[ -s "$file" ]] || { echo "ERROR: missing source-build input: $file" >&2; exit 1; }
done

grep -q 'generated/ti_drivers_config_openhd\.c' "$INC" || { echo 'ERROR: qualified R5 driver compiler basename is not active' >&2; exit 1; }
grep -q 'generated/ti_power_clock_config_openhd\.c' "$INC" || { echo 'ERROR: qualified R5 power/clock compiler basename is not active' >&2; exit 1; }

# The deployed/qualified load image contains 42 OHDBG markers. Four additional
# F00-F03 source markers may remain J7DBG in an experiment tree because that
# branch is compiled out by the R2 configuration. A clean reconstruction via
# apply-j722s-r2.sh normalizes all markers to OHDBG.
ohdbg_count=$(grep -ho 'OHDBG' "$MAIN" "$DRIVERS" "$POWER" | wc -l)
[[ $ohdbg_count -ge 42 ]] || { echo "ERROR: expected at least 42 qualified OHDBG R5 markers, got $ohdbg_count" >&2; exit 1; }

unexpected_j7=$(
    grep -h 'J7DBG' "$MAIN" "$DRIVERS" "$POWER" 2>/dev/null |
    grep -Ev 'J7DBG F0[0-3] ' || true
)
[[ -z "$unexpected_j7" ]] || { echo 'ERROR: unexpected J7DBG marker remains in an active qualified R5 source path' >&2; printf '%s\n' "$unexpected_j7" >&2; exit 1; }

bash "$BUILD_SCRIPT" "$SDK_ROOT"

R5="$SDK_ROOT/vision_apps/out/J722S/R5F/FREERTOS/release/vx_app_rtos_linux_mcu2_0.out"
C7X_DIR="$SDK_ROOT/vision_apps/out/J722S/C7524/FREERTOS/release"
C7X1="$C7X_DIR/vx_app_rtos_linux_c7x_1.out"
C7X2="$C7X_DIR/vx_app_rtos_linux_c7x_2.out"

for fw in "$R5" "$C7X1" "$C7X2"; do
    [[ -s "$fw" ]] || { echo "ERROR: source build did not produce firmware: $fw" >&2; exit 1; }
done

rm -rf "$OUT"
install -d -m 0755 "$OUT/usr/lib/firmware/vision_apps_evm"

install -m 0644 "$R5" "$OUT/usr/lib/firmware/vision_apps_evm/vx_app_rtos_linux_mcu2_0.out"
install -m 0644 "$C7X1" "$OUT/usr/lib/firmware/vision_apps_evm/vx_app_rtos_linux_c7x_1.out"
install -m 0644 "$C7X2" "$OUT/usr/lib/firmware/vision_apps_evm/vx_app_rtos_linux_c7x_2.out"

ln -s vision_apps_evm/vx_app_rtos_linux_mcu2_0.out "$OUT/usr/lib/firmware/j722s-main-r5f0_0-fw"
ln -s vision_apps_evm/vx_app_rtos_linux_c7x_1.out "$OUT/usr/lib/firmware/j722s-c71_0-fw"
ln -s vision_apps_evm/vx_app_rtos_linux_c7x_2.out "$OUT/usr/lib/firmware/j722s-c71_1-fw"

main_sha=$(sha256sum "$R5" | awk '{print $1}')
c7x1_sha=$(sha256sum "$C7X1" | awk '{print $1}')
c7x2_sha=$(sha256sum "$C7X2" | awk '{print $1}')

# shellcheck source=/dev/null
source "$MANIFEST"

cat >"$OUT/SOURCE-BUILD.env" <<EOF
format=4
build_mode=ti-psdk-rtos-source-built-r2
vendor=Texas_Instruments
soc=j722s
psdk_rtos_version=${PSDK_RTOS_VERSION}
mcu_plus_sdk_version=${MCU_PLUS_SDK_VERSION}
cgt_armllvm_version=${CGT_ARMLLVM_VERSION}
cgt_c7x_version=${CGT_C7X_VERSION}
sysconfig_version=${SYSCONFIG_VERSION}
memory_map_id=openhd-j722s-4gb-evm-matched-v2
qualified_runtime_identity=j722s-r2-load-image-qualified-20260813
qualified_r5_driver_basename=ti_drivers_config_openhd.c
qualified_r5_power_clock_basename=ti_power_clock_config_openhd.c
qualified_r5_trace_prefix=OHDBG
main_r5_sha256=${main_sha}
c71_0_sha256=${c7x1_sha}
c71_1_sha256=${c7x2_sha}
EOF

cat >"$OUT/SHA256SUMS" <<EOF
${main_sha}  usr/lib/firmware/vision_apps_evm/vx_app_rtos_linux_mcu2_0.out
${c7x1_sha}  usr/lib/firmware/vision_apps_evm/vx_app_rtos_linux_c7x_1.out
${c7x2_sha}  usr/lib/firmware/vision_apps_evm/vx_app_rtos_linux_c7x_2.out
EOF

(
    cd "$OUT"
    sha256sum -c SHA256SUMS
)

echo "SOURCE_BUILT_MAIN_R5_SHA256=$main_sha"
echo "SOURCE_BUILT_C7X1_SHA256=$c7x1_sha"
echo "SOURCE_BUILT_C7X2_SHA256=$c7x2_sha"
echo 'J722S_R2_SOURCE_FIRMWARE_STAGING=PASS'
