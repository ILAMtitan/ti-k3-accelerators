#!/usr/bin/env bash
set -Eeuo pipefail
export LC_ALL=C

usage() {
    echo "Usage: $0 DEST_ROOTFS" >&2
    exit 2
}

[[ $# -eq 1 ]] || usage

repo=$(cd "$(dirname "$0")/.." && pwd)
dst=$(readlink -m "$1")

manifest="$repo/inputs/ti-edgeai-development-headers.env"
lock="$repo/inputs/ti-edgeai-development-headers.lock"

[[ -d "$dst/usr/include" ]] || {
    echo "TI userspace destination is not initialized: $dst" >&2
    exit 1
}

[[ -s "$manifest" && -s "$lock" ]] || {
    echo "TI EdgeAI header input contract missing" >&2
    exit 1
}

for cmd in git sha256sum awk find sort cp chmod stat; do
    command -v "$cmd" >/dev/null || {
        echo "Missing command: $cmd" >&2
        exit 1
    }
done

# shellcheck source=/dev/null
source "$manifest"

[[ "${format:-}" == 1 ]] || exit 1
[[ "${vendor:-}" == Texas_Instruments ]] || exit 1
[[ "${release:-}" == 11.02.01.03 ]] || exit 1
[[ "${header_count:-}" == 32 ]] || exit 1

declare -A repositories=(
    [edgeai-tiovx-modules]="$edgeai_tiovx_modules_repository"
    [edgeai-tiovx-kernels]="$edgeai_tiovx_kernels_repository"
    [edgeai-apps-utils]="$edgeai_apps_utils_repository"
)

declare -A commits=(
    [edgeai-tiovx-modules]="$edgeai_tiovx_modules_commit"
    [edgeai-tiovx-kernels]="$edgeai_tiovx_kernels_commit"
    [edgeai-apps-utils]="$edgeai_apps_utils_commit"
)

declare -A expected_counts=(
    [edgeai-tiovx-modules]="$edgeai_tiovx_modules_header_count"
    [edgeai-tiovx-kernels]="$edgeai_tiovx_kernels_header_count"
    [edgeai-apps-utils]="$edgeai_apps_utils_header_count"
)

work=$(mktemp -d)

cleanup() {
    rm -rf "$work"
}
trap cleanup EXIT

fetch_exact()
{
    local component=$1
    local repository=${repositories[$component]}
    local commit=${commits[$component]}
    local source="$work/$component"

    git init -q "$source"
    git -C "$source" remote add origin "$repository"

    if ! git -C "$source" fetch -q --no-tags origin "$commit"; then
        git -C "$source" fetch -q --no-tags origin \
            '+refs/heads/*:refs/remotes/origin/*'

        git -C "$source" cat-file -e "$commit^{commit}"
    fi

    git -C "$source" checkout -q --detach "$commit"

    actual=$(git -C "$source" rev-parse HEAD)

    [[ "$actual" == "$commit" ]] || {
        echo "TI source commit mismatch: $component" >&2
        echo "expected=$commit" >&2
        echo "actual=$actual" >&2
        exit 1
    }

    printf '%s_COMMIT=%s\n' \
        "$(printf '%s' "$component" | tr 'a-z-' 'A-Z_')" \
        "$actual"
}

fetch_exact edgeai-apps-utils
fetch_exact edgeai-tiovx-kernels
fetch_exact edgeai-tiovx-modules

total=$(awk 'END {print NR}' "$lock")
[[ "$total" == 32 ]] || {
    echo "Expected 32 locked EdgeAI headers; found $total" >&2
    exit 1
}

fail=0
copied=0

declare -A copied_counts=()

while IFS=$'\t' read -r component path expected_hash; do
    case "$component" in
        edgeai-apps-utils|edgeai-tiovx-kernels|edgeai-tiovx-modules)
            ;;
        *)
            echo "Unknown TI EdgeAI component in lock: $component" >&2
            fail=1
            continue
            ;;
    esac

    prefix="/usr/include/$component/"

    [[ "$path" == "$prefix"* ]] || {
        echo "Invalid locked header path: $path" >&2
        fail=1
        continue
    }

    rel=${path#"$prefix"}
    source_file="$work/$component/include/$rel"

    [[ -f "$source_file" ]] || {
        echo "Missing pinned TI source header: $component/$rel" >&2
        fail=1
        continue
    }

    actual_hash=$(sha256sum "$source_file" | awk '{print $1}')

    if [[ "$actual_hash" != "$expected_hash" ]]; then
        echo "Pinned TI source header SHA mismatch: $path" >&2
        echo "expected=$expected_hash" >&2
        echo "actual=$actual_hash" >&2
        fail=1
        continue
    fi

    mkdir -p "$dst$(dirname "$path")"
    cp -a "$source_file" "$dst$path"

    ((copied+=1))
    copied_counts[$component]=$(( ${copied_counts[$component]:-0} + 1 ))

done < "$lock"

(( fail == 0 )) || {
    echo 'TI_EDGEAI_HEADER_IMPORT=FAIL' >&2
    exit 1
}

[[ "$copied" == 32 ]] || {
    echo "Expected 32 copied headers; copied $copied" >&2
    exit 1
}

for component in \
    edgeai-apps-utils \
    edgeai-tiovx-kernels \
    edgeai-tiovx-modules
do
    actual=${copied_counts[$component]:-0}
    expected=${expected_counts[$component]}

    [[ "$actual" == "$expected" ]] || {
        echo "Header count mismatch for $component: expected=$expected actual=$actual" >&2
        exit 1
    }

    #
    # Preserve TI source directory modes for the component include tree.
    #
    source_root="$work/$component/include"
    dest_root="$dst/usr/include/$component"

    while IFS= read -r -d '' directory; do
        rel=${directory#"$dest_root"}
        source_directory="$source_root$rel"

        [[ -d "$source_directory" ]] || continue
        chmod --reference="$source_directory" "$directory"

    done < <(
        find "$dest_root" -type d -print0
    )
done

manifest_sha=$(sha256sum "$manifest" | awk '{print $1}')
lock_sha=$(sha256sum "$lock" | awk '{print $1}')

provenance="$dst/.ti-k3-vendor-bundle.env"

[[ -s "$provenance" ]] || {
    echo "Base TI userspace provenance missing: $provenance" >&2
    exit 1
}

cat >>"$provenance" <<META
development_headers_model=ti-psdk-opkg-plus-ti-edgeai-source-overlay
development_headers_overlay=ti-edgeai-pinned-source
development_headers_overlay_count=32
development_headers_overlay_manifest_sha256=${manifest_sha}
development_headers_overlay_lock_sha256=${lock_sha}
edgeai_tiovx_modules_repository=${edgeai_tiovx_modules_repository}
edgeai_tiovx_modules_commit=${edgeai_tiovx_modules_commit}
edgeai_tiovx_kernels_repository=${edgeai_tiovx_kernels_repository}
edgeai_tiovx_kernels_commit=${edgeai_tiovx_kernels_commit}
edgeai_apps_utils_repository=${edgeai_apps_utils_repository}
edgeai_apps_utils_commit=${edgeai_apps_utils_commit}
META

echo 'TI_EDGEAI_HEADER_IMPORT=PASS'
printf 'TI_EDGEAI_HEADERS=%d\n' "$copied"
