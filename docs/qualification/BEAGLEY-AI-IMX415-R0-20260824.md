# BeagleY-AI / Arducam B0569 IMX415 R0 pre-hardware integration

Date: 2026-08-24

This branch prepares the IMX415 path before the Arducam B0569 is available in
the live development environment. **R0 is not hardware qualified.** It is
additive to the qualified IMX708 R1 checkpoint.

## Confirmed source/vendor facts

For the exact Beagle kernel source ref `v6.12.49-ti-arm64-r56`:

- driver: `drivers/media/i2c/imx415.c`
- compatible: `sony,imx415`
- full driver frame: `3864x2192`
- raw format: `MEDIA_BUS_FMT_SGBRG10_1X10` (GBRG RAW10)
- supplies requested: `dvdd`, `ovdd`, `avdd`
- 2- and 4-lane CSI-2 endpoints are accepted
- 24 MHz is a supported INCK
- supported 2-lane fast mode uses 1.44 Gb/s lane rate, represented in DT as
  `link-frequencies = <720000000>`
- that mode reports virtual `pixel_rate=304615385` and approximately 30.019 fps
- VBLANK is fixed at 58 in this driver
- analogue gain range is 0..100
- reset is optional
- sensor model ID is 0x514

Arducam identifies SKU B0569 as its 8.3 MP Sony IMX415 open-source camera and
publishes a B0569-specific libcamera tuning profile. Arducam describes the
sensor active area as 3840x2160; the kernel driver exposes the surrounding
3864x2192 all-pixel frame.

The upstream Raspberry Pi IMX415 overlay defaults to I2C 0x37 and 24 MHz, but
also supports multiple IMX415 address straps. R0 therefore does not claim the
B0569 address until it is measured on the actual module.

## R0 device-tree strategy

Two CSI0 overlays are built:

- `k3-am67a-beagley-ai-csi0-arducam-b0569-imx415-37.dtbo`
- `k3-am67a-beagley-ai-csi0-arducam-b0569-imx415-1a.dtbo`

Both use:

- BeagleY-AI CSI0 / `main_i2c2`
- 24 MHz fixed input clock
- 2 CSI lanes
- 720 MHz V4L2 link frequency (1.44 Gb/s lane rate)
- existing `cdns_csi2rx0` -> `ti_csi2rx0` topology
- no extra EdgeAI memory-map overlay

`reset-gpios` is intentionally omitted until B0569 connector/reset wiring is
confirmed. The three driver supply requests are provisionally parented to
`vdd_3v3` on the assumption that the integrated module contains its required
sensor rail regulation. Check that assumption on hardware before R1.

Use `ti-k3-select-imx415-overlay --address 0x37` or `--address 0x1a`; changing
the sensor DT requires a reboot.

## R0 capture contract

`ti-k3-configure-imx415-graph` expects the fast mode and rejects a different
pixel rate by default.

Expected contract:

```
sensor       imx415
SKU          arducam-b0569
input        3864x2192 SGBRG10
rate         ~30 fps
V4L2 fourcc  GB10
GStreamer    gbrg10le
TIOVX caps   gbrg10
format-msb   9
```

The qualified RAW10LE TIOVX compatibility runtime inherited from IMX708 R1 can
be reused: it aliases all four Bayer `*10le` names, including `gbrg10le`, to
the legacy TI 16-bit raw container.

## DCC / ISP R0

`scripts/build-imx415-default-dcc.sh` generates an untuned full-frame profile:

- geometry: 3864x2192
- Bayer: GBRG (`COLOR_PATTERN 2`)
- RAW10
- black-level starting point: 50 in 10-bit units
- compatibility DCC ID: 219

The black-level value matches the kernel driver's default and is only a
bring-up starting point.

As with IMX708 R1, `SENSOR_SONY_IMX219_RPI` is used only as the available TI
registry/DCC slot. AE and AWB remain disabled because the deployed TI plugin
has IMX219-specific sensor-control mapping. Native IMX415 2A is future work.

## Proposed OpenHD R0 path

The matching OpenHD branch is `imx415-r0-20260824` in
`ILAMtitan/openhd-k3-integration`.

Initial FPV pipeline:

```
IMX415 3864x2192 GBRG10 ~30
  -> CSI0 / CSI2RX
  -> VPAC/VISS 3864x2192 NV12
  -> TIOVX multiscaler
  -> 1280x720 NV12 @ 30
  -> queue depth 1 / leaky downstream
  -> Wave5 H.264 @ 6 Mbit/s, GOP 15
  -> OpenHD RTP MTU 1024
```

The 3864x2192 driver frame is slightly different in aspect ratio from 16:9, so
direct scaling to 1280x720 introduces a very small geometry change. R1 should
qualify a centered 3840x2160 crop/ROI before scaling if the TIOVX multiscaler
crop controls are suitable.

## Live information required for R1

Collect these before enabling the OpenHD path:

1. Kernel support:
   ```
   grep CONFIG_VIDEO_IMX415 /boot/config-$(uname -r)
   modinfo imx415
   ```
2. Confirm the actual `main_i2c2` Linux bus and probe the B0569 address before
   binding if practical. Determine whether it is 0x37, 0x1a, or another strap.
3. Select the matching overlay and reboot once.
4. After reboot:
   ```
   dmesg | grep -i imx415
   media-ctl -d /dev/media0 -p
   v4l2-ctl -d <imx415-subdev> --list-ctrls-menus
   v4l2-ctl -d <imx415-subdev> --get-ctrl=link_frequency,pixel_rate
   ```
5. Confirm context 0 is present and capture fourcc is `GB10`.
6. Run:
   ```
   ti-k3-configure-imx415-graph --verify-stream --verify-frames 300
   ```
   Record elapsed time and dmesg delta. Expected duration is about 10 seconds.
7. Confirm module power/reset behavior across a real cold boot. If probe is
   unreliable, determine whether MCU_GPIO0_15 is wired to B0569 XCLR or a
   module power-enable and add the correct polarity instead of guessing.
8. Generate/install the R0 DCC pair, then run `ti-k3-imx415-viss-smoke`.
9. If VISS passes, test VISS -> multiscaler -> Wave5 locally before OpenHD RF.
10. Record manual exposure/gain only after live testing; do not copy IMX708
    values because IMX415 uses different control units and ranges.

## R0 status

- kernel/source analysis: prepared
- CSI0 DT address variants: prepared, not boot-tested
- RAW graph helper: prepared, not hardware-tested
- TIOVX RAW10LE compatibility: inherited from qualified IMX708 runtime
- default DCC generator: prepared, not yet generated/validated for IMX415
- VISS smoke pipeline: prepared, not hardware-tested
- OpenHD type/pipeline: prepared in matching repo branch, not hardware-tested
- physical RF video: not tested
