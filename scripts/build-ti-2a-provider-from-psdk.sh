#!/usr/bin/env bash
set -Eeuo pipefail
export LC_ALL=C

usage()
{
    cat >&2 <<'USAGE'
Usage:
  build-ti-2a-provider-from-psdk.sh TI_PSDK_RTOS_ROOT OUTPUT_DIR

Required environment:
  PSDK_TOOLS_PATH    TI compiler/SysConfig tools used by the PSDK RTOS build

This builds the J722S imaging target from the supplied TI PSDK RTOS source tree,
then stages an AArch64 library built from that imaging tree which defines:
  TI_2A_wrapper_create
  TI_2A_wrapper_process
  TI_2A_wrapper_delete
USAGE
    exit 2
}

[[ $# -eq 2 ]] || usage

SDK_ROOT=$(cd "$1" && pwd)
OUTPUT_DIR=$(readlink -m "$2")

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
MANIFEST="$REPO_ROOT/firmware/manifests/j722s-r2.env"
SDK_BUILDER="$SDK_ROOT/sdk_builder"
IMAGING_ROOT="$SDK_ROOT/imaging"

[[ -s "$MANIFEST" ]] || {
    echo "Missing J722S R2 manifest: $MANIFEST" >&2
    exit 1
}

# shellcheck source=/dev/null
source "$MANIFEST"

[[ -n ${PSDK_TOOLS_PATH:-} ]] || {
    echo "PSDK_TOOLS_PATH is required" >&2
    exit 1
}
PSDK_TOOLS_PATH=$(readlink -f "$PSDK_TOOLS_PATH")
export PSDK_TOOLS_PATH

[[ -d "$SDK_BUILDER" && -d "$IMAGING_ROOT/ti_2a_wrapper" ]] || {
    echo "The supplied SDK does not contain the expected J722S imaging source tree" >&2
    echo "SDK_ROOT=$SDK_ROOT" >&2
    exit 1
}

CROSS_PREFIX="$SDK_ROOT/toolchain/sysroots/x86_64-arago-linux/usr/bin/aarch64-oe-linux/aarch64-oe-linux-"
CROSS_NM="${CROSS_PREFIX}nm"
CROSS_READELF="${CROSS_PREFIX}readelf"

ARM_CLANG="$PSDK_TOOLS_PATH/ti-cgt-armllvm_${CGT_ARMLLVM_VERSION}/bin/tiarmclang"
C7X_CLANG="$PSDK_TOOLS_PATH/ti-cgt-c7000_${CGT_C7X_VERSION}/bin/cl7x"
SYSCONFIG_ROOT="$PSDK_TOOLS_PATH/sysconfig_${SYSCONFIG_VERSION}"

for path in \
    "$CROSS_NM" \
    "$CROSS_READELF" \
    "$ARM_CLANG" \
    "$C7X_CLANG" \
    "$SYSCONFIG_ROOT"
do
    [[ -e "$path" ]] || {
        echo "Missing required PSDK build input: $path" >&2
        exit 1
    }
done

COMMON=(
    "SOC=$SOC"
    "TISDK_IMAGE=$TISDK_IMAGE"
    "RTOS=$RTOS"
    "PROFILE=$PROFILE"
    "BUILD_PROFILE_LIST_ALL=$BUILD_PROFILE_LIST_ALL"
    "CGT_ARMLLVM_VERSION=$CGT_ARMLLVM_VERSION"
    "CGT_C7X_VERSION=$CGT_C7X_VERSION"
    "SYSCONFIG_VERSION=$SYSCONFIG_VERSION"
    "BUILD_EDGEAI=$BUILD_EDGEAI"
    "BUILD_MCU_BOARD_DEPENDENCIES=$BUILD_MCU_BOARD_DEPENDENCIES"
    "BUILD_ENABLE_ETHFW=$BUILD_ENABLE_ETHFW"
    "BUILD_EMULATION_MODE=no"
    "BUILD_TARGET_MODE=yes"
    "BUILD_LINUX_MPU=yes"
    "BUILD_PTK=$BUILD_PTK"
    "ENABLE_NEW_TIDL_STRUCTURE=$ENABLE_NEW_TIDL_STRUCTURE"
)

echo '===== TI 2A SOURCE BUILD ====='
echo "SDK_ROOT=$SDK_ROOT"
echo "PSDK_TOOLS_PATH=$PSDK_TOOLS_PATH"
echo "SOURCE_COMPONENT=imaging/ti_2a_wrapper"
echo

make -B \
    -C "$SDK_BUILDER" \
    "${COMMON[@]}" \
    imaging

echo
echo '===== TI 2A PROVIDER DISCOVERY ====='

symbols=(
    TI_2A_wrapper_create
    TI_2A_wrapper_process
    TI_2A_wrapper_delete
)

mapfile -t candidates < <(
    find -L "$IMAGING_ROOT" -type f \
        \( -name '*.a' -o -name '*.so' -o -name '*.so.*' \) \
        -print 2>/dev/null |
    sort -u
)

providers=()

for candidate in "${candidates[@]}"
do
    symbol_table=$(
        "$CROSS_NM" -g --defined-only "$candidate" 2>/dev/null || true
    )
    [[ -n "$symbol_table" ]] || continue

    provides_all=yes
    for symbol in "${symbols[@]}"
    do
        if ! awk -v wanted="$symbol" \
            '$NF == wanted { found=1 } END { exit(found ? 0 : 1) }' \
            <<<"$symbol_table"
        then
            provides_all=no
            break
        fi
    done
    [[ "$provides_all" == yes ]] || continue

    elf_headers=$(
        "$CROSS_READELF" -h "$candidate" 2>/dev/null || true
    )
    grep -Eq 'Machine:[[:space:]]+AArch64' <<<"$elf_headers" || {
        echo "Ignoring non-AArch64 provider candidate: ${candidate#"$SDK_ROOT/"}" >&2
        continue
    }

    providers+=("$candidate")
done

(( ${#providers[@]} > 0 )) || {
    echo "No AArch64 source-built TI 2A provider was found under imaging/." >&2
    echo "The imaging target completed, but no library defined all required symbols." >&2
    echo "Inspect imaging/ti_2a_wrapper and the imaging build logs before changing the image build." >&2
    exit 1
}

selected=${providers[0]}
selected_sha=$(sha256sum "$selected" | awk '{print $1}')

for provider in "${providers[@]:1}"
do
    provider_sha=$(sha256sum "$provider" | awk '{print $1}')
    [[ "$provider_sha" == "$selected_sha" ]] || {
        echo "Conflicting source-built TI 2A providers were found:" >&2
        printf '  %s  %s\n' "$selected_sha" "${selected#"$SDK_ROOT/"}" >&2
        printf '  %s  %s\n' "$provider_sha" "${provider#"$SDK_ROOT/"}" >&2
        exit 1
    }
done

case "$selected" in
    *.a)
        provider_kind=static
        output_name=libti_2a_wrapper.a
        ;;
    *)
        provider_kind=shared
        output_name=libti_2a_wrapper.so
        ;;
esac

selected_relpath=${selected#"$SDK_ROOT/"}
[[ "$selected_relpath" != "$selected" ]] || {
    echo "Selected provider is outside the PSDK RTOS tree: $selected" >&2
    exit 1
}

rm -rf "$OUTPUT_DIR"
install -d -m 0755 "$OUTPUT_DIR"
install -m 0644 "$selected" "$OUTPUT_DIR/$output_name"

cat >"$OUTPUT_DIR/SOURCE-BUILD.env" <<META
format=1
build_mode=ti-psdk-rtos-source-built-2a-provider
vendor=Texas_Instruments
psdk_rtos_version=$PSDK_RTOS_VERSION
mcu_plus_sdk_version=$MCU_PLUS_SDK_VERSION
soc=$SOC
profile=$PROFILE
source_component=imaging/ti_2a_wrapper
build_target=imaging
build_target_mode=yes
build_linux_mpu=yes
selected_relpath=$selected_relpath
provider_kind=$provider_kind
provider_filename=$output_name
provider_sha256=$selected_sha
required_symbols_csv=TI_2A_wrapper_create,TI_2A_wrapper_process,TI_2A_wrapper_delete
META

for symbol in "${symbols[@]}"
do
    "$CROSS_NM" -g --defined-only "$OUTPUT_DIR/$output_name" |
        awk -v wanted="$symbol" \
            '$NF == wanted { found=1 } END { exit(found ? 0 : 1) }'
done

staged_sha=$(sha256sum "$OUTPUT_DIR/$output_name" | awk '{print $1}')
[[ "$staged_sha" == "$selected_sha" ]]

echo "TI_2A_PROVIDER_SOURCE=$selected_relpath"
echo "TI_2A_PROVIDER_KIND=$provider_kind"
echo "TI_2A_PROVIDER_SHA256=$staged_sha"
echo "TI_2A_SOURCE_BUILD=PASS"
