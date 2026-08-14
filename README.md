# ti-k3-accelerators

Hardware-qualified TI K3 accelerator platform integration for the **BeagleY-AI**
(TI J722S / AM67A).

This repository turns a clean Armbian BeagleY-AI build into a reusable TI
accelerator platform with:

- source-built Main R5 and C7x Vision Apps firmware
- RPMsg and remoteproc sequencing
- the qualified 4 GiB reserved-memory / DMA-heap contract
- TI TIOVX / VPAC imaging
- TIOVX multiscaler
- Wave5 H.264/H.265 hardware codecs
- IMX219 CSI0 camera support and DCC data
- source-built TI 2A provider
- platform-owned systemd services and `ti-k3-*` validation tools

The accelerator platform is intentionally independent of OpenHD. OpenHD,
wifibroadcast/RF policy, bitrate/GOP policy, radio drivers, and
flight-controller policy belong in consumer projects.

---

## Current qualified baseline: R3 source-built

The current hardware-qualified baseline is:

- Board: **BeagleY-AI**
- SoC: **TI J722S / AM67A**
- Memory: **4 GiB**
- Kernel: `6.12.49-vendor-k3-beagle`
- Distribution: Armbian Noble / Ubuntu 24.04
- TI Processor SDK Linux: `11.02.01.03`
- TI Processor SDK RTOS source: `11.02.01.03`
- Camera qualification: Raspberry Pi **IMX219 on CSI0**
- Qualified source tag: `beagley-ai-r3-source-hw-qualified-20260814`
- Tested TI K3 source commit:
  `83c62656be0a725c691cda8727421cba552c32bf`
- Armbian source commit:
  `259c7b157f9cc7968f077f5483ff0537f691c712`
- Qualified compressed image SHA-256:
  `8e263e15bd7c436bd410b774427db0a50f365810e72f8e6859f9b0f47e0f89e5`

Qualified source-built firmware hashes:

```text
Main R5  fc56b2a0e5110dac22ba3f25e997190aa07ccaf50bee36f21cc1703c61d6c41a
C7x 0    00ddc57e33a02a683c0077d9ef424aa1c3fa6b6a82935f335306052f355cb16b
C7x 1    10f3b472aa7d260c0f978356a12a539f15c5e49297b408f84ee92c66f91600d5
TI 2A    4f7b2acf81511fc0dabf7f61b88b7a7574d153cab435c178b238ecc689e6c567
```

See
[`docs/qualification/BEAGLEY-AI-R3-SOURCE-20260814.md`](docs/qualification/BEAGLEY-AI-R3-SOURCE-20260814.md)
for the complete qualification record.

The immutable qualification tag points to the exact **tested executable source
commit**. This README and the R3 qualification document were committed after
hardware qualification, so they are intentionally not part of the tag target.
Do not move the qualification tag to include later documentation commits.

The previous R2 tag, `beagley-ai-r2-hw-qualified-20260813`, remains frozen as a
historical baseline and must not be moved.

### What the image SHA means

The image SHA identifies the exact `.img.xz` artifact that was flashed and
physically tested. It is **not** a requirement that a later rebuild produce the
same whole-image hash. Package metadata, timestamps, filesystem construction,
and other build-time inputs can change the resulting disk image even when the
source commits are unchanged.

If you rebuild from the qualified source tag, the result is a **new candidate**
until it passes the hardware gates again.

---

## Architecture and ownership

The intended layering is:

```text
Armbian source
  + TI K3 kernel / DT integration
  + fixed J722S 4 GiB memory contract
  + source-built Main R5 / C7x firmware
  + locked TI accelerator userspace
  + source-built TI 2A provider
  + private TIOVX/GStreamer runtime
  + ti-k3-* services and tools
        ↓
physical cold-boot accelerator qualification
        ↓
optional consumer such as OpenHD
```

`ti-k3-accelerators` owns:

- J722S/AM67A kernel configuration and device-tree integration
- the Vision Apps Main R5 / C7x firmware source contract
- firmware aliases and remoteproc sequencing
- RPMsg readiness
- the `j722s-beagley-ai-4gb-r73341` memory map
- carveout DMA heaps and `ti,dma-buf-phys`
- TI TIOVX/OpenVX userspace
- VPAC VISS / TIOVX ISP
- TIOVX multiscaler
- Wave5 H.264/H.265 codecs
- IMX219 CSI0 topology, DCC assets, and graph configuration
- systemd platform services
- `ti-k3-*` diagnostics and qualification helpers

It does **not** own:

- OpenHD application policy
- wifibroadcast/RF policy
- RTL8812AU or other consumer radio policy
- application bitrate/GOP decisions
- telemetry or flight-controller UART policy

See [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) and
[`docs/PORTING-MODEL.md`](docs/PORTING-MODEL.md) for the platform boundary and
porting model.

---

# Start-to-finish setup and build

The following procedure starts from a Linux build host and ends with a
hardware-validated BeagleY-AI accelerator platform.

## 1. Hardware required

For the base accelerator platform:

- BeagleY-AI / J722S / AM67A, 4 GiB configuration
- suitable boot media
- stable power supply

For camera qualification:

- Raspberry Pi IMX219 camera
- camera connected to **CSI0**

Connect or disconnect the camera only while the board is powered off.

## 2. Build-host requirements

Use an x86-64 Linux host with:

- Git
- Docker with a working daemon
- curl
- xz utilities
- standard GNU userland tools
- enough free disk space for Armbian, TI SDK sources, TI rootfs extraction, and
  Docker build layers

Verify the basics:

```bash
git --version
docker --version
docker info
curl --version
xz --version
```

The image wrapper builds through Docker and pins its Ubuntu Noble base image by
digest.

## 3. Obtain the TI Processor SDK RTOS source and tools

The repository does not vendor TI's RTOS SDK or compiler installations. Obtain
the matching official J722S TI Processor SDK RTOS source release and install or
extract it locally.

Required RTOS source release:

```text
TI Processor SDK RTOS J722S 11.02.01.03
```

The firmware build manifest requires these tools:

```text
TI ARM LLVM        4.0.4.LTS
TI C7000 compiler  5.0.0.LTS
TI SysConfig       1.26.2
```

A convenient layout is:

```text
$HOME/ti-sdk-11.02.01/rtos-src/
$HOME/ti/
  ti-cgt-armllvm_4.0.4.LTS/
  ti-cgt-c7000_5.0.0.LTS/
  sysconfig_1.26.2/
```

Set the environment:

```bash
export PSDK_RTOS="$HOME/ti-sdk-11.02.01/rtos-src"
export PSDK_TOOLS_PATH="$HOME/ti"
```

Verify the required inputs exist:

```bash
test -d "$PSDK_RTOS/sdk_builder" && echo "PASS: sdk_builder"
test -d "$PSDK_RTOS/imaging/ti_2a_wrapper" && echo "PASS: imaging/ti_2a_wrapper"
test -x "$PSDK_TOOLS_PATH/ti-cgt-armllvm_4.0.4.LTS/bin/tiarmclang" && echo "PASS: tiarmclang"
test -x "$PSDK_TOOLS_PATH/ti-cgt-c7000_5.0.0.LTS/bin/cl7x" && echo "PASS: cl7x"
test -d "$PSDK_TOOLS_PATH/sysconfig_1.26.2" && echo "PASS: SysConfig"
```

The RTOS SDK tree must also contain the AArch64 Linux cross-toolchain shipped
with the SDK under its `toolchain/sysroots/...` hierarchy. The TI 2A source
builder uses that toolchain to validate the produced AArch64 library.

### Use a clean RTOS source tree

The preparation flow applies the repository's J722S firmware reconstruction
patches directly to the supplied RTOS source tree. For a qualification build,
use a fresh dedicated extraction/copy rather than a shared development tree.

If the tree already contains the canonical application-neutral reconstruction,
`prepare-armbian.sh` recognizes it. If it detects the old temporary
`*_openhd.c` / `OHDBG` reproduction experiment, it refuses to continue; restore
the generic state or use a fresh RTOS tree.

## 4. Clone this repository

For the exact executable source that produced the R3 hardware-qualified image:

```bash
git clone https://github.com/ILAMtitan/ti-k3-accelerators.git
cd ti-k3-accelerators
git checkout beagley-ai-r3-source-hw-qualified-20260814
```

Verify the tag target:

```bash
git rev-list -n 1 beagley-ai-r3-source-hw-qualified-20260814
```

Expected:

```text
83c62656be0a725c691cda8727421cba552c32bf
```

If you are developing beyond the frozen qualification point, use the active
source branch instead of moving the tag.

## 5. Run repository contract checks

Before preparing Armbian:

```bash
bash tests/test-boundary.sh
bash tests/test-contract.sh
bash tests/test-sdk-inputs.sh
```

Expected final lines include:

```text
PASS: TI pass-1 boundary and shell syntax
PASS: TI dependency and ownership contract
PASS: TI SDK application-neutral zero-frozen firmware/2A source-input contract
```

These tests verify ownership boundaries and the source-input contract. They do
not replace physical hardware qualification.

## 6. Clone and pin Armbian

Use a dedicated clean Armbian checkout. `prepare-armbian.sh` intentionally
refuses to overwrite a non-empty `userpatches` tree.

```bash
export ARMBIAN="$HOME/armbian-j722s-ti-k3"
export ARMBIAN_COMMIT=259c7b157f9cc7968f077f5483ff0537f691c712

git clone https://github.com/armbian/build.git "$ARMBIAN"
git -C "$ARMBIAN" checkout "$ARMBIAN_COMMIT"

git -C "$ARMBIAN" rev-parse HEAD
git -C "$ARMBIAN" status -sb
```

The expected Armbian commit is:

```text
259c7b157f9cc7968f077f5483ff0537f691c712
```

## 7. Prepare the Armbian tree

`prepare-armbian.sh` is the source-input handoff into Armbian. It:

1. validates or applies the application-neutral J722S RTOS reconstruction
2. builds Main R5 and both C7x firmware images from the supplied PSDK RTOS tree
3. builds the TI 2A wrapper from `imaging/ti_2a_wrapper`
4. downloads or verifies the exact TI PSDK Linux rootfs archive
5. extracts the TI image into a temporary work area
6. imports only the package/path-locked TI accelerator userspace
7. reconstructs the pinned TI EdgeAI development headers
8. stages source-build provenance for firmware and TI 2A
9. installs this repository's Armbian kernel/DT/config/overlay integration into
   the clean Armbian `userpatches` tree

No frozen Vision Apps firmware directory is accepted. `--firmware` is
intentionally rejected.

Use a disk-backed work area:

```bash
export TI_K3_WORKDIR_BASE="$HOME/ti-k3-work"
mkdir -p "$TI_K3_WORKDIR_BASE"

./prepare-armbian.sh \
    --ti-rtos-src "$PSDK_RTOS" \
    "$ARMBIAN"
```

If the exact TI Linux rootfs archive is already available locally:

```bash
./prepare-armbian.sh \
    --ti-rootfs-archive /path/to/tisdk-adas-image-j722s-evm.tar.xz \
    --ti-rtos-src "$PSDK_RTOS" \
    "$ARMBIAN"
```

The pinned TI Linux archive is:

```text
release: 11.02.01.03
file:    tisdk-adas-image-j722s-evm.tar.xz
SHA256:  01b8e762db99673108b423e8dcb1e5f2c00bdba17359dcd00600b49db030ded4
```

When `--ti-rootfs-archive` is omitted, the script downloads the URL recorded in
`inputs/ti-linux-j722s-11.02.01.03.env` and verifies that SHA-256 before use.

Important successful preparation markers include:

```text
J722S_R2_SOURCE_FIRMWARE_STAGING=PASS
TI_R2_FIRMWARE_SOURCE_INPUT=PASS
TI_2A_SOURCE_BUILD=PASS
TI_2A_SOURCE_INPUT=PASS
TI_USERSPACE_LOCK_IMPORT=PASS
TI_USERSPACE_PROVENANCE_GENERATED=PASS
SOURCE_FIRMWARE_STAGING_BOUNDARY=PASS
TI_K3_ARMBIAN_INPUT_PREPARATION=PASS
```

Some script/file names retain `r2` because they describe the source
reconstruction generation that R3 qualified. They do **not** mean the active
build is using the frozen R2 firmware cohort.

## 8. Inspect the staged source-build contract

Before building the image:

```bash
FW_STAGE="$ARMBIAN/userpatches/overlay/opt/ti-k3-port/firmware-source-build"
TI2A_STAGE="$ARMBIAN/userpatches/overlay/opt/ti-k3-port/ti-2a-provider-source"

cat "$FW_STAGE/SOURCE-BUILD.env"
cat "$FW_STAGE/SHA256SUMS"
cat "$TI2A_STAGE/SOURCE-BUILD.env"
```

The firmware metadata must identify the application-neutral candidate:

```text
build_mode=ti-psdk-rtos-source-built-r2
qualification_status=unqualified_source_candidate
vendor=Texas_Instruments
soc=j722s
memory_map_id=j722s-beagley-ai-4gb-r73341
r5_driver_basename=ti_drivers_config_j722s.c
r5_power_clock_basename=ti_power_clock_config_j722s.c
r5_trace_prefix=J7DBG
```

`qualification_status=unqualified_source_candidate` is intentional. A build
cannot declare itself hardware-qualified before the resulting image has been
flashed and physically tested.

The post-build qualification record/tag is the attestation that promotes an
exact artifact after testing.

## 9. Build the image

Use the repository wrapper so the Armbian host container starts from the pinned
Ubuntu Noble image digest:

```bash
./build-image.sh --jobs "$(nproc)" "$ARMBIAN"
```

The wrapper verifies Docker availability, pulls/tags the pinned container base,
and runs:

```text
./compile.sh build ti-k3-beagley-ai
```

inside Armbian's Docker build path.

The output image is placed under:

```text
$ARMBIAN/output/images/
```

List the generated image and record its hash:

```bash
find "$ARMBIAN/output/images" \
    -maxdepth 1 \
    -type f \
    -name '*.img.xz' \
    -print

sha256sum "$ARMBIAN"/output/images/*.img.xz
```

A newly rebuilt image is a new candidate even if the source commits match the
R3 tag.

### Docker/APT cache troubleshooting

If the Armbian Docker host-image build fails with a Ubuntu package `404 Not
Found` while installing host dependencies, a cached Docker APT layer may be
stale relative to the Ubuntu mirror. Clear the Docker **builder cache** and
retry the image build:

```bash
docker builder prune -af
```

Do not change TI inputs, remove required packages, or pin an obsolete Ubuntu
package revision to work around a transient mirror/cache mismatch.

If preparation already completed successfully, a Docker host-image failure does
not require re-running `prepare-armbian.sh`.

## 10. Flash the image

Flash the generated `.img.xz` to the BeagleY-AI boot media with your preferred
raw-image writer.

Examples include Balena Etcher, Raspberry Pi Imager, or `xz` + `dd`. Be very
careful to select the correct target device if using `dd`; it is destructive.

If you possess the exact R3 qualified image artifact, its compressed SHA-256 is:

```text
8e263e15bd7c436bd410b774427db0a50f365810e72f8e6859f9b0f47e0f89e5
```

A different hash does not automatically mean the build is wrong; it means it
is a different artifact and therefore needs its own qualification if it will
be treated as a frozen baseline.

## 11. Optional: select IMX219 on CSI0

The generic accelerator platform does **not** automatically claim a camera.
This is deliberate so headless and non-camera consumers can use the same base.

For the qualified camera configuration:

1. power the board off
2. connect the IMX219 to **CSI0**
3. boot the board
4. select the IMX219 CSI0 overlay

```bash
sudo ti-k3-select-camera-overlay imx219 0
sync
sudo poweroff
```

The helper removes stale package-managed camera/EdgeAI overlays and selects:

```text
k3-am67a-beagley-ai-csi0-imx219.dtbo
```

After shutdown, **physically remove power and reapply it**.

A warm `reboot` is not accepted as the remote-firmware qualification cold-boot
gate.

## 12. Cold-boot platform validation

Do not manually write to:

```text
/sys/class/remoteproc/*/state
```

The platform services own remoteproc startup and RPMsg sequencing.

After a complete physical cold power cycle, inspect the installed provenance:

```bash
cat /var/lib/ti-k3/platform.env
cat /var/lib/ti-k3/vision-apps-source-build.env
sha256sum -c /etc/ti-k3/vision-apps-firmware.sha256
```

Check the platform services:

```bash
systemctl --failed --no-pager
systemctl status ti-k3-accelerators.target --no-pager
systemctl status ti-k3-remoteproc-prepare.service --no-pager
```

Read-only remoteproc inspection:

```bash
for r in /sys/class/remoteproc/remoteproc*; do
    echo "[$r]"
    printf 'name='; cat "$r/name" 2>/dev/null
    printf 'firmware='; cat "$r/firmware" 2>/dev/null
    printf 'state='; cat "$r/state" 2>/dev/null
    echo
done
```

For the Vision Apps cohort, the qualified state is:

```text
remoteproc2  Main R5   j722s-main-r5f0_0-fw  running
remoteproc3  C7x 0     j722s-c71_0-fw         running
remoteproc4  C7x 1     j722s-c71_1-fw         running
```

Then run the public acceptance tools:

```bash
sudo ti-k3-memory-map-verify
sudo ti-k3-rpmsg-ready
sudo ti-k3-wave5-verify
sudo ti-k3-self-test
```

`ti-k3-self-test` must report PASS for:

```text
memory-map verification
RPMsg readiness
Wave5 verification
firmware hashes
GStreamer tiovxisp
GStreamer tiovxmultiscaler
GStreamer v4l2h264enc
GStreamer v4l2h264dec
GStreamer v4l2h265enc
GStreamer v4l2h265dec
```

Do not install a higher-level consumer such as OpenHD until this base gate
passes.

## 13. IMX219 CSI0 validation

After the CSI0 overlay is selected and the board has completed the physical
cold boot, run:

```bash
sudo ti-k3-test-imx219 detect
sudo ti-k3-test-imx219 raw
sudo ti-k3-test-imx219 isp
sudo ti-k3-test-imx219 encode
```

The current helper configures the IMX219 media graph before raw/ISP/encode tests
and performs a raw stream preflight. This prevents an unconfigured media graph
from producing a misleading camera result.

Expected raw path:

```text
IMX219
  -> Cadence CSI2RX bridge
  -> TI J721E CSI2RX
  -> 1920x1080 RGGB / SRGGB8_1X8 @ ~30 fps
```

Expected ISP path:

```text
IMX219 CSI0
  -> 1920x1080 RGGB @ 30 fps
  -> TIOVX ISP / VPAC VISS
  -> 1920x1080 NV12 @ 30 fps
```

Expected full accelerator path:

```text
IMX219 CSI0
  -> 1920x1080 RGGB @ 30 fps
  -> TIOVX ISP / VPAC VISS
  -> 1920x1080 NV12
  -> TIOVX MultiScaler
  -> 1280x720 NV12 @ 30 fps
  -> Wave5 v4l2h264enc
  -> H.264 byte-stream / AU alignment
```

The R3 qualification observed approximately 30.01 fps on the raw stream and
completed the ISP and full encode paths successfully.

The camera contract is published at:

```text
/run/ti-k3/camera.env
/run/ti-k3/camera-video
/run/ti-k3/camera-subdev
```

## 14. Qualification acceptance criteria

A candidate is not a hardware-qualified platform merely because it builds.
For the R3-equivalent accelerator/camera scope, require all of the following
after a physical cold boot:

```text
source-built firmware hashes           PASS
Main R5 running                         PASS
C7x 0 running                           PASS
C7x 1 running                           PASS
RPMsg endpoints 13/21                   PASS
memory-map verification                 PASS
TI K3 self-test                         PASS
Wave5 runtime                           PASS
IMX219 CSI0 detect                      PASS
IMX219 raw 1920x1080 RGGB ~30 fps       PASS
TIOVX ISP 1920x1080 NV12                PASS
TIOVX multiscaler 1280x720              PASS
Wave5 H.264 encode                      PASS
```

For a new frozen baseline, record at minimum:

- TI K3 source commit
- Armbian source commit
- compressed image SHA-256
- Main R5 SHA-256
- both C7x SHA-256 values
- TI 2A provider SHA-256
- physical cold-boot result
- camera/accelerator results for the declared qualification scope

Do not move an existing qualification tag to a later commit. Create a new
qualification record/tag for a new artifact or source state.

---

# What changes from stock Armbian

## Kernel and device-tree integration

The platform adds the BeagleY-AI/J722S pieces required by the TI accelerator
stack, including:

- CSI camera integration
- BeagleY-AI camera overlays
- reserved-memory integration
- carveout DMA heap support
- `ti,dma-buf-phys`
- Wave5 codec configuration
- IMX219 / Cadence CSI2RX / TI J721E CSI2RX support
- required remoteproc modules

The relevant files are under:

```text
armbian/userpatches/kernel/archive/k3-beagle-6.12/
armbian/userpatches/extensions/ti-k3-accelerators.sh
```

## Fixed J722S 4 GiB memory contract

Vision Apps remote firmware, RPMsg, TIOVX, DMA heaps, and Linux must agree on
the same DDR layout. The platform therefore uses an explicit qualified memory
profile rather than dynamically rearranging carveouts at runtime.

Primary sources:

```text
profiles/memory/j722s-beagley-ai-4gb.json
armbian/userpatches/kernel/archive/k3-beagle-6.12/dt/
```

Live validation:

```bash
sudo ti-k3-memory-map-verify
```

## Source-built Main R5 and C7x firmware

The production source contract is application-neutral:

```text
generated/ti_drivers_config_j722s.c
generated/ti_power_clock_config_j722s.c
J7DBG
```

Historical OpenHD-specific `_openhd.c` basenames and `OHDBG` strings were used
only in a source-reproduction experiment. They are not part of the permanent
TI accelerator firmware contract.

The required firmware aliases remain:

```text
j722s-main-r5f0_0-fw -> vision_apps_evm/vx_app_rtos_linux_mcu2_0.out
j722s-c71_0-fw       -> vision_apps_evm/vx_app_rtos_linux_c7x_1.out
j722s-c71_1-fw       -> vision_apps_evm/vx_app_rtos_linux_c7x_2.out
```

The R3 source-built firmware is hardware-qualified on its own merits. The Main
R5 is intentionally not required to be byte-identical to the older R2 Main R5
load image.

## Locked TI accelerator userspace

TI accelerator userspace is imported from the exact official PSDK Linux
`11.02.01.03` `tisdk-adas-image-j722s-evm` archive.

The repository uses:

```text
inputs/ti-linux-j722s-11.02.01.03.env
inputs/ti-j722s-11.02.01.03-userspace-files.lock
inputs/ti-j722s-11.02.01.03-userspace-packages.lock
scripts/import-ti-userspace-locked.sh
```

The importer rejects distribution-core replacement libraries so Armbian/Noble
remains the Linux distribution rather than being overwritten by the TI rootfs.

Additional development headers are reconstructed from pinned TI sources using:

```text
inputs/ti-edgeai-development-headers.env
inputs/ti-edgeai-development-headers.lock
scripts/import-ti-edgeai-development-headers.sh
```

## Source-built TI 2A provider

`build-ti-2a-provider-from-psdk.sh` builds the J722S imaging target and discovers
the freshly produced AArch64 provider defining:

```text
TI_2A_wrapper_create
TI_2A_wrapper_process
TI_2A_wrapper_delete
```

The source-built R3 provider SHA-256 is:

```text
4f7b2acf81511fc0dabf7f61b88b7a7574d153cab435c178b238ecc689e6c567
```

It reproduced the historical provider byte-for-byte, but the active build path
uses the freshly built source output rather than a frozen copy.

## Private TIOVX/GStreamer runtime

The image keeps the normal Armbian/Noble multimedia stack and publishes the TI
compatibility runtime separately. Consumers that need TI elements use:

```text
/etc/ti-k3/gstreamer.env
```

The selected compatibility plugin is built from pinned Texas Instruments source
when required by the Noble integration.

## Platform-owned remoteproc startup

Applications must not start/stop Vision Apps remote cores themselves.

The platform owns the sequence through:

```text
ti-k3-accelerators.target
ti-k3-remoteproc-prepare.service
ti-k3-remote-log.service
ti-k3-wave5-prepare.service
```

The Main R5 endpoint is established before the delayed C7x startup/readiness
sequence.

Never use warm manual remoteproc restarts as a substitute for qualification.

---

# Troubleshooting

## `prepare-armbian.sh` rejects non-empty `userpatches`

Use a fresh dedicated Armbian checkout. The script intentionally refuses to
merge this platform into an unknown pre-existing userpatch tree during a
qualification build.

## RTOS tree reports historical OpenHD reproduction state

The permanent firmware source contract is `_j722s.c` + `J7DBG`. Do not convert
historical experiment files in-place during a qualification build. Use a fresh
matching TI PSDK RTOS source tree or restore the canonical application-neutral
state first.

## Docker build gets Ubuntu package 404s

If the failure occurs while constructing Armbian's Docker host environment and
shows an obsolete Ubuntu package revision, clear the Docker builder cache:

```bash
docker builder prune -af
```

Then rerun `build-image.sh`. Do not alter the TI firmware/userspace inputs for a
host-container APT cache problem.

## `Unexpected TI 2A source-build identity`

The canonical SoC identity is lowercase:

```text
soc=j722s
```

Current builds and contract tests enforce the same identity from the firmware
manifest through the TI 2A producer and image consumer.

## IMX219 is not detected after flashing

A newly flashed image does not automatically select a camera overlay. On the
board:

```bash
sudo ti-k3-select-camera-overlay imx219 0
sync
sudo poweroff
```

Then physically remove and reapply power.

## Raw camera stream reports `Broken pipe`

Current `ti-k3-test-imx219 raw|isp|encode` configures and verifies the media
graph before the main test. If diagnosing manually, run:

```bash
sudo ti-k3-configure-imx219-graph --verify-stream
```

Do not treat a `v4l2-ctl` zero exit status as sufficient if its output reports a
stream-on error. The current qualification helper explicitly checks for these
errors.

## Remoteproc trouble

Inspect state read-only:

```bash
for r in /sys/class/remoteproc/remoteproc*; do
    echo "$r"
    cat "$r/name" "$r/firmware" "$r/state" 2>/dev/null
done
```

Do not manually write `start`, `stop`, or firmware names into remoteproc sysfs
during qualification. A full physical cold power cycle is the required reset
boundary.

---

# Useful installed commands

```text
ti-k3-info
ti-k3-memory-map-verify
ti-k3-rpmsg-ready
ti-k3-self-test
ti-k3-wave5-verify
ti-k3-find-camera-devices
ti-k3-configure-imx219-graph
ti-k3-select-camera-overlay
ti-k3-test-imx219 detect
ti-k3-test-imx219 raw
ti-k3-test-imx219 isp
ti-k3-test-imx219 encode
```

Useful service status commands:

```bash
systemctl status ti-k3-accelerators.target
systemctl status ti-k3-remoteproc-prepare.service
systemctl status ti-k3-wave5-prepare.service
systemctl status ti-k3-remote-log.service
systemctl status ti-k3-imx219-prepare.service
```

---

# Source and provenance model

The R3 production build path uses:

```text
pinned Armbian source
+ this repository
+ official TI PSDK Linux 11.02.01.03 image
+ official TI PSDK RTOS 11.02.01.03 source
+ pinned TI/public source dependencies
+ TI compiler/SysConfig tools
        ↓
source-built Main R5 + C7x firmware
source-built TI 2A provider
locked TI accelerator userspace
private TI/TIOVX compatibility runtime
        ↓
bootable Armbian accelerator image
```

Historical frozen firmware and forensic reference files are retained only as
evidence/reference material. They are not required production build inputs for
R3.

"Zero-frozen" in this repository refers specifically to removing the historical
frozen Vision Apps firmware and TI 2A provider from the required build path. It
does not claim that an entire Linux image is hermetically or byte-for-byte
reproducible across time.

---

# Repository layout

```text
armbian/userpatches/   Armbian kernel, DT, config, services, tools, image integration
inputs/                locked TI Linux and development-header inputs
scripts/               TI input extraction/import and TI 2A source-build tools
profiles/              board, SoC, and memory profiles
firmware/              J722S firmware reconstruction patches/build/staging tools
reference/r73341/      historical/forensic qualification reference material
tests/                  static ownership and source-input contract tests
docs/                   architecture, porting, test plans, qualification records
prepare-armbian.sh      prepare a clean Armbian checkout from source inputs
build-image.sh          build through the pinned Docker/Armbian environment
```

Repository checks:

```bash
bash tests/test-boundary.sh
bash tests/test-contract.sh
bash tests/test-sdk-inputs.sh
```

Git provides integrity/versioning for repository files; the repository does not
maintain a second whole-tree checksum manifest.

---

# Further documentation

- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) — platform layers and ownership
- [`docs/PORTING-MODEL.md`](docs/PORTING-MODEL.md) — SoC/board/memory separation
- [`docs/PASS1-TEST-PLAN.md`](docs/PASS1-TEST-PLAN.md) — standalone accelerator
  acceptance plan
- [`docs/qualification/BEAGLEY-AI-R3-SOURCE-20260814.md`](docs/qualification/BEAGLEY-AI-R3-SOURCE-20260814.md)
  — current R3 source-built hardware qualification
- [`docs/qualification/BEAGLEY-AI-R2-20260813.md`](docs/qualification/BEAGLEY-AI-R2-20260813.md)
  — historical frozen R2 qualification

---

# OpenHD consumer

OpenHD is layered on top only after the accelerator platform passes its own
qualification gates. The consumer integration lives in:

`ILAMtitan/openhd-k3-integration`

That repository consumes the public `ti-k3-*` platform contract and does not
own or warm-restart the TI remote processors.
