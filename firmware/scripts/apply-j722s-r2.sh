#!/usr/bin/env bash
set -Eeuo pipefail

usage()
{
    echo "Usage: $0 <TI-PSDK-RTOS-root>"
    echo
    echo "Example:"
    echo "  $0 /opt/ti/ti-processor-sdk-rtos-j722s-evm-11_02_01_03"
}

if [[ $# -ne 1 ]]; then
    usage
    exit 2
fi

SDK_ROOT="$(cd "$1" && pwd)"

SCRIPT_DIR="$(
    cd "$(dirname "${BASH_SOURCE[0]}")"
    pwd
)"

REPO_ROOT="$(
    cd "$SCRIPT_DIR/../.."
    pwd
)"

PATCH_DIR="$REPO_ROOT/firmware/patches/j722s-r2"
RTOS_ROOT="$SDK_ROOT/vision_apps/platform/j722s/rtos"

if [[ ! -d "$RTOS_ROOT" ]]; then
    echo "ERROR: J722S Vision Apps RTOS tree not found:"
    echo "  $RTOS_ROOT"
    exit 1
fi

PATCHES=(
    "$PATCH_DIR/0001-shared-ddr-memory-map.patch"
    "$PATCH_DIR/0002-main-r5-j722s.patch"
    "$PATCH_DIR/0003-c7x-ddr-identity-map.patch"
)

echo '===== J722S SPLIT-R2 SOURCE RECONSTRUCTION ====='
echo "SDK_ROOT=$SDK_ROOT"
echo

for patch in "${PATCHES[@]}"
do
    if [[ ! -f "$patch" ]]; then
        echo "ERROR: missing patch:"
        echo "  $patch"
        exit 1
    fi

    echo "CHECK $(basename "$patch")"

    git -C "$SDK_ROOT" apply \
        --check \
        --whitespace=nowarn \
        "$patch"
done

echo

for patch in "${PATCHES[@]}"
do
    echo "APPLY $(basename "$patch")"

    git -C "$SDK_ROOT" apply \
        --whitespace=nowarn \
        "$patch"
done

echo
echo '===== POST-APPLY PATCH STATE ====='

for patch in "${PATCHES[@]}"
do
    git -C "$SDK_ROOT" apply \
        --reverse \
        --check \
        --whitespace=nowarn \
        "$patch"

    echo "APPLIED $(basename "$patch")"
done

echo
echo '===== REQUIRED ADDED FILES ====='

for file in \
    "$RTOS_ROOT/mcu2_0/generated/ti_drivers_config_j722s.c" \
    "$RTOS_ROOT/mcu2_0/generated/ti_power_clock_config_j722s.c"
do
    if [[ -f "$file" ]]; then
        echo "PRESENT ${file#"$SDK_ROOT/"}"
    else
        echo "ERROR: missing ${file#"$SDK_ROOT/"}"
        exit 1
    fi
done

INC="$RTOS_ROOT/mcu2_0/concerto_mcu2_0_inc.mak"
MAIN="$RTOS_ROOT/mcu2_0/main.c"
DRIVERS="$RTOS_ROOT/mcu2_0/generated/ti_drivers_config_j722s.c"
POWER="$RTOS_ROOT/mcu2_0/generated/ti_power_clock_config_j722s.c"

grep -q 'generated/ti_drivers_config_j722s\.c' "$INC" || {
    echo "ERROR: J722S driver source is not the active compiler input" >&2
    exit 1
}

grep -q 'generated/ti_power_clock_config_j722s\.c' "$INC" || {
    echo "ERROR: J722S power/clock source is not the active compiler input" >&2
    exit 1
}

if grep -q 'generated/ti_.*_config_openhd\.c' "$INC"; then
    echo "ERROR: application-specific generated-source basename remains active" >&2
    exit 1
fi

j7_count=$(grep -ho 'J7DBG' "$MAIN" "$DRIVERS" "$POWER" | wc -l)
[[ "$j7_count" -eq 46 ]] || {
    echo "ERROR: expected 46 J7DBG source markers, got $j7_count" >&2
    exit 1
}

if grep -q 'OHDBG' "$MAIN" "$DRIVERS" "$POWER"; then
    echo "ERROR: historical OpenHD diagnostic marker remains in application-neutral R5 sources" >&2
    exit 1
fi

echo "R5_DRIVER_BASENAME=ti_drivers_config_j722s.c"
echo "R5_POWER_CLOCK_BASENAME=ti_power_clock_config_j722s.c"
echo "R5_TRACE_PREFIX=J7DBG"

echo
echo '===== C7X NO-BOARD-DEPS SYMLINKS ====='

for core in c7x_1 c7x_2
do
    link="$RTOS_ROOT/$core/freertos_no_board_deps.syscfg"

    if [[ ! -L "$link" ]]; then
        echo "ERROR: not a symlink:"
        echo "  $link"
        exit 1
    fi

    target="$(readlink "$link")"

    if [[ "$target" != "freertos.syscfg" ]]; then
        echo "ERROR: unexpected symlink target:"
        echo "  $link -> $target"
        exit 1
    fi

    echo "$core -> $target"
done

echo
echo "J722S_R2_PATCH_APPLY=PASS"
