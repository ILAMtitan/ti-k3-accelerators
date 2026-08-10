# Architecture

The project is organized along three independent axes:

- **SoC profile** — accelerator inventory and remote-core topology.
- **Board profile** — physical CSI/board wiring and kernel DT integration.
- **Memory profile** — validated reserved-memory/linker/runtime contract.

The pass-1 public boundary is:

```
Armbian/kernel/DT
        |
        v
ti-k3-accelerators.target
        |
        +-- ti-k3-remoteproc-prepare.service
        +-- ti-k3-remote-log.service
        +-- ti-k3-wave5-prepare.service

Optional imaging:
        ti-k3-imx219-prepare.service
```

Applications are expected to consume tools/services, not remoteproc sysfs or
firmware implementation details directly.

Future profiles can add AM62A and AM62P without changing application-facing
names. Capabilities, not SoC names, should drive applications.
