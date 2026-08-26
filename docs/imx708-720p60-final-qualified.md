# IMX708 720p60 accelerator final qualification

Date: 2026-08-26

This checkpoint freezes the accelerator-side state used for the successful
end-to-end OpenHD RF qualification of the Arducam B0310 / Sony IMX708 on
BeagleY-AI / J722S.

## Sensor and ISP

Qualified sensor contract:

- CSI0
- 1536x864 RAW10
- ~60 fps sensor-native cadence
- VBLANK 946
- DCC compatibility sensor `SENSOR_SONY_IMX219_RPI`
- AE/AWB disabled
- manual exposure 1280
- analogue gain 512
- digital gain 256

The VISS output is 1536x864 NV12 at 60 fps. `tiovxmultiscaler target=0`
produces 1280x720 NV12 at 60 fps. VISS pool sizes are 2/2.

## Wave5

The final smoke pipeline uses:

- 1280x720p60
- H.264 Baseline Level 3.2
- 6,000,000 bit/s
- GOP 30
- one-buffer downstream-leaky queue

## GStreamer encoded-buffer CMA fix

Ubuntu Noble `gstreamer1.0-plugins-good` 1.24.2 used the V4L2 driver's maximum
codec dimensions when calculating encoded `sizeimage`. Wave5 advertises an
8192-pixel maximum, which caused GStreamer to request a 33,554,432-byte
encoded buffer during the otherwise-correct 720p encoder startup.

The final checkpoint backports the functional TI meta-arago fix: calculate
encoded `sizeimage` from the negotiated stream width and height.

Build and install the isolated override with:

```sh
sudo ./scripts/build-install-gstreamer-v4l2-cma-override.sh
```

The override is installed at:

`/opt/ti-k3/gstreamer-overrides/gstreamer-1.0/libgstvideo4linux2.so`

and `/etc/ti-k3/gstreamer.env` places it before both TI runtime plugin paths.

The plugin used during final RF qualification had SHA-256:

`85fee44325de66cd0ddb6e4470dc45d8282c82726a1ee9cbe147b220e4c46af1`

A rebuild may have a different binary hash; in that case the 600-frame Wave5
smoke is the qualification gate.

## Qualification order

```sh
sudo ./scripts/install-imx708-720p60-live.sh --dcc-dir scripts/out/1536x864
sudo ti-k3-configure-imx708-graph --mode 864p60 --verify-stream --verify-frames 600
sudo env FRAMES=600 ti-k3-imx708-viss-smoke
sudo env FRAMES=600 ti-k3-imx708-wave5-720p60-smoke
```

The Wave5 run must show no 33,554,432-byte / 8192-page CMA allocation failure.
After that, the matching `openhd-k3-integration` checkpoint can be installed
and RF-qualified.
