#!/usr/bin/env bash
set -Eeuo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
# Active TI tree must not contain OpenHD application/RF ownership. Historical
# forensic metadata lives only under reference/ and is excluded here.
#
# TI CC33xx kernel/firmware platform enablement is allowed here; the ownership
# boundary prohibits application/RF policy such as monitor-mode/injection,
# OpenHD services, or the legacy UDP video transport.
if grep -RniE 'rtl8812|openhd\.service|udp.*5500|port[ =]5500|radio-watch|monitor.mode|injection' \
    "$root/armbian" "$root/profiles" --exclude='*.patch' 2>/dev/null; then
  echo 'TI boundary violation' >&2; exit 1
fi
for f in $(find "$root" -type f -name '*.sh' -o -path '*/usr/local/sbin/*'); do
  [[ -x $f || $f == *.sh ]] || continue
  bash -n "$f"
done
echo 'PASS: TI pass-1 boundary and shell syntax'
