#!/usr/bin/env bash
set -Eeuo pipefail

[[ $(id -u) -eq 0 ]] || { echo 'Run as root' >&2; exit 1; }

root=$(cd "$(dirname "$0")/.." && pwd)
PATCH="$root/patches/gstreamer/0001-v4l2-use-negotiated-resolution-for-encoded-sizeimage.patch"
EXPECTED_VERSION=${EXPECTED_VERSION:-1.24.2-1ubuntu1.5}
WORK=${WORK:-/var/tmp/gst-good-cma}
SRC_PKG=gst-plugins-good1.0
BIN_PKG=gstreamer1.0-plugins-good
OVERRIDE=/opt/ti-k3/gstreamer-overrides/gstreamer-1.0/libgstvideo4linux2.so
GST_ENV=/etc/ti-k3/gstreamer.env
QUALIFIED_SHA256=85fee44325de66cd0ddb6e4470dc45d8282c82726a1ee9cbe147b220e4c46af1
STAMP=$(date -u +%Y%m%dT%H%M%SZ)

die(){ echo "ERROR: $*" >&2; exit 1; }
say(){ printf '\n=== %s ===\n' "$*"; }

for cmd in apt-get dpkg-query dpkg-buildpackage dpkg-deb patch find gst-inspect-1.0 sha256sum; do
  command -v "$cmd" >/dev/null || die "Missing command: $cmd"
done
[[ -s "$PATCH" ]] || die "Missing patch: $PATCH"

installed=$(dpkg-query -W -f='${Version}' "$BIN_PKG" 2>/dev/null || true)
[[ "$installed" == "$EXPECTED_VERSION" ]] ||
  die "Expected $BIN_PKG $EXPECTED_VERSION, found: ${installed:-not-installed}"

arch=$(dpkg --print-architecture)
[[ "$arch" == arm64 ]] || die "This qualified build recipe expects arm64, got: $arch"

say 'Stopping OpenHD before replacing the V4L2 plugin override'
systemctl stop openhd.service 2>/dev/null || true

say 'Preparing Ubuntu Noble GStreamer source build'
rm -rf "$WORK"
install -d -m 0755 "$WORK"
cd "$WORK"

if ! apt-get build-dep -y "$SRC_PKG"; then
  die "apt build-dep failed. Ensure Noble deb-src entries are enabled, then retry."
fi

apt-get source "$SRC_PKG=$EXPECTED_VERSION"

src=$(find "$WORK" -mindepth 1 -maxdepth 1 -type d -name 'gst-plugins-good1.0-*' -print -quit)
[[ -n "$src" && -d "$src/sys/v4l2" ]] || die 'Could not locate extracted gst-plugins-good source tree'

say 'Applying negotiated-resolution encoded sizeimage fix'
(
  cd "$src"
  patch --forward --batch -p1 <"$PATCH"
)

grep -Fq 'calculate_encoded_sizeimage (guint width, guint height' \
  "$src/sys/v4l2/gstv4l2object.c" ||
  die 'Patched GStreamer source marker missing'

say 'Building Ubuntu GStreamer package'
(
  cd "$src"
  DEB_BUILD_OPTIONS=nocheck dpkg-buildpackage -b -uc -us
)

deb=$(find "$WORK" -maxdepth 1 -type f \
  -name "gstreamer1.0-plugins-good_*_${arch}.deb" -print -quit)
[[ -n "$deb" ]] || die 'Built gstreamer1.0-plugins-good arm64 package not found'

stage="$WORK/extract"
rm -rf "$stage"
install -d -m 0755 "$stage"
dpkg-deb -x "$deb" "$stage"

plugin="$stage/usr/lib/aarch64-linux-gnu/gstreamer-1.0/libgstvideo4linux2.so"
[[ -s "$plugin" ]] || die "Built V4L2 plugin not found: $plugin"

say 'Installing isolated GStreamer V4L2 override'
install -d -m 0755 /root/ti-k3-gstreamer-backups
[[ -e "$OVERRIDE" ]] &&
  cp -a "$OVERRIDE" "/root/ti-k3-gstreamer-backups/libgstvideo4linux2.so.$STAMP"
[[ -e "$GST_ENV" ]] &&
  cp -a "$GST_ENV" "/root/ti-k3-gstreamer-backups/gstreamer.env.$STAMP"

install -d -m 0755 "$(dirname "$OVERRIDE")"
install -m 0644 "$plugin" "$OVERRIDE"

install -d -m 0755 "$(dirname "$GST_ENV")"
cat >"$GST_ENV" <<'EOF_ENV'
LD_LIBRARY_PATH=/opt/ti-k3/runtime/current/ti
GST_PLUGIN_PATH_1_0=/opt/ti-k3/gstreamer-overrides/gstreamer-1.0:/opt/ti-k3/runtime/current/gstreamer/gstreamer-1.0:/opt/ti-k3/runtime/current/ti/gstreamer-1.0
EOF_ENV

unset GST_PLUGIN_PATH GST_PLUGIN_PATH_1_0 GST_REGISTRY || true
set -a
# shellcheck source=/dev/null
source "$GST_ENV"
set +a
export GST_REGISTRY=/tmp/gst-registry-ti-k3-cma-override.bin
rm -f "$GST_REGISTRY"

filename=$(gst-inspect-1.0 v4l2h264enc 2>/dev/null |
  awk -F'[[:space:]]+' '/^[[:space:]]*Filename[[:space:]]/{print $3; exit}')
[[ "$filename" == "$OVERRIDE" ]] ||
  die "GStreamer did not select the installed override (got: $filename)"

actual_sha=$(sha256sum "$OVERRIDE" | awk '{print $1}')

echo "installed_override=$OVERRIDE"
echo "installed_sha256=$actual_sha"
echo "qualified_live_sha256=$QUALIFIED_SHA256"

if [[ "$actual_sha" == "$QUALIFIED_SHA256" ]]; then
  echo 'PASS: rebuilt plugin matches the final live-qualified binary hash'
else
  echo 'NOTE: rebuilt plugin hash differs from the live qualification build.'
  echo '      Verify the Wave5 720p60 smoke test before using it for OpenHD RF.'
fi

echo
echo 'GStreamer V4L2 CMA override installed. OpenHD remains stopped.'
