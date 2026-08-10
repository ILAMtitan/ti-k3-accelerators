# Porting model

Portability is deliberately split across three axes instead of branching the
whole project per board.

## SoC profile

Describes accelerator capabilities and remote-core topology, for example:

- C7x count
- VPAC VISS / MSC availability
- Wave5 availability
- H.264/H.265 encode/decode capability
- firmware aliases / remoteproc topology

Pass 1 implements `j722s`. Future targets can add `am62a` and `am62p` without
changing the application-facing `ti-k3-*` API.

## Board profile

Describes physical integration:

- base DT / overlay integration
- CSI port routing and supported sensor overlays
- board-specific muxes or regulators

Pass 1 implements `beagley-ai`.

## Memory profile

Describes a fully validated contract shared by DT reserved-memory, remote-core
firmware/linker placement, IPC, DMA heaps and Linux-visible memory.

Memory profiles are explicit and qualified; they are not dynamically invented
from detected RAM size at boot. Pass 1 implements only the hardware-proven
J722S BeagleY-AI 4 GiB profile.

## Capability-driven consumers

Applications should ask the platform for capabilities rather than hard-code a
SoC. A later manifest/tool can expose keys such as:

```
codec.h264.encode=yes
codec.h264.decode=yes
codec.h265.encode=yes
codec.h265.decode=yes
vision.c7x.count=2
vision.vpac.viss=yes
vision.vpac.msc=yes
camera.csi2=yes
```

This is the intended path for AM62A (vision + codec) and AM62P (codec-centric)
ports after J722S pass-1 separation is proven on hardware.
