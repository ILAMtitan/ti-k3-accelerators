#!/usr/bin/env bash
set -Eeuo pipefail

usage()
{
    echo "Usage: $0 <TI-PSDK-RTOS-root>"
    echo
    echo "Required environment:"
    echo "  PSDK_TOOLS_PATH"
    echo
    echo "Optional environment:"
    echo "  PYTHONUSERBASE"
    echo "  J722S_R1_LOG_DIR"
}

if [[ $# -ne 1 ]]; then
    usage
    exit 2
fi

SDK_ROOT="$(cd "$1" && pwd)"
SDK_BUILDER="$SDK_ROOT/sdk_builder"

SCRIPT_DIR="$(
    cd "$(dirname "${BASH_SOURCE[0]}")"
    pwd
)"

REPO_ROOT="$(
    cd "$SCRIPT_DIR/../.."
    pwd
)"

MANIFEST="$REPO_ROOT/firmware/manifests/j722s-r1.env"

if [[ ! -f "$MANIFEST" ]]; then
    echo "ERROR: missing manifest:"
    echo "  $MANIFEST"
    exit 1
fi

# shellcheck disable=SC1090
source "$MANIFEST"

if [[ "$SDK_ROOT" != "$ORACLE_BUILD_ROOT" ]]; then
    echo "ERROR: Split-R1 oracle-equivalent builds are currently path-sensitive."
    echo "Expected SDK root:"
    echo "  $ORACLE_BUILD_ROOT"
    echo "Actual SDK root:"
    echo "  $SDK_ROOT"
    echo "A checkout-independent prefix-map solution has not yet been qualified."
    exit 1
fi

if [[ -z "${PSDK_TOOLS_PATH:-}" ]]; then
    echo "ERROR: PSDK_TOOLS_PATH is not set"
    exit 1
fi

export PSDK_TOOLS_PATH

if [[ -n "${PYTHONUSERBASE:-}" ]]; then
    export PYTHONUSERBASE
    export PATH="$PYTHONUSERBASE/bin:$PATH"
fi

LOG_DIR="${J722S_R1_LOG_DIR:-$SDK_ROOT/.j722s-r1-build-logs}"
mkdir -p "$LOG_DIR"

HLOS_GCC="$SDK_ROOT/toolchain/sysroots/x86_64-arago-linux/usr/bin/aarch64-oe-linux/aarch64-oe-linux-gcc"
ARM_CLANG="$PSDK_TOOLS_PATH/ti-cgt-armllvm_${CGT_ARMLLVM_VERSION}/bin/tiarmclang"
C7X_CLANG="$PSDK_TOOLS_PATH/ti-cgt-c7000_${CGT_C7X_VERSION}/bin/cl7x"
SYSCONFIG_ROOT="$PSDK_TOOLS_PATH/sysconfig_${SYSCONFIG_VERSION}"

echo '===== J722S SPLIT-R1 BUILD PREFLIGHT ====='
echo "SDK_ROOT=$SDK_ROOT"
echo "PSDK_TOOLS_PATH=$PSDK_TOOLS_PATH"
echo "LOG_DIR=$LOG_DIR"
echo

for dir in \
    "$SDK_BUILDER" \
    "$SDK_ROOT/vision_apps" \
    "$SDK_ROOT/targetfs/usr/include" \
    "$SYSCONFIG_ROOT"
do
    if [[ -d "$dir" ]]; then
        echo "PRESENT $dir"
    else
        echo "ERROR: missing directory:"
        echo "  $dir"
        exit 1
    fi
done

for tool in \
    "$HLOS_GCC" \
    "$ARM_CLANG" \
    "$C7X_CLANG"
do
    if [[ -x "$tool" ]]; then
        echo "EXECUTABLE $tool"
    else
        echo "ERROR: missing executable:"
        echo "  $tool"
        exit 1
    fi
done

COMMON=(
    "SOC=$SOC"
    "TISDK_IMAGE=$TISDK_IMAGE"
    "RTOS=$RTOS"
    "PROFILE=$PROFILE"

    "CGT_ARMLLVM_VERSION=$CGT_ARMLLVM_VERSION"
    "CGT_C7X_VERSION=$CGT_C7X_VERSION"
    "SYSCONFIG_VERSION=$SYSCONFIG_VERSION"


    "BUILD_EMULATION_MODE=$BUILD_EMULATION_MODE"
    "BUILD_TARGET_MODE=$BUILD_TARGET_MODE"
    "BUILD_PTK=$BUILD_PTK"
    "ENABLE_NEW_TIDL_STRUCTURE=$ENABLE_NEW_TIDL_STRUCTURE"

    "BUILD_CPU_MCU2_0=$BUILD_CPU_MCU2_0"
    "BUILD_CPU_C7x_1=$BUILD_CPU_C7x_1"
    "BUILD_CPU_C7x_2=$BUILD_CPU_C7x_2"
)

DEPENDENCY_TARGETS=(
    "$C7X_REBUILD_1"
    "$C7X_REBUILD_2"
    "$C7X_REBUILD_3"
    "$C7X_REBUILD_4"
    "$C7X_REBUILD_5"
)

echo
echo '===== REBUILD C7X DEPENDENCY COHORT ====='

for target in "${DEPENDENCY_TARGETS[@]}"
do
    log="$LOG_DIR/01-${target}.log"

    echo
    echo "============================================================"
    echo "FORCED SOURCE BUILD: $target"
    echo "============================================================"

    if make -B \
        -C "$SDK_BUILDER" \
        "${COMMON[@]}" \
        "$target" \
        2>&1 |
        tee "$log"
    then
        echo "${target}_rc=0"
    else
        rc=$?
        echo "${target}_rc=$rc"
        echo "J722S_R1_BUILD=FAIL"
        exit "$rc"
    fi
done

echo
echo '===== BUILD FULL VISION APPS COHORT ====='

VISION_LOG="$LOG_DIR/02-vision-apps.log"

if make -B \
    -C "$SDK_BUILDER" \
    "${COMMON[@]}" \
    vision_apps \
    2>&1 |
    tee "$VISION_LOG"
then
    echo "vision_apps_rc=0"
else
    rc=$?
    echo "vision_apps_rc=$rc"
    echo "J722S_R1_BUILD=FAIL"
    exit "$rc"
fi

BUILD_CORE="$SDK_ROOT/vision_apps/.build_core.bak"

if [[ ! -f "$BUILD_CORE" ]]; then
    echo "ERROR: missing:"
    echo "  $BUILD_CORE"
    exit 1
fi

EXPECTED_CORE="$(
    printf '%s\n' \
        "$IPC_CORE_1" \
        "$IPC_CORE_2" \
        "$IPC_CORE_3" \
        "$IPC_CORE_4"
)"

ACTUAL_CORE="$(cat "$BUILD_CORE")"

echo
echo '===== IPC BUILD COHORT ====='
cat "$BUILD_CORE"

if [[ "$ACTUAL_CORE" != "$EXPECTED_CORE" ]]; then
    echo
    echo "ERROR: unexpected IPC build cohort"
    echo "J722S_R1_BUILD=FAIL"
    exit 1
fi

R5="$SDK_ROOT/vision_apps/out/J722S/R5F/FREERTOS/release/vx_app_rtos_linux_mcu2_0.out"
C7X_DIR="$SDK_ROOT/vision_apps/out/J722S/C7524/FREERTOS/release"
C7X1="$C7X_DIR/vx_app_rtos_linux_c7x_1.out"
C7X2="$C7X_DIR/vx_app_rtos_linux_c7x_2.out"

echo
echo '===== GENERATED FIRMWARE ====='

for fw in "$R5" "$C7X1" "$C7X2"
do
    if [[ ! -f "$fw" ]]; then
        echo "ERROR: missing firmware:"
        echo "  $fw"
        exit 1
    fi

    sha256sum "$fw"
done

echo
echo "J722S_R1_BUILD=PASS"
