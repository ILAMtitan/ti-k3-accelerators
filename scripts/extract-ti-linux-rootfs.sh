#!/usr/bin/env bash
set -Eeuo pipefail
export LC_ALL=C

usage() {
    echo "Usage: $0 TI_ROOTFS_ARCHIVE DEST_ROOTFS" >&2
    exit 2
}

[[ $# -eq 2 ]] || usage

root=$(cd "$(dirname "$0")/.." && pwd)
manifest="$root/inputs/ti-linux-j722s-11.02.01.03.env"

archive=$(readlink -f "$1")
dest=$(readlink -m "$2")

[[ -s "$manifest" ]] || {
    echo "Missing TI Linux input manifest: $manifest" >&2
    exit 1
}

[[ -s "$archive" ]] || {
    echo "Missing TI rootfs archive: $archive" >&2
    exit 1
}

# shellcheck source=/dev/null
source "$manifest"

[[ "${format:-}" == 1 ]] || {
    echo "Unsupported TI Linux manifest format" >&2
    exit 1
}

[[ "${vendor:-}" == Texas_Instruments ]] || {
    echo "Unexpected TI vendor: ${vendor:-unset}" >&2
    exit 1
}

[[ "${release:-}" == 11.02.01.03 ]] || {
    echo "Unexpected TI release: ${release:-unset}" >&2
    exit 1
}

[[ "${machine:-}" == j722s-evm ]] || {
    echo "Unexpected TI machine: ${machine:-unset}" >&2
    exit 1
}

[[ "${image_target:-}" == tisdk-adas-image ]] || {
    echo "Unexpected TI image target: ${image_target:-unset}" >&2
    exit 1
}

[[ "${rootfs_archive_sha256:-}" =~ ^[0-9a-f]{64}$ ]] || {
    echo "Invalid TI rootfs SHA-256 in manifest" >&2
    exit 1
}

actual=$(
    sha256sum "$archive" |
    awk '{print $1}'
)

if [[ "$actual" != "$rootfs_archive_sha256" ]]; then
    echo "TI rootfs archive SHA-256 mismatch" >&2
    echo "expected=$rootfs_archive_sha256" >&2
    echo "actual=$actual" >&2
    exit 1
fi

echo 'TI_ROOTFS_ARCHIVE_SHA256=PASS'

listing=$(mktemp)
trap 'rm -f "$listing"' EXIT

tar -tJf "$archive" >"$listing"

if awk '
    /^\// {
        bad=1
        print "Absolute archive path: " $0 > "/dev/stderr"
    }

    {
        n=split($0, p, "/")
        for (i=1; i<=n; i++) {
            if (p[i] == "..") {
                bad=1
                print "Parent traversal archive path: " $0 > "/dev/stderr"
                break
            }
        }
    }

    END {
        exit bad ? 1 : 0
    }
' "$listing"
then
    echo 'TI_ROOTFS_ARCHIVE_PATH_SAFETY=PASS'
else
    echo 'TI_ROOTFS_ARCHIVE_PATH_SAFETY=FAIL' >&2
    exit 1
fi

rm -rf "$dest"
mkdir -p "$dest"

tar -xJf "$archive" \
    -C "$dest"

[[ -d "$dest/usr" ]] || {
    echo "Extracted TI rootfs lacks /usr" >&2
    exit 1
}

[[ -d "$dest/var/lib/opkg/info" ]] || {
    echo "Extracted TI rootfs lacks OPKG database" >&2
    exit 1
}

printf 'TI_ROOTFS=%s\n' "$dest"
echo 'TI_ROOTFS_EXTRACT=PASS'
