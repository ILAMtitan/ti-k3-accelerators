#!/usr/bin/env bash
set -Eeuo pipefail

if [[ $# -ne 1 ]]; then
    echo "Usage: $0 <TI-PSDK-RTOS-root>" >&2
    exit 2
fi

SDK_ROOT="$(cd "$1" && pwd)"
MCU="$SDK_ROOT/vision_apps/platform/j722s/rtos/mcu2_0"
GEN="$MCU/generated"
INC="$MCU/concerto_mcu2_0_inc.mak"
MAIN="$MCU/main.c"

DRIVERS_J722S="$GEN/ti_drivers_config_j722s.c"
POWER_J722S="$GEN/ti_power_clock_config_j722s.c"
DRIVERS_QUAL="$GEN/ti_drivers_config_openhd.c"
POWER_QUAL="$GEN/ti_power_clock_config_openhd.c"

for file in "$INC" "$MAIN" "$DRIVERS_J722S" "$POWER_J722S"; do
    if [[ ! -f "$file" ]]; then
        echo "ERROR: missing source input: $file" >&2
        exit 1
    fi
done

# The R2 platform is application-neutral, but these two compiler-visible source
# basenames and the OHDBG diagnostic prefix are retained exactly because the
# hardware-qualified R5 load image was produced with them. Changing only these
# identifiers changes allocated .rodata and relocation results even when source
# logic is otherwise identical.
if [[ -e "$DRIVERS_QUAL" || -e "$POWER_QUAL" ]]; then
    echo "ERROR: qualified-identity source basename already exists" >&2
    echo "  $DRIVERS_QUAL" >&2
    echo "  $POWER_QUAL" >&2
    exit 1
fi

mv "$DRIVERS_J722S" "$DRIVERS_QUAL"
mv "$POWER_J722S" "$POWER_QUAL"

sed -i \
    -e 's#generated/ti_drivers_config_j722s\.c#generated/ti_drivers_config_openhd.c#g' \
    -e 's#generated/ti_power_clock_config_j722s\.c#generated/ti_power_clock_config_openhd.c#g' \
    "$INC"

for file in "$MAIN" "$DRIVERS_QUAL" "$POWER_QUAL"; do
    sed -i 's/J7DBG/OHDBG/g' "$file"
done

if grep -q 'generated/ti_.*_config_j722s\.c' "$INC"; then
    echo "ERROR: stale J722S generated-source basename remains in $INC" >&2
    exit 1
fi

for expected in "$DRIVERS_QUAL" "$POWER_QUAL"; do
    if [[ ! -f "$expected" ]]; then
        echo "ERROR: missing qualified-identity source: $expected" >&2
        exit 1
    fi
done

if grep -q 'J7DBG' "$MAIN" "$DRIVERS_QUAL" "$POWER_QUAL"; then
    echo "ERROR: stale J7DBG marker remains in active R5 sources" >&2
    exit 1
fi

echo "QUALIFIED_R5_DRIVER_BASENAME=ti_drivers_config_openhd.c"
echo "QUALIFIED_R5_POWER_CLOCK_BASENAME=ti_power_clock_config_openhd.c"
echo "QUALIFIED_R5_TRACE_PREFIX=OHDBG"
echo "J722S_R2_QUALIFIED_IDENTITY_NORMALIZATION=PASS"
