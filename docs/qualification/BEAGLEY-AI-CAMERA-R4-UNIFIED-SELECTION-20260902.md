# TI K3 unified camera selection R4

R4 unifies the three BeagleY-AI/OpenHD camera paths without changing their
qualified media pipelines:

| Sensor | OpenHD camera type | Port | Boot overlay |
| --- | ---: | --- | --- |
| IMX219 | 150 | CSI1 | `ti/k3-am67a-beagley-ai-csi1-imx219.dtbo` |
| IMX708 | 151 | CSI0 | `ti/k3-am67a-beagley-ai-csi0-arducam-b0310.dtbo` |
| IMX415 | 152 | CSI0 | `ti/k3-am67a-beagley-ai-csi0-arducam-b0569-imx415-37.dtbo` |

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

A reboot is required when the selected DT overlay changes.

`ti-k3-camera-prepare.service` reads the persistent selection, prepares the
selected media graph, validates that the probed sensor matches the selection,
and publishes the common application contract:

- `/run/ti-k3/camera.env`
- `/run/ti-k3/camera-video`
- `/run/ti-k3/camera-subdev`

If no persistent selection exists (for migration from R3), the prepare layer
will auto-detect exactly one already-probed supported sensor. Once the user
runs `ti-k3-camera-select`, configured-vs-detected mismatch becomes a hard
startup error.

The old `ti-k3-imx219-prepare.service` is retained as a compatibility alias and
now pulls in the generic camera prepare service. This allows the older OpenHD
consumer installer to operate while the OpenHD R4 integration layer is being
qualified.
