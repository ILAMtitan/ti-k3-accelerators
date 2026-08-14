# TI K3 accelerator architecture

`ti-k3-accelerators` is the reusable hardware/platform layer between a normal
Armbian distribution and accelerator-consuming applications such as OpenHD.
Its purpose is to make the J722S/AM67A accelerator stack look like a stable
Linux platform contract instead of a collection of board-specific firmware,
remoteproc, memory, imaging, and codec details that every application must know.

## Design rule

Applications consume capabilities and public platform interfaces:

```text
systemd targets/services
/run/ti-k3/* runtime contracts
/etc/ti-k3/gstreamer.env
ti-k3-* validation/helper commands
```

Applications do **not** own:

```text
remoteproc sysfs writes
firmware aliases or firmware selection
reserved-memory addresses
DMA carveout creation
TIOVX installation
Wave5 platform enablement
sensor DCC provisioning
```

That separation is intentional. A consumer should be replaceable without
changing the hardware-qualified accelerator base.

## Three profile axes

The project is organized along three independent axes instead of branching the
whole implementation per board.

### SoC profile

Describes accelerator inventory and remote-core topology:

- Main R5 / C7x topology
- VPAC VISS and multiscaler capability
- Wave5 capability
- remote-firmware aliases
- RPMsg expectations

The current implementation uses `profiles/soc/j722s.env`.

### Board profile

Describes the physical board integration:

- base DT integration
- CSI routing and camera overlays
- board muxes/regulators
- board identity

The current implementation uses `profiles/board/beagley-ai.env`.

### Memory profile

Describes a single validated memory contract shared by Linux, DT reserved
memory, remote firmware/linkers, RPMsg, DMA heaps, and TIOVX.

The current qualified profile is
`profiles/memory/j722s-beagley-ai-4gb.json`.

Memory profiles are explicit and qualified. They are not synthesized from the
amount of RAM detected at boot.

## Stock Armbian to accelerator platform

The transformation is layered deliberately:

```text
Armbian build source
    |
    |  kernel/DT userpatches + config
    v
BeagleY-AI kernel with accelerator hardware contract
    |
    |  locked TI Linux userspace + pinned TI headers
    |  frozen qualified remote firmware
    v
TI K3 image customization
    |
    |  private TIOVX/GStreamer runtime
    |  systemd services and public tools
    v
ti-k3-accelerators.target
    |
    +-- ti-k3-remoteproc-prepare.service
    +-- ti-k3-remote-log.service
    +-- ti-k3-wave5-prepare.service

Optional camera consumer contract:
    ti-k3-imx219-prepare.service
```

## Why the kernel and DT are modified

The Linux kernel and device tree must describe the same hardware and DDR
contract expected by the qualified remote firmware and TI userspace.

The BeagleY-AI integration therefore adds or enables:

1. board camera I2C/CSI routing
2. BeagleY-AI camera overlays
3. the fixed J722S 4 GiB reserved-memory map
4. `dma-heap-carveout`
5. TI `dma-buf-phys`
6. Wave5 codec support
7. IMX219 and CSI2RX media support
8. the kernel configuration needed by management Wi-Fi and accelerator tools

These changes live under
`armbian/userpatches/kernel/archive/k3-beagle-6.12/` and are selected by the
Armbian extension in `armbian/userpatches/extensions/ti-k3-accelerators.sh`.

A generic EdgeAI-composed DTB is not used as the BeagleY-AI runtime contract.
The qualified memory layout is compiled into the BeagleY-AI platform DT path,
and the camera overlay is selected separately.

## Why memory and firmware are one contract

The Main R5 and C7x firmware contain linker/runtime assumptions about DDR. The
Linux DT, DMA heaps, RPMsg shared regions, and TIOVX runtime must agree with
those assumptions exactly.

For that reason:

- firmware identity is fixed by hash
- aliases are fixed
- the memory profile is fixed
- `ti-k3-memory-map-verify` validates the Linux/DT view
- application code is prohibited from selecting alternate firmware or memory
  addresses

The independent RTOS source rebuild is useful provenance evidence, but because
it did not reproduce every remote binary bit-for-bit it is not substituted for
the frozen hardware-qualified deployment cohort.

## Remoteproc and RPMsg lifecycle

Remote-core startup is platform policy, not application policy.

The systemd platform layer owns the qualified sequence. The Main R5 contract is
established first; the C7x portion follows the qualified delayed sequence. The
public readiness gate is `ti-k3-rpmsg-ready`, which verifies that the expected
Vision Apps RPMsg endpoints exist before a consumer is allowed to depend on the
accelerator stack.

Applications must not write `/sys/class/remoteproc/*/state`.

## Why physical cold boot matters

A Linux `reboot` does not necessarily reproduce the same remote-core reset,
power, clock, and firmware-start conditions as removal and reapplication of
board power. The hardware qualification therefore uses a complete physical
cold power cycle as the firmware/platform reset boundary.

This is a qualification rule, not a recommendation to repeatedly power-cycle
for ordinary application debugging. Consumers should leave remoteproc ownership
with the platform rather than trying to recover failures by warm-restarting
remote cores.

## TI userspace on Armbian/Noble

Armbian/Noble remains the host distribution. The project does not replace its
core libc, GLib, GStreamer core, systemd, or toolchain libraries with an entire
TI root filesystem.

Instead, the build reconstructs the accelerator-specific TI payload from the
official PSDK Linux `11.02.01.03` `tisdk-adas-image` using package/path locks.
Required development headers are reconstructed independently from pinned TI
sources.

`armbian/userpatches/customize-image.sh` rejects forbidden distribution-core
replacement libraries before the TI payload is installed.

## Private TIOVX/GStreamer runtime

The original TI release plugin remains part of the provenance record, but the
active Armbian/Noble runtime uses the source-built compatibility plugin proven
for this integration.

The runtime is published behind:

```text
/etc/ti-k3/gstreamer.env
```

A consumer sources that environment instead of adding arbitrary TI library
paths globally to the distribution.

## Wave5

Wave5 is a platform capability. The platform owns kernel/module readiness and
codec validation; the application owns encoding policy such as target bitrate
and GOP.

Platform validation includes:

```bash
ti-k3-wave5-verify
ti-k3-test-wave5-codecs h264
ti-k3-test-wave5-codecs h265
```

A consumer such as OpenHD may then use the exposed `v4l2h264enc` capability
without owning Wave5 initialization.

## IMX219 camera contract

Camera support is optional at the generic platform-target level. This prevents a
non-camera consumer or a ground role from being forced to own an IMX219.

For the qualified BeagleY-AI air-camera path:

1. select `imx219` on CSI0 with `ti-k3-select-camera-overlay imx219 0`
2. perform a physical cold power cycle
3. start `ti-k3-imx219-prepare.service`
4. validate detect/raw/ISP/encode stages

The camera preparation service publishes:

```text
/run/ti-k3/camera.env
/run/ti-k3/camera-video
/run/ti-k3/camera-subdev
```

That contract hides the exact `/dev/video*`, media-controller, and subdevice
enumeration from applications.

## Application-facing acceptance gate

Before any consumer is installed, the accelerator-only platform should pass:

```bash
ti-k3-info
ti-k3-memory-map-verify
ti-k3-rpmsg-ready --wait 120
ti-k3-wave5-verify --prepare
ti-k3-self-test
```

If a camera is required, additionally validate the IMX219 path.

The detailed standalone acceptance criteria are in
[`PASS1-TEST-PLAN.md`](PASS1-TEST-PLAN.md). The frozen BeagleY-AI R2 hardware
result is in
[`qualification/BEAGLEY-AI-R2-20260813.md`](qualification/BEAGLEY-AI-R2-20260813.md).

## Future platforms

Future J722S boards or AM62A/AM62P targets should add or change profile-specific
integration rather than teaching applications new remoteproc paths, firmware
filenames, memory addresses, or device-node assumptions.

Capabilities, not SoC names, should drive consumers. See
[`PORTING-MODEL.md`](PORTING-MODEL.md).
