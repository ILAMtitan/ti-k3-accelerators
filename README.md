# ti-k3-accelerators

Hardware-qualified TI K3 accelerator platform integration for the **BeagleY-AI**
(TI J722S / AM67A).

This repository owns the platform layer used by OpenHD and other consumers:
remoteproc/RPMsg sequencing, the reserved-memory and DMA-heap contract, TI
TIOVX/VPAC imaging, multiscaler, Wave5 hardware codecs, camera device-tree
integration, camera graph preparation, and platform-level validation tools.

## Current main baseline: Camera R4 unified selection

`main` now contains the R4 unified camera-selection package.

Final R4 checkpoint:

```text
tag:     camera-r4-unified-20260902
commit:  b32d11e99040042677ce318dcbf51b4c066ec529
version: 0.4.0-camera-r4
```

R4 carries forward the previously qualified accelerator platform and unifies the
three supported BeagleY-AI camera paths behind one boot-time selector and one
runtime contract.

| Camera | OpenHD type | Port | Qualified input mode | Boot overlay |
| --- | ---: | --- | --- | --- |
| IMX219 | 150 | CSI1 | existing pre-R4 path | `ti/k3-am67a-beagley-ai-csi1-imx219.dtbo` |
| IMX708 / Arducam B0310 | 151 | CSI0 | 1536x864 RAW10 @ 60 fps | `ti/k3-am67a-beagley-ai-csi0-arducam-b0310.dtbo` |
| IMX415 / Arducam B0569 | 152 | CSI0 | 3864x2192 RAW10 @ ~30 fps | `ti/k3-am67a-beagley-ai-csi0-arducam-b0569-imx415-37.dtbo` |

R4 qualification on 2026-09-02 demonstrated the unified boundary with IMX415
and a physical IMX415 -> IMX708 camera/overlay transition. IMX219 remains
supported through the existing path, but a new physical IMX219 transition was
not run before the R4 checkpoint was frozen.

See
[`docs/qualification/BEAGLEY-AI-CAMERA-R4-UNIFIED-SELECTION-20260902.md`](docs/qualification/BEAGLEY-AI-CAMERA-R4-UNIFIED-SELECTION-20260902.md)
for the final R4 qualification record. Older qualification records remain under
`docs/qualification/` as immutable historical checkpoints.

## Camera selection

Camera selection is intentionally a **boot-time** operation because the sensor,
CSI routing, reset GPIOs, clocks, and media endpoints are device-tree state.

```bash
sudo ti-k3-camera-select status
sudo ti-k3-camera-select list
sudo ti-k3-camera-select imx219
sudo ti-k3-camera-select imx708
sudo ti-k3-camera-select imx415
```

The selector writes the persistent choice to:

```text
/etc/ti-k3/camera.conf
```

and updates only known camera overlay tokens in `/boot/uEnv.txt`, preserving
unrelated overlays. A reboot is required whenever the selected camera overlay
changes.

After boot, the generic camera service prepares the selected graph:

```bash
sudo systemctl start ti-k3-camera-prepare.service
systemctl status ti-k3-camera-prepare.service --no-pager
cat /run/ti-k3/camera.env
```

The common application-facing contract is:

```text
/run/ti-k3/camera.env
/run/ti-k3/camera-video
/run/ti-k3/camera-subdev
```

If the configured sensor and the sensor actually probed by Linux do not match,
R4 fails preparation rather than silently configuring the wrong graph.

The old `ti-k3-imx219-prepare.service` is retained only as a compatibility alias
to `ti-k3-camera-prepare.service` for older consumers.

## R4 live install on an existing qualified platform

For an already-qualified BeagleY-AI platform, install the R4 orchestration layer
without automatically starting or reconfiguring the camera:

```bash
sudo ./scripts/install-camera-r4-live.sh
```

To install and immediately run the generic camera prepare service:

```bash
sudo ./scripts/install-camera-r4-live.sh --start
```

R4 does not replace the underlying source-built TI firmware, memory-map, TIOVX,
DMA-heap, or Wave5 qualification requirements.

## Architecture and ownership

The intended layering is:

```text
Armbian / Beagle kernel
  + TI K3 DT and memory integration
  + source-built Main R5 / C7x firmware
  + TI accelerator userspace
  + DMA heaps / dma-buf-phys
  + TIOVX / VPAC / multiscaler / Wave5
  + selected camera graph and /run/ti-k3 contract
        ↓
consumer application such as OpenHD
```

`ti-k3-accelerators` owns:

- J722S/AM67A kernel and device-tree integration
- Vision Apps Main R5 / C7x firmware source contract
- remoteproc and RPMsg readiness
- reserved-memory / DMA-heap contract
- TI TIOVX/OpenVX runtime
- VPAC VISS and multiscaler
- Wave5 H.264/H.265 platform integration
- IMX219, IMX708, and IMX415 camera platform integration
- boot-time camera selection and graph preparation
- platform systemd services and `ti-k3-*` diagnostics

It does **not** own OpenHD application policy, RF/wifibroadcast policy,
application bitrate/GOP choices, or flight-controller integration.

See [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) and
[`docs/PORTING-MODEL.md`](docs/PORTING-MODEL.md) for the platform boundary.

## Verification

Repository-side selector test:

```bash
bash tests/test-camera-selector.sh
```

Target-side R4 checks:

```bash
ti-k3-camera-select status
sudo systemctl restart ti-k3-camera-prepare.service
cat /run/ti-k3/camera.env
readlink -f /run/ti-k3/camera-video
readlink -f /run/ti-k3/camera-subdev
```

For camera-specific qualification and historical performance results, use the
records under `docs/qualification/` and the camera-specific smoke/preflight
helpers under `armbian/userpatches/overlay/usr/local/sbin/`.

## Recovery points

The current R4 recovery point is the annotated tag:

```text
camera-r4-unified-20260902
```

That tag remains fixed at the tested R4 checkpoint commit. Documentation merged
after the checkpoint may advance `main`; do not move the tag to include later
documentation-only commits.
