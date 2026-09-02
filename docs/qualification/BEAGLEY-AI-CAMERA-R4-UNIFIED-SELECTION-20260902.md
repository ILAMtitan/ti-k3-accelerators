# TI K3 unified camera selection R4 — final checkpoint 2026-09-02

R4 unifies the three BeagleY-AI/OpenHD camera paths behind one persistent,
boot-time selector without changing the established camera media pipelines.

| Sensor | OpenHD camera type | Port | Boot overlay | R4 status |
| --- | ---: | --- | --- | --- |
| IMX219 | 150 | CSI1 | `ti/k3-am67a-beagley-ai-csi1-imx219.dtbo` | Supported; not re-qualified during the R4 checkpoint |
| IMX708 | 151 | CSI0 | `ti/k3-am67a-beagley-ai-csi0-arducam-b0310.dtbo` | R4 selector/prepare qualified |
| IMX415 | 152 | CSI0 | `ti/k3-am67a-beagley-ai-csi0-arducam-b0569-imx415-37.dtbo` | R4 selector/prepare qualified |

Camera selection is intentionally boot-time. `ti-k3-camera-select` replaces
only known camera entries in `name_overlays`, preserves unrelated overlays,
and writes the persistent selection to `/etc/ti-k3/camera.conf`.

Examples:

```sh
ti-k3-camera-select status
sudo ti-k3-camera-select imx219
sudo ti-k3-camera-select imx708
sudo ti-k3-camera-select imx415
```

A reboot is required when the selected DT overlay changes. Physical CSI camera
changes are performed only with the board powered off.

`ti-k3-camera-prepare.service` reads the persistent selection, prepares the
selected media graph, validates that the probed sensor matches the selection,
and publishes the common application contract:

- `/run/ti-k3/camera.env`
- `/run/ti-k3/camera-video`
- `/run/ti-k3/camera-subdev`

If no persistent selection exists, the R3 migration path can auto-detect one
already-probed supported sensor. After `ti-k3-camera-select` has been used, a
configured-vs-detected mismatch is a hard startup error.

The old `ti-k3-imx219-prepare.service` remains only as a compatibility alias
which pulls in `ti-k3-camera-prepare.service`.

## R4 qualification results

### IMX415 / Arducam B0569 / CSI0

R4 was installed on the existing IMX415 R3-qualified AIR unit. The selector
correctly recognized the already-booted IMX415 overlay and the persistent
selection was adopted without changing the active DT state.

The first generic prepare attempt exposed one integration bug: Beagle 6.12
`media-ctl` prefixes entity list rows with `- entity`, while the IMX415 helper
parser expected `entity` at the start of the row. R4 commit
`043defea933aaf40c00e5978bfbc1d856abb2539` fixes that parser while leaving the
IMX415 graph and sensor mode unchanged.

After the parser fix:

- `ti-k3-camera-prepare.service` completed successfully.
- Sensor resolved as `imx415 4-0037` on `/dev/media0`.
- Capture node resolved to `/dev/video2`.
- Sensor subdevice resolved to `/dev/v4l-subdev2`.
- Pixel rate remained the qualified `304615385` value.
- Four-frame RAW10 prepare preflight passed.
- Independent 120-frame RAW10 check passed at 30.02 fps.
- The 120-frame check completed in about 5 seconds.
- IMX415 runtime PM returned to `suspended` after capture closed.
- No new IMX415, STREAMON, I2C `-EREMOTEIO`, or CSI errors were observed.

This preserves the R3 IMX415 reset/runtime-resume qualification while moving
camera orchestration to the generic R4 service.

### IMX708 / Arducam B0310 / CSI0

The AIR unit was then changed from IMX415 to IMX708 using only the R4 selector,
a complete power-off camera swap, and the subsequent boot. The generic prepare
service reported `configured=imx708 detected=imx708` and produced the expected
qualified IMX708 contract:

- `/dev/media0`
- `/dev/video2`
- `/dev/v4l-subdev2`
- mode `864p60`
- sensor RAW10 `1536x864@60`
- `VBLANK=946`
- `SRGGB10_1X10` / `RG10`
- IMX708 1536x864 VISS and 2A DCC paths

The four-frame RAW10 prepare preflight passed. The OpenHD-side type-151 handoff
was also exercised successfully; see the matching R4 qualification document in
`ILAMtitan/openhd-k3-integration`.

### IMX219

IMX219 support is retained in the same R4 dispatch and selector layer, but the
user elected to freeze the R4 package before performing a new physical IMX219
transition. Do not describe IMX219 as newly R4-qualified. Its pre-existing
camera path remains available as type 150 on CSI1.

## Scope

R4 is an orchestration release. Except for the IMX415 entity-name parser fix,
it does not retune the sensor modes, DCC configuration, TIOVX processing, or
camera-specific graph behavior established before R4.

Canonical R4 branch:

`camera-r4-unified-camera-selection-20260902`

R4 starts from the IMX415 R3 stability checkpoint
`8b036b3e12ca0ccfc5fdf8990cf4ecbe5def5f3f`.
