# TI K3 unified camera selection R4 — final checkpoint 2026-09-02

R4 unifies the three BeagleY-AI/OpenHD camera paths behind one persistent,
boot-time selector without changing the established camera-specific media
pipelines.

## Frozen checkpoint

```text
repository: ILAMtitan/ti-k3-accelerators
tag:        camera-r4-unified-20260902
commit:     b32d11e99040042677ce318dcbf51b4c066ec529
version:    0.4.0-camera-r4
base R3:    8b036b3e12ca0ccfc5fdf8990cf4ecbe5def5f3f
```

The annotated tag is the immutable R4 recovery point. The R4 branch was
fast-forward merged into `main` after qualification. Documentation-only commits
may therefore make `main` newer than the tag; the tag must not be moved.

## Supported camera map

| Sensor | OpenHD type | Port | Boot overlay | R4 status |
| --- | ---: | --- | --- | --- |
| IMX219 | 150 | CSI1 | `ti/k3-am67a-beagley-ai-csi1-imx219.dtbo` | Supported; not physically re-qualified during final R4 transition testing |
| IMX708 / Arducam B0310 | 151 | CSI0 | `ti/k3-am67a-beagley-ai-csi0-arducam-b0310.dtbo` | R4 selector/prepare qualified |
| IMX415 / Arducam B0569 | 152 | CSI0 | `ti/k3-am67a-beagley-ai-csi0-arducam-b0569-imx415-37.dtbo` | R4 selector/prepare qualified |

The B0569 0x37 overlay is the physically qualified IMX415 variant in this
checkpoint. The alternate 0x1a overlay remains available as development input
but is not the qualified R4 selection.

## R4 architecture

Camera selection is intentionally boot-time because the sensor identity, CSI
routing, reset GPIOs, clocks, and endpoints are device-tree state.

The user-facing selector is:

```bash
ti-k3-camera-select list
ti-k3-camera-select status
sudo ti-k3-camera-select imx219
sudo ti-k3-camera-select imx708
sudo ti-k3-camera-select imx415
```

Persistent selection is stored in:

```text
/etc/ti-k3/camera.conf
```

The selector changes only known camera tokens in `/boot/uEnv.txt` `name_overlays`
and preserves unrelated overlays. If the selected overlay changes, the selector
reports that a reboot is required.

At boot/runtime, `ti-k3-camera-prepare.service` invokes the generic camera setup
path and publishes the common contract:

```text
/run/ti-k3/camera.env
/run/ti-k3/camera-video
/run/ti-k3/camera-subdev
```

A configured-vs-detected sensor mismatch is a hard failure. The old
`ti-k3-imx219-prepare.service` remains only as a compatibility alias that pulls
in `ti-k3-camera-prepare.service`.

## Qualification results

### IMX415 — qualified

The already-booted IMX415 was first adopted into R4 without changing its active
DT state. The selector correctly reported the migration state and then persisted
IMX415 as the selected sensor.

The first generic prepare attempt exposed an R4 software bug in the IMX415 media
entity parser. This kernel's `media-ctl` output prefixes entity lines with
`- entity`; the parser originally expected the line to begin directly with
`entity`. The fix accepts both forms and is included in the final R4 checkpoint.

After the parser fix, generic prepare succeeded with:

```text
sensor:      imx415
media:       /dev/media0
subdev:      /dev/v4l-subdev2
video:       /dev/video2
mode:        3864x2192 RAW10 @ ~30 fps
pixel_rate:  304615385
```

The generic service successfully completed its four-frame RAW preflight.

A longer hardware smoke test captured 120 RAW frames at 30.02 fps:

```text
raw_rc=0
elapsed_s=5
30.02 fps
runtime_status=suspended
```

No new IMX415, STREAMON, I2C, or CSI errors were observed. The sensor returned
to runtime-suspended state after capture.

### Physical IMX415 -> IMX708 transition — qualified

R4 then selected IMX708, updated the persistent camera selection and boot
overlay, and the board was completely powered off for the physical camera swap.
After boot with the Arducam B0310 on CSI0, the generic service automatically
selected the IMX708 graph without a camera-specific manual setup command.

Qualified generic contract:

```text
TI_K3_CAMERA_DETECTED_SENSOR=imx708
TI_K3_CAMERA_SKU=arducam-b0310
TI_K3_CAMERA_MEDIA_DEVICE=/dev/media0
TI_K3_CAMERA_VIDEO_DEVICE_REAL=/dev/video2
TI_K3_CAMERA_SUBDEV_DEVICE_REAL=/dev/v4l-subdev2
TI_K3_CAMERA_MODE=864p60
TI_K3_CAMERA_WIDTH=1536
TI_K3_CAMERA_HEIGHT=864
TI_K3_CAMERA_FPS=60
TI_K3_CAMERA_VBLANK=946
TI_K3_CAMERA_MBUS_FORMAT=SRGGB10_1X10
TI_K3_CAMERA_V4L2_FORMAT=RG10
```

The service's four-frame RAW10 streaming verification passed and the final
configured/detected state was:

```text
configured=imx708
detected=imx708
```

The matching OpenHD R4 integration layer subsequently mapped this physical
sensor to camera type 151 and reached the native IMX708 OpenHD pipeline in
`PLAYING` state. See the paired R4 qualification document in
`ILAMtitan/openhd-k3-integration`.

### IMX219 — supported, not newly R4-qualified

IMX219 remains part of the R4 selector and generic setup dispatch as camera type
150 on CSI1. The final package was frozen before performing a new physical
IMX219 transition. Do not describe IMX219 as newly R4-qualified; its existing
pre-R4 camera path remains supported.

## Scope and non-goals

R4 is primarily an orchestration release. Except for the IMX415 entity-name
parser correction, it does not retune the established sensor modes, DCC data,
TIOVX image processing, multiscaler behavior, Wave5 behavior, or camera-specific
media graphs.

R4 does not change OpenHD RTP fragmentation, appsink policy, RF policy, or ground
receiver behavior. Those are consumer/application concerns and remain outside
this repository's platform ownership boundary.

## Main-branch integration

The final R4 branch:

```text
camera-r4-unified-camera-selection-20260902
```

was strictly ahead of `main` with no divergent commits, so it was merged by
fast-forward. `main` is now the normal development baseline for unified camera
selection.

For exact reproduction or recovery, use the immutable tag instead of relying on
the moving `main` branch:

```bash
git checkout camera-r4-unified-20260902
```
