#!/usr/bin/env bash
set -Eeuo pipefail
export LC_ALL=C

usage() {
    echo "Usage: $0 TI_ROOTFS DEST" >&2
    exit 2
}

[[ $# -eq 2 ]] || usage

repo=$(cd "$(dirname "$0")/.." && pwd)

src=$(readlink -f "$1")
dst=$(readlink -m "$2")

release_manifest="$repo/inputs/ti-linux-j722s-11.02.01.03.env"
file_lock="$repo/inputs/ti-j722s-11.02.01.03-userspace-files.lock"
package_lock="$repo/inputs/ti-j722s-11.02.01.03-userspace-packages.lock"

for f in \
    "$release_manifest" \
    "$file_lock" \
    "$package_lock"
do
    [[ -s "$f" ]] || {
        echo "Missing input contract: $f" >&2
        exit 1
    }
done

[[ -d "$src/usr" ]] || {
    echo "Invalid TI rootfs: $src" >&2
    exit 1
}

opkg="$src/var/lib/opkg/info"

[[ -d "$opkg" ]] || {
    echo "TI rootfs OPKG database missing: $opkg" >&2
    exit 1
}

# shellcheck source=/dev/null
source "$release_manifest"

[[ "${vendor:-}" == Texas_Instruments ]] || exit 1
[[ "${release:-}" == 11.02.01.03 ]] || exit 1
[[ "${machine:-}" == j722s-evm ]] || exit 1
[[ "${image_target:-}" == tisdk-adas-image ]] || exit 1
[[ "${rootfs_archive_sha256:-}" =~ ^[0-9a-f]{64}$ ]] || exit 1

locked_objects=$(awk 'END {print NR}' "$file_lock")
locked_packages=$(awk 'END {print NR}' "$package_lock")

[[ "$locked_objects" == 511 ]] || {
    echo "Expected 511 locked TI userspace objects; found $locked_objects" >&2
    exit 1
}

[[ "$locked_packages" == 16 ]] || {
    echo "Expected 16 locked TI packages; found $locked_packages" >&2
    exit 1
}

echo 'TI_USERSPACE_LOCK_CARDINALITY=PASS'

actual_packages=$(mktemp)
expected_packages=$(mktemp)

cleanup() {
    rm -f "$actual_packages" "$expected_packages"
}
trap cleanup EXIT

awk -F '\t' '
    NF >= 1 && $1 != "" {
        print $1
    }
' "$file_lock" |
sort -u >"$actual_packages"

sort -u "$package_lock" >"$expected_packages"

if ! cmp -s "$actual_packages" "$expected_packages"; then
    echo "Package lock and file lock disagree" >&2
    diff -u "$expected_packages" "$actual_packages" >&2 || true
    exit 1
fi

echo 'TI_USERSPACE_PACKAGE_SET=PASS'

for pkg in $(cat "$package_lock"); do
    [[ -s "$opkg/$pkg.list" ]] || {
        echo "Missing TI OPKG ownership file: $pkg.list" >&2
        exit 1
    }
done

echo 'TI_USERSPACE_OPKG_PACKAGES=PASS'

rm -rf "$dst"
mkdir -p "$dst"

fail=0
copied=0

while IFS=$'\t' read -r pkg path identity; do
    [[ -n "$pkg" && -n "$path" && -n "$identity" ]] || {
        echo "Malformed userspace lock entry" >&2
        fail=1
        continue
    }

    source_path="$src$path"
    package_list="$opkg/$pkg.list"

    [[ -e "$source_path" || -L "$source_path" ]] || {
        echo "Missing locked TI object: $path" >&2
        fail=1
        continue
    }

    #
    # Verify package ownership. Most paths match OPKG directly.
    # /lib -> /usr/lib usrmerge aliases are accepted through the
    # canonical rootfs-relative path.
    #
    owned=no

    if awk -F '\t' -v wanted="$path" '
        $1 == wanted {
            found=1
        }
        END {
            exit found ? 0 : 1
        }
    ' "$package_list"
    then
        owned=yes
    else
        canonical_abs=$(
            readlink -f "$source_path" 2>/dev/null || true
        )

        canonical_rel=""

        if [[ "$canonical_abs" == "$src"* ]]; then
            canonical_rel=${canonical_abs#"$src"}
        fi

        if [[ -n "$canonical_rel" ]] &&
           awk -F '\t' -v wanted="$canonical_rel" '
               $1 == wanted {
                   found=1
               }
               END {
                   exit found ? 0 : 1
               }
           ' "$package_list"
        then
            owned=yes
        fi
    fi

    if [[ "$owned" != yes ]]; then
        echo "TI OPKG ownership mismatch: package=$pkg path=$path" >&2
        fail=1
        continue
    fi

    #
    # Verify exact object identity.
    #
    if [[ -L "$source_path" ]]; then
        actual=$(readlink "$source_path")

        if [[ "$actual" != "$identity" ]]; then
            echo "TI symlink identity mismatch: $path" >&2
            echo "expected=$identity" >&2
            echo "actual=$actual" >&2
            fail=1
            continue
        fi
    else
        actual=$(
            sha256sum "$source_path" |
            awk '{print $1}'
        )

        if [[ "$actual" != "$identity" ]]; then
            echo "TI file SHA-256 mismatch: $path" >&2
            echo "expected=$identity" >&2
            echo "actual=$actual" >&2
            fail=1
            continue
        fi
    fi

    mkdir -p "$dst$(dirname "$path")"
    cp -a "$source_path" "$dst$path"

    ((copied+=1))

done <"$file_lock"

#
# Preserve the mode of every TI source directory materialized as part of
# the locked payload. Directory mtimes are intentionally not part of the
# userspace reproducibility contract.
#
directory_count=0

while IFS= read -r -d '' directory; do
    rel=${directory#"$dst"}

    [[ -n "$rel" ]] || continue

    source_directory="$src$rel"

    [[ -d "$source_directory" ]] || {
        echo "Missing TI source directory for locked payload: $rel" >&2
        fail=1
        continue
    }

    chmod --reference="$source_directory" "$directory"
    ((directory_count+=1))

done < <(
    find "$dst" -mindepth 1 -type d -print0
)

echo "TI_USERSPACE_DIRECTORIES=$directory_count"

#
# Structural staging directories are created by the R2 importer rather than
# imported as TI-owned directory objects. The qualified R2 staging contract
# materializes these directories as 0775.
#
staging_scaffold_dirs=(
    /lib
    /lib/firmware
    /lib/firmware/cnm
    /lib/firmware/ti-connectivity
    /lib/gstreamer-1.0
    /opt
    /usr
    /usr/include
    /usr/lib
    /usr/lib/firmware
    /usr/lib/firmware/cnm
    /usr/lib/firmware/ti-connectivity
    /usr/lib/gstreamer-1.0
)

for rel in "${staging_scaffold_dirs[@]}"; do
    directory="$dst$rel"

    [[ -d "$directory" ]] || {
        echo "Missing R2 userspace staging directory: $rel" >&2
        fail=1
        continue
    }

    chmod 0775 "$directory"
done

echo 'TI_USERSPACE_STAGING_SCAFFOLD_MODES=PASS'

(( fail == 0 )) || {
    echo 'TI_USERSPACE_LOCK_IMPORT=FAIL' >&2
    exit 1
}

[[ "$copied" == 511 ]] || {
    echo "Expected to copy 511 objects; copied $copied" >&2
    exit 1
}

echo 'TI_USERSPACE_LOCK_IMPORT=PASS'

#
# The lock intentionally excludes Vision Apps remote-core firmware.
# That firmware remains a separate R2 contract.
#
if find "$dst" \
    \( -type f -o -type l \) \
    \( \
        -name 'vx_app_rtos_linux_*.out' \
        -o -name 'j722s-main-r5f0_0-fw' \
        -o -name 'j722s-c71_0-fw' \
        -o -name 'j722s-c71_1-fw' \
    \) \
    -print -quit |
    grep -q .
then
    echo "Userspace lock illegally contains Vision Apps remote firmware" >&2
    exit 1
fi

echo 'TI_USERSPACE_REMOTE_FIRMWARE_BOUNDARY=PASS'

#
# Essential qualification inputs.
#
for required in \
    /opt/vision_apps/vx_app_arm_remote_log.out \
    /opt/vision_apps/vx_app_arm_ipc.out \
    /opt/imaging/imx219/linear/dcc_viss_1920x1080.bin \
    /opt/imaging/imx219/linear/dcc_2a_1920x1080.bin
do
    [[ -s "$dst$required" ]] || {
        echo "Missing required TI accelerator object: $required" >&2
        exit 1
    }
done

mapfile -t plugins < <(
    find "$dst" \
        -type f \
        -path '*/gstreamer-1.0/libgsttiovx.so*' \
        -print |
    sort -u
)

(( ${#plugins[@]} > 0 )) || {
    echo "TI release libgsttiovx.so missing" >&2
    exit 1
}

#
# Generate new generic provenance directly from the official TI release
# contract and the exact R2 userspace locks.
#
file_lock_sha=$(
    sha256sum "$file_lock" |
    awk '{print $1}'
)

package_lock_sha=$(
    sha256sum "$package_lock" |
    awk '{print $1}'
)

remote_logger_sha=$(
    sha256sum "$dst/opt/vision_apps/vx_app_arm_remote_log.out" |
    awk '{print $1}'
)

cat >"$dst/.ti-k3-vendor-bundle.env" <<META
format=2
build_mode=ti-release-binary
firmware_policy=release-rootfs-firmware-not-used
vendor=Texas_Instruments
release=${release}
machine=${machine}
image_target=${image_target}
rootfs_archive=${rootfs_archive}
rootfs_url=${rootfs_url}
rootfs_archive_sha256=${rootfs_archive_sha256}
archive_strip_components=${archive_strip_components:-0}
userspace_selection=opkg-package-path-identity-lock
userspace_locked_objects=511
userspace_locked_packages=16
userspace_file_lock_sha256=${file_lock_sha}
userspace_package_lock_sha256=${package_lock_sha}
development_headers_base=ti-psdk-linux-11.02.01.03-opkg
development_header_base_packages=libtivision-apps-dev,ti-tidl-dev,libti-rpmsg-char-dev,libedgeai-apps-utils-dev,edgeai-tiovx-kernels-dev
remote_logger_path=/opt/vision_apps/vx_app_arm_remote_log.out
remote_logger_sha256=${remote_logger_sha}
META

echo 'TI_USERSPACE_PROVENANCE_GENERATED=PASS'
printf 'TI_USERSPACE_OBJECTS=%d\n' "$copied"
printf 'TI_USERSPACE_DEST=%s\n' "$dst"
