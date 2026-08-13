# ti-k3-accelerators

Hardware-qualified TI K3 accelerator platform integration for the **BeagleY-AI**
(TI J722S / AM67A).

This repository turns a clean Armbian build into a reusable TI accelerator
platform with the remote-core firmware contract, RPMsg, reserved-memory/DMA
heaps, TIOVX/VPAC imaging, Wave5 video codecs, and IMX219 camera support needed
by higher-level applications such as OpenHD.

The accelerator platform is intentionally independent of OpenHD. Application,
RF, bitrate/GOP, and telemetry policy belong in consumer projects.

## Current qualified baseline

The current hardware-qualified baseline is:

- Board: BeagleY-AI
- SoC: TI J722S / AM67A
- Memory: 4 GiB
- Kernel: `6.12.49-vendor-k3-beagle`
- TI Processor SDK Linux: `11.02.01.03`
- Camera: Raspberry Pi IMX219 on **CSI0**
- Qualified tag: `beagley-ai-r2-hw-qualified-20260813`
- Qualified image SHA-256:
  `ac9925a9192e20c44b5cdc618ce8099bda53339e930d2d0be0ccc16377a363c4`

The image itself is not stored in Git. See
[`docs/qualification/BEAGLEY-AI-R2-20260813.md`](docs/qualification/BEAGLEY-AI-R2-20260813.md)
for the full qualification record.

## What this repository owns

`ti-k3-accelerators` owns the reusable platform layer:

- J722S/AM67A kernel configuration and device-tree integration
- the qualified Vision Apps remote-firmware contract
- Main R5 / C7x remoteproc sequencing
- RPMsg readiness and validation
- the R2 reserved-memory map
- carveout DMA heaps and `ti,dma-buf-phys`
- TI TIOVX/OpenVX userspace
- VPAC VISS / TIOVX ISP and multiscaler
- Wave5 H.264/H.265 hardware codec enablement
- IMX219 camera topology, DCC data, and validation helpers
- systemd platform services and `ti-k3-*` diagnostic tools

It does **not** own OpenHD, wifibroadcast/RF policy, RTL8812AU policy, video
bitrate/GOP policy, or flight-controller UART policy.

## Quick start: build the qualified Armbian platform

### 1. Prerequisites

Use a Linux build host with Git, Docker, curl, xz, and enough free disk space
for an Armbian build and the TI SDK root filesystem.

You also need:

1. a clean Armbian build checkout
2. the frozen hardware-qualified R2 firmware staging directory
3. this repository at the qualified tag or an intentionally newer revision

The qualified Armbian source commit is:

```text
259c7b157f9cc7968f077f5483ff0537f691c712
```

Clone the two repositories:

```bash
git clone https://github.com/ILAMtitan/ti-k3-accelerators.git
cd ti-k3-accelerators
git checkout beagley-ai-r2-hw-qualified-20260813

cd ..
git clone https://github.com/armbian/build.git armbian-build
git -C armbian-build checkout 259c7b157f9cc7968f077f5483ff0537f691c712
```

### 2. Prepare the Armbian tree

`prepare-armbian.sh` reconstructs the TI userspace from locked TI SDK inputs,
imports the pinned TI development headers, verifies the frozen firmware hashes,
and installs the Armbian userpatches.

If the official TI rootfs archive is not supplied, the script downloads the
exact archive recorded in `inputs/ti-linux-j722s-11.02.01.03.env` and verifies
its SHA-256.

For large temporary extraction work, use a disk-backed work directory:

```bash
export TI_K3_WORKDIR_BASE="$HOME/ti-k3-work"
mkdir -p "$TI_K3_WORKDIR_BASE"

./prepare-armbian.sh \
    --firmware /path/to/qualified-r2-firmware-staging \
    /path/to/armbian-build
```

If the TI rootfs archive is already available locally:

```bash
./prepare-armbian.sh \
    --ti-rootfs-archive /path/to/tisdk-adas-image-j722s-evm.rootfs.tar.xz \
    --firmware /path/to/qualified-r2-firmware-staging \
    /path/to/armbian-build
```

The preparation step refuses to overwrite a non-empty Armbian `userpatches`
tree.

### 3. Build the image

The wrapper uses the pinned Docker/Ubuntu Noble environment used for the
qualified build:

```bash
./build-image.sh --jobs "$(nproc)" /path/to/armbian-build
```

The resulting image is written by Armbian under `output/images/`.

For development, the prepared Armbian tree can also be built directly:

```bash
cd /path/to/armbian-build
./compile.sh build ti-k3-beagley-ai
```

### 4. Flash and perform a physical cold boot

Flash the generated image to the BeagleY-AI boot media using your normal image
writer.

For hardware qualification, use a **complete physical power cycle**. A warm
`reboot` is not considered equivalent.

Do not manually write to:

```text
/sys/class/remoteproc/*/state
```

The platform services own the qualified remoteproc sequence.

## IMX219 on CSI0

The generic accelerator target boots without automatically starting the static
camera preparation service. Select the CSI0 IMX219 overlay once:

```bash
sudo ti-k3-select-camera-overlay imx219 0
sync
sudo poweroff
```

After the board is fully powered down, remove/reapply power.

Then validate the platform and camera:

```bash
systemctl --failed --no-pager
systemctl status ti-k3-accelerators.target --no-pager

sudo ti-k3-memory-map-verify
sudo ti-k3-rpmsg-ready
sudo ti-k3-self-test

sudo systemctl start ti-k3-imx219-prepare.service

sudo ti-k3-test-imx219 detect
sudo ti-k3-test-imx219 raw
sudo ti-k3-test-imx219 isp
sudo ti-k3-test-imx219 encode
```

The qualified `encode` path is:

```text
IMX219 CSI0
  -> 1920x1080 RGGB @ 30 fps
  -> TIOVX ISP / VPAC VISS
  -> 1920x1080 NV12
  -> TIOVX MultiScaler
  -> 1280x720 NV12 @ 30 fps
  -> Wave5 H.264
```

The camera contract is published under:

```text
/run/ti-k3/camera.env
/run/ti-k3/camera-video
/run/ti-k3/camera-subdev
```

The private TI GStreamer runtime is exported by:

```text
/etc/ti-k3/gstreamer.env
```

## Useful platform commands

```bash
ti-k3-info
ti-k3-memory-map-verify
ti-k3-rpmsg-ready
ti-k3-self-test
ti-k3-wave5-verify
ti-k3-find-camera-devices
ti-k3-test-imx219 detect
```

Service status:

```bash
systemctl status ti-k3-accelerators.target
systemctl status ti-k3-remoteproc-prepare.service
systemctl status ti-k3-wave5-prepare.service
systemctl status ti-k3-remote-log.service
systemctl status ti-k3-imx219-prepare.service
```

## Source and provenance model

The platform deliberately separates several provenance classes:

- TI accelerator userspace is reconstructed from the official TI PSDK Linux
  `11.02.01.03` `tisdk-adas-image` using package/path identity locks.
- additional EdgeAI development headers are reconstructed from pinned Texas
  Instruments source repositories.
- the active TIOVX compatibility plugin is built from pinned
  `TexasInstruments/edgeai-gst-plugins` source when the release plugin does not
  provide every required factory.
- the remote-core binaries remain the frozen hardware-qualified R2 firmware
  cohort; an independent RTOS rebuild did not reproduce every binary
  bit-for-bit and is not substituted into the qualified image.

The current release does not claim that every remaining third-party or RTOS
build input has completed strict source-origin hardening. The qualification
document records the remaining provenance work separately.

## Repository layout

- `armbian/userpatches/` - kernel, DT, systemd, and image integration
- `inputs/` - locked TI Linux and development-header inputs
- `scripts/` - deterministic TI input extraction/import tools
- `profiles/` - board, SoC, and memory profiles
- `reference/r73341/` - qualified/historical reference material
- `tests/` - static ownership and source-input contract tests
- `docs/` - architecture, porting notes, test plans, and qualification records
- `prepare-armbian.sh` - prepare a clean Armbian checkout
- `build-image.sh` - build with the pinned container environment

## Repository checks

Run the static checks before publishing changes:

```bash
bash tests/test-boundary.sh
bash tests/test-contract.sh
bash tests/test-sdk-inputs.sh
sha256sum -c SHA256SUMS
```

## OpenHD consumer

OpenHD is layered on top only after this platform is qualified. The consumer
integration lives in:

https://github.com/ILAMtitan/openhd-k3-integration

That repository consumes the public `ti-k3-*` APIs and does not own or
warm-restart the TI remote processors.
