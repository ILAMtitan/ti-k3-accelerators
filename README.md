# ti-k3-accelerators — split pass 1

This is the first mechanical extraction of the **hardware-proven R7.33.4.1
BeagleY-AI/J722S accelerator stack** from the OpenHD image project.


## Pass 1 r0.3 correction

r0.2 successfully published the TIOVX GStreamer plugin in the private
`/opt/ti-k3/runtime/current` tree, but several generic diagnostics/tests invoked
`gst-inspect-1.0` or `gst-launch-1.0` without importing `/etc/ti-k3/gstreamer.env`.
That made `tiovxisp` and `tiovxmultiscaler` appear absent even though the private
plugin had been validated during image construction. r0.3 keeps the runtime
private and explicitly imports that environment in the relevant tools and the
IMX219 preparation service.

## Scope of pass 1

Supported now:

- SoC: TI J722S / AM67A
- Board: BeagleY-AI
- Memory: 4 GiB profile only
- exact hardware-proven Vision Apps R5/C7x firmware contract
- main-R5 first remoteproc sequence and 10 s C7x delay
- RPMsg endpoints 13/21 qualification
- TIOVX/OpenVX userspace and private GStreamer runtime
- VPAC VISS / multiscaler
- Wave5 H.264/H.265 hardware encode and decode
- IMX219 DCC and generic camera bring-up helpers
- carveout DMA heap and TI DMA-BUF physical exporter

Explicitly **not owned by this project**:

- OpenHD binaries or OpenHD-SysUtils
- OpenHD RF/monitor/injection policy
- RTL8812AU
- CC33xx management-WiFi policy
- RTP port 5500 or OpenHD camera bitrate/GOP policy
- flight-controller UART policy

Pass 1 intentionally accepts the frozen R7.33.4.1 forensic staging format as an
input. Rebuilding the firmware from source is a later, separate reproducibility
lane. The public runtime API is `ti-k3-*`; the historical staging metadata may
still contain old `openhd-*` identifiers because those strings are part of the
forensic contract and are not rewritten.

## Build model

This pass is deliberately not one-click:

1. Supply the frozen TI 11.02.01.03 J722S target-rootfs staging tree. `prepare-armbian.sh` filters it down to accelerator-specific userspace; the full TI distribution is never copied into the image.
2. Supply the frozen R7.33.4.1 forensic firmware staging tree.
3. Run `./prepare-armbian.sh ... /path/to/armbian-build`.
4. Build `ti-k3-beagley-ai` through `./build-image.sh`, which preserves the pinned Docker/Ubuntu-Noble Armbian build environment used by the frozen Alpha.
5. Boot the resulting image and qualify it **without OpenHD installed**.

See `docs/PASS1-TEST-PLAN.md`.

## Legacy forensic input boundary

Pass 1 intentionally accepts the immutable R7.33.4.1 staging format as an input,
including its historical `.openhd-ti-vendor-bundle.env`, memory-map identifier,
and source-tree paths. Image customization immediately normalizes those artifacts
into `/var/lib/ti-k3`, `/usr/share/ti-k3`, and `/usr/lib/ti-k3-build-only`. No
installed TI K3 service or public tool depends on OpenHD. Acquisition/rebuild of
these inputs is deliberately deferred to the reproducibility phase.


## r0.4 camera-contract fix

Camera device rediscovery now atomically republishes the complete `/run/ti-k3/camera.env` contract. Earlier pass-1 revisions could truncate DCC, CSI I/O-mode, and TIOVX pool fields after `ti-k3-test-imx219`, even though the camera tests themselves passed via fallback defaults.
