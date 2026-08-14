# ti-k3-accelerators

Hardware-qualified TI K3 accelerator platform integration for the **BeagleY-AI**
(TI J722S / AM67A).

This repository documents and automates the changes required to turn a clean
Armbian BeagleY-AI build into a reusable TI accelerator platform with the
remote-core firmware contract, RPMsg, reserved-memory/DMA heaps, TIOVX/VPAC
imaging, Wave5 video codecs, and IMX219 camera support needed by higher-level
applications such as OpenHD.

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
for the frozen qualification record.

## Platform layering and ownership

The intended layering is:

```text
stock Armbian source
  -> BeagleY-AI kernel / DT integration
  -> qualified memory + remote-firmware contract
  -> TI accelerator userspace + private TIOVX/GStreamer runtime
  -> ti-k3-* systemd services and public tools
  -> physical cold-boot accelerator qualification
  -> optional consumer such as OpenHD
```

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

For the architectural boundary and porting model, see
[`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) and
[`docs/PORTING-MODEL.md`](docs/PORTING-MODEL.md).

## What must change from stock Armbian

The build scripts apply these changes automatically. They are listed here so a
new platform port can be understood and reviewed rather than treated as a
black-box image build.

### 1. Kernel and device-tree support

**Why:** stock BeagleY-AI support does not by itself provide the complete
hardware contract used by the qualified J722S Vision Apps/TIOVX/Wave5 stack.
The accelerator platform needs the correct CSI topology, camera overlays,
reserved-memory layout, DMA heap/exporter support, and codec/camera modules.

**Implementation:**

- `armbian/userpatches/kernel/archive/k3-beagle-6.12/0001-*` — BeagleY-AI CSI
  camera I2C integration.
- `0002-*` — board mux integration required by the BeagleY-AI display/CSI routing.
- `0003-*` — builds the BeagleY-AI camera overlays and avoids relying on generic
  EdgeAI-composed DTBs.
- `0006-*` — backports the TI `dma-buf-phys` exporter used by the accelerator
  memory contract.
- `armbian/userpatches/kernel/archive/k3-beagle-6.12/dt/` — BeagleY-AI DT
  supplements, the qualified 4 GiB R2 memory map, and camera-overlay source.
- `armbian/userpatches/extensions/ti-k3-accelerators.sh` — enables the required
  media, DMA heap, Wave5, IMX219, CSI2RX, CC33xx, and CMA kernel configuration.

**Validation:** the finished image must expose `ti,dma-buf-phys`, the exact R2
reserved-memory regions, the expected media/remoteproc modules, and the
BeagleY-AI IMX219 overlay. The frozen result is recorded in the qualification
document.

### 2. A fixed 4 GiB memory contract

**Why:** Vision Apps remote firmware, RPMsg, TIOVX, DMA heaps, and Linux must
all agree on the same DDR layout. This cannot be safely inferred or rearranged
at runtime.

**Implementation:**

- `profiles/memory/j722s-beagley-ai-4gb.json`
- `armbian/userpatches/kernel/archive/k3-beagle-6.12/dt/k3-am67a-beagley-ai-ti-k3-edgeai-memory-map.dtsi`
- `ti-k3-memory-map-verify`

The memory profile is explicit and hardware-qualified; it is not a dynamic
"use whatever RAM is available" policy.

**Validation:**

```bash
sudo ti-k3-memory-map-verify
```

### 3. Qualified Main R5 and C7x firmware

**Why:** the Linux host only works if the Vision Apps firmware, firmware aliases,
linker placement, and memory map match. The independent source rebuild did not
reproduce every remote binary bit-for-bit, so the hardware-qualified cohort is
the deployment authority.

**Implementation:** `prepare-armbian.sh` verifies the exact Main R5 and two C7x
hashes before staging them. `customize-image.sh` installs the cohort and writes
`/etc/ti-k3/vision-apps-firmware.sha256`.

The required aliases are:

```text
j722s-main-r5f0_0-fw -> vision_apps_evm/vx_app_rtos_linux_mcu2_0.out
j722s-c71_0-fw       -> vision_apps_evm/vx_app_rtos_linux_c7x_1.out
j722s-c71_1-fw       -> vision_apps_evm/vx_app_rtos_linux_c7x_2.out
```

**Validation:** firmware identity is checked during image construction and again
by the live platform qualification tools.

### 4. TI accelerator userspace on top of Armbian/Noble

**Why:** TIOVX, imaging, DCC, RPMsg support libraries, and TI GStreamer elements
are not supplied by normal Armbian/Noble packages.

**Implementation:**

- `inputs/ti-linux-j722s-11.02.01.03.env` pins the official TI PSDK Linux image.
- `inputs/ti-j722s-11.02.01.03-userspace-files.lock` and
  `inputs/ti-j722s-11.02.01.03-userspace-packages.lock` define the allowed TI
  payload.
- `scripts/import-ti-userspace-locked.sh` imports only the locked accelerator
  assets and rejects distribution-core replacement libraries.
- `inputs/ti-edgeai-development-headers.*` and
  `scripts/import-ti-edgeai-development-headers.sh` reconstruct the required
  development headers from pinned TI sources.

This keeps Armbian/Noble as the Linux distribution while adding only the TI
accelerator payload that the platform actually needs.

### 5. Private TIOVX/GStreamer compatibility runtime

**Why:** the release TI userspace is the provenance baseline, but the active
Armbian/Noble integration requires a source-built compatibility plugin exposing
the factories used by the qualified pipeline.

**Implementation:** `customize-image.sh` invokes the `ti-k3-build-*` helpers in
`armbian/userpatches/overlay/usr/local/sbin/` and publishes the selected runtime
under the TI K3 namespace. Consumers source:

```text
/etc/ti-k3/gstreamer.env
```

The original TI release plugin remains preserved; the selected compatibility
plugin is built from pinned Texas Instruments source.

**Validation:** `ti-k3-self-test` verifies the runtime and required TIOVX
factories.

### 6. Platform-owned remoteproc startup and RPMsg readiness

**Why:** remote-core startup order is part of the qualified firmware/memory
contract. Applications must not race firmware startup or manipulate remoteproc
sysfs themselves.

**Implementation:**

```text
ti-k3-accelerators.target
  -> ti-k3-remoteproc-prepare.service
  -> ti-k3-remote-log.service
  -> ti-k3-wave5-prepare.service
```

The service/helper layer lives under
`armbian/userpatches/overlay/etc/systemd/system/` and
`armbian/userpatches/overlay/usr/local/sbin/`.

The qualified sequence brings up the Main R5 contract before the delayed C7x
portion and waits for the required RPMsg endpoints.

**Validation:**

```bash
sudo ti-k3-rpmsg-ready
sudo ti-k3-self-test
```

Do not manually write `/sys/class/remoteproc/*/state`.

### 7. IMX219 CSI0 + DCC + hardware video path

**Why:** the air-camera pipeline requires a known sensor topology, TI imaging
calibration data, TIOVX ISP/multiscaler, and Wave5 H.264 working together.

**Implementation:** the image contains the BeagleY-AI IMX219 overlay, camera
setup/discovery helpers, DCC assets under `/opt/imaging/imx219/`, and
`ti-k3-imx219-prepare.service`.

The generic accelerator target does not automatically claim a camera; camera
preparation is an explicit optional service so non-camera consumers remain
valid.

**Validation:** use the staged IMX219 tests described below.

## Step-by-step: build the qualified Armbian platform

### Step 1 — Prepare the build host

Use a Linux build host with Git, Docker, curl, xz, and enough free disk space
for an Armbian build and the TI SDK root filesystem.

You need:

1. this repository
2. a clean Armbian build checkout
3. the frozen hardware-qualified R2 firmware staging directory

The qualified Armbian source commit is:

```text
259c7b157f9cc7968f077f5483ff0537f691c712
```

### Step 2 — Clone and pin the sources

```bash
git clone https://github.com/ILAMtitan/ti-k3-accelerators.git
cd ti-k3-accelerators
git checkout beagley-ai-r2-hw-qualified-20260813

cd ..
git clone https://github.com/armbian/build.git armbian-build
git -C armbian-build checkout 259c7b157f9cc7968f077f5483ff0537f691c712
```

Use the qualified tag when reproducing the frozen hardware result. Use a newer
branch only when intentionally validating newer integration work.

### Step 3 — Reconstruct the TI inputs and prepare Armbian

`prepare-armbian.sh` is the handoff from upstream inputs into the Armbian build.
It:

1. verifies the qualified remote-firmware hashes
2. obtains or verifies the exact TI PSDK Linux rootfs archive
3. extracts the TI image to a temporary work area
4. reconstructs the package/path-locked TI userspace payload
5. reconstructs the pinned TI development headers
6. copies this repository's Armbian kernel/DT/config/overlay integration into a
   clean `userpatches/` tree
7. stages the frozen remote firmware separately from the Linux userspace payload

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

The script refuses to overwrite a non-empty Armbian `userpatches` tree. Use a
dedicated clean Armbian checkout rather than merging unrelated userpatches into
a qualification build.

### Step 4 — Build the image

The wrapper uses the pinned Docker/Ubuntu Noble build environment:

```bash
./build-image.sh --jobs "$(nproc)" /path/to/armbian-build
```

The resulting image is written by Armbian under `output/images/`.

For development, the prepared Armbian tree can also be built directly:

```bash
cd /path/to/armbian-build
./compile.sh build ti-k3-beagley-ai
```

During image customization, `armbian/userpatches/customize-image.sh` installs the
locked TI payload, installs/verifies the frozen firmware, validates the combined
DT/camera memory contract and DCC files, builds the private TI GStreamer runtime,
and enables `ti-k3-accelerators.target`.

### Step 5 — Flash the image

Flash the generated image to BeagleY-AI boot media using your normal raw-image
writer. When reproducing the qualified image, compare the compressed artifact
SHA-256 to the value in the qualification record.

### Step 6 — Select IMX219 on CSI0

The platform itself can run without a camera. For the qualified camera path,
select the CSI0 IMX219 overlay once:

```bash
sudo ti-k3-select-camera-overlay imx219 0
sync
sudo poweroff
```

### Step 7 — Perform a complete physical cold power cycle

After the board is fully powered down, remove and reapply power.

A warm `reboot` is **not** considered equivalent for remote-firmware
qualification. Do not manually write to:

```text
/sys/class/remoteproc/*/state
```

The platform services own the qualified sequence.

### Step 8 — Validate the accelerator platform before the camera

```bash
systemctl --failed --no-pager
systemctl status ti-k3-accelerators.target --no-pager

sudo ti-k3-memory-map-verify
sudo ti-k3-rpmsg-ready
sudo ti-k3-self-test
sudo ti-k3-wave5-verify
```

For the standalone acceptance criteria, see
[`docs/PASS1-TEST-PLAN.md`](docs/PASS1-TEST-PLAN.md). Do not install OpenHD until
this accelerator-only gate passes.

### Step 9 — Prepare and validate IMX219 on CSI0

```bash
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

The camera service publishes the application-facing contract under:

```text
/run/ti-k3/camera.env
/run/ti-k3/camera-video
/run/ti-k3/camera-subdev
```

### Step 10 — Freeze the accelerator base before adding an application

Once memory, RPMsg, TIOVX, Wave5, and the desired camera path pass after a
physical cold boot, treat that image as the platform baseline. Higher-level
applications should consume the `ti-k3-*` API rather than modify firmware,
remoteproc, memory carveouts, or the TI runtime.

The OpenHD consumer is maintained separately in
`ILAMtitan/openhd-k3-integration`.

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

- `armbian/userpatches/` - kernel, DT, systemd, tools, and image integration
- `inputs/` - locked TI Linux and development-header inputs
- `scripts/` - deterministic TI input extraction/import tools
- `profiles/` - board, SoC, and memory profiles
- `firmware/` - current R2 source-reconstruction support; deployed firmware is
  still the frozen hardware-qualified cohort described above
- `reference/r73341/` - qualified/historical reference material
- `tests/` - static ownership and source-input contract tests
- `docs/` - architecture, porting notes, standalone test plan, and qualification
  records
- `prepare-armbian.sh` - prepare a clean Armbian checkout
- `build-image.sh` - build with the pinned container environment

## Repository checks

Run the contract checks before publishing changes:

```bash
bash tests/test-boundary.sh
bash tests/test-contract.sh
bash tests/test-sdk-inputs.sh
```

These tests protect ownership boundaries and locked external inputs. Git itself
provides integrity/versioning for ordinary repository files, so the repository
does not maintain a second whole-tree checksum manifest.

## Further documentation

- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) — platform layers, ownership,
  and why applications consume stable services/tools instead of internals.
- [`docs/PORTING-MODEL.md`](docs/PORTING-MODEL.md) — how SoC, board, and memory
  profiles are separated for future K3 targets.
- [`docs/PASS1-TEST-PLAN.md`](docs/PASS1-TEST-PLAN.md) — accelerator-only
  acceptance before any consumer is installed.
- [`docs/qualification/BEAGLEY-AI-R2-20260813.md`](docs/qualification/BEAGLEY-AI-R2-20260813.md)
  — exact qualified sources, artifact hashes, firmware identities, and hardware
  results.

## OpenHD consumer

OpenHD is layered on top only after this platform is qualified. The consumer
integration lives in:

https://github.com/ILAMtitan/openhd-k3-integration

That repository consumes the public `ti-k3-*` APIs and does not own or
warm-restart the TI remote processors.
