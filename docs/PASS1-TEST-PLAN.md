# Pass-1 standalone accelerator qualification

Pass 1 proves that a normal Armbian image exposes the complete reusable TI K3
accelerator platform with OpenHD and other application consumers absent.

The current hardware-qualified reference is R3:

- tag: `beagley-ai-r3-source-hw-qualified-20260814`
- tested TI K3 source commit: `83c62656be0a725c691cda8727421cba552c32bf`
- BeagleY-AI / J722S / AM67A, 4 GiB
- source-built Main R5 and both C7x firmware images
- source-built TI 2A provider
- IMX219 camera qualification on CSI0

A newly rebuilt image is a new qualification candidate even when it is built
from the qualified source tag.

## 1. Optional camera selection before the cold-boot gate

The generic accelerator platform does not automatically claim a camera. If the
candidate will be qualified for the R3 IMX219 camera scope, connect the IMX219
to CSI0 while powered off, boot once, and select the overlay:

```bash
sudo ti-k3-select-camera-overlay imx219 0
sync
sudo poweroff
```

After shutdown, physically remove and reapply power.

If camera qualification is not in scope, leave the camera unselected and
continue with the base accelerator gates below.

## 2. Physical cold boot

Qualification starts from a complete physical power cycle. A warm `reboot` is
not a substitute for this gate.

Do not manually write to:

```text
/sys/class/remoteproc/*/state
```

The platform services own Vision Apps remoteproc startup and sequencing.

## 3. Base accelerator gate

After the untouched cold boot, verify installed provenance and platform state:

```bash
cat /var/lib/ti-k3/platform.env
cat /var/lib/ti-k3/vision-apps-source-build.env
sha256sum -c /etc/ti-k3/vision-apps-firmware.sha256

systemctl --failed --no-pager
systemctl status ti-k3-accelerators.target --no-pager
systemctl status ti-k3-remoteproc-prepare.service --no-pager

ti-k3-info
ti-k3-memory-map-verify
ti-k3-rpmsg-ready --wait 120
ti-k3-wave5-verify
ti-k3-self-test
```

Read-only remoteproc inspection is allowed:

```bash
for r in /sys/class/remoteproc/remoteproc*; do
    echo "[$r]"
    printf 'name='; cat "$r/name" 2>/dev/null
    printf 'firmware='; cat "$r/firmware" 2>/dev/null
    printf 'state='; cat "$r/state" 2>/dev/null
    echo
done
```

For the Vision Apps cohort, require:

```text
remoteproc2  Main R5   j722s-main-r5f0_0-fw  running
remoteproc3  C7x 0     j722s-c71_0-fw         running
remoteproc4  C7x 1     j722s-c71_1-fw         running
```

The remoteproc preparation log must show Main R5 endpoint 13 ready before the
10-second C7x delay, followed by endpoints 13 and 21 on Main R5 and both C7x
cores.

## 4. Codec gate

Exercise the standalone Wave5 codec paths:

```bash
ti-k3-test-wave5-codecs h264
ti-k3-test-wave5-codecs h265
```

The base self-test must also report PASS for the TIOVX ISP/multiscaler factories
and Wave5 H.264/H.265 encode/decode factories.

## 5. IMX219 CSI0 gate

When IMX219 camera qualification is in scope, run the corrected camera helper:

```bash
ti-k3-test-imx219 detect
ti-k3-test-imx219 raw
ti-k3-test-imx219 isp
ti-k3-test-imx219 encode
```

The helper configures and verifies the IMX219 media graph before raw, ISP, and
encode tests. It must not report a raw PASS when V4L2 output contains a stream-on
error such as `Broken pipe`.

Required R3-equivalent camera path:

```text
IMX219 CSI0
  -> Cadence CSI2RX bridge
  -> TI J721E CSI2RX
  -> 1920x1080 RGGB / SRGGB8_1X8 @ ~30 fps
  -> TIOVX ISP / VPAC VISS
  -> 1920x1080 NV12 @ 30 fps
  -> TIOVX MultiScaler
  -> 1280x720 NV12 @ 30 fps
  -> Wave5 H.264
```

## 6. Application-boundary gate

OpenHD must not be required for the standalone platform to pass. The reusable
TI K3 layer owns kernel/DT integration, memory, remoteproc/RPMsg, TIOVX, Wave5,
and optional camera preparation; application RF/video/telemetry policy remains
outside this repository.

A source/package review should find no active OpenHD dependency in the generic
platform services or tools. Historical/forensic references retained only as
provenance evidence are not active application dependencies.

## Acceptance

For the full R3-equivalent accelerator + IMX219 scope, require:

```text
source-built firmware hashes           PASS
Main R5 running                         PASS
C7x 0 running                           PASS
C7x 1 running                           PASS
RPMsg endpoints 13/21                   PASS
memory-map verification                 PASS
TI K3 self-test                         PASS
Wave5 H.264/H.265 codec tests           PASS
IMX219 CSI0 detect                      PASS
IMX219 raw 1920x1080 RGGB ~30 fps       PASS
TIOVX ISP 1920x1080 NV12                PASS
TIOVX multiscaler 1280x720              PASS
Wave5 H.264 encode                      PASS
OpenHD/application independence         PASS
```

Only after the declared Pass-1 scope succeeds after a physical cold boot should
OpenHD or another higher-level consumer be installed.

For the exact frozen R3 hardware result, see
`docs/qualification/BEAGLEY-AI-R3-SOURCE-20260814.md`.
