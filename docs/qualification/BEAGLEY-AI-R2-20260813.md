# BeagleY-AI R2 Accelerator Hardware Qualification

Qualification date: 2026-08-13  
Status: PASS

## Scope

This qualification covers the TI K3 accelerator platform for BeagleY-AI / J722S
(AM67A) integrated into Armbian.

OpenHD is deliberately outside this qualification boundary. OpenHD is a later
consumer of the qualified accelerator platform.

## Qualified source inputs

- TI K3 source-input commit:
  `6b3e51058888e045f1877cc0c270f013274b2461`
- Frozen R2 platform commit:
  `812bfe23c9d6599006cc0bc080366e4b93e91669`
- Armbian build commit:
  `259c7b157f9cc7968f077f5483ff0537f691c712`
- TI Processor SDK Linux release:
  `11.02.01.03`
- TI image:
  `tisdk-adas-image-j722s-evm`
- TI rootfs archive SHA-256:
  `01b8e762db99673108b423e8dcb1e5f2c00bdba17359dcd00600b49db030ded4`

The direct TI userspace import is package/path locked to the official TI SDK
image. Additional EdgeAI development headers are imported from pinned official
Texas Instruments source repositories.

## Qualified image

Image:

`Armbian-unofficial_26.08.0-trunk_Beagley-ai_noble_vendor_6.12.49_minimal.img.xz`

SHA-256:

`ac9925a9192e20c44b5cdc618ce8099bda53339e930d2d0be0ccc16377a363c4`

Kernel:

`6.12.49-vendor-k3-beagle`

The image itself is not stored in Git. Its SHA-256 is the artifact identity.

## Qualified remote firmware

Main R5:

`214ee24d51bd8f3166cd930b2ed01f058fe5268bc93c4fdbb43feb551f9a753c`

C7x 0:

`fcfd8a387e93fb23a7ddae7c8c86283ef9384dad473700012333b2715709be01`

C7x 1:

`23d2c02c0eba51bfa42c64d36ee6bfdeb8a79be9adc4bfb4d0e3799706bb7116`

Firmware aliases:

- `j722s-main-r5f0_0-fw -> vision_apps_evm/vx_app_rtos_linux_mcu2_0.out`
- `j722s-c71_0-fw -> vision_apps_evm/vx_app_rtos_linux_c7x_1.out`
- `j722s-c71_1-fw -> vision_apps_evm/vx_app_rtos_linux_c7x_2.out`

These binaries are the frozen hardware-qualified R2 firmware cohort. The
independent RTOS rebuild did not reproduce every firmware binary bit-for-bit,
so rebuilt firmware is not substituted for the qualified cohort.

## TI TIOVX runtime provenance

Original TI release plugin SHA-256:

`806adb6fd46b68966f1df869f7bda460e1e4633edef347598c0f7b0691acb4b8`

The original TI plugin is preserved in the finished image.

The active compatibility plugin is built from:

- repository: `https://github.com/TexasInstruments/edgeai-gst-plugins.git`
- commit: `fea12213b449fc1ea117ad5f0016c08f417ab46d`
- selected plugin SHA-256:
  `971a6f0391ddd357eb3e976b15c789e3b7e260d49b37058562a9950eba8c90b0`

Live factories verified:

- `tiovxisp`
- `tiovxmultiscaler`
- `tiovxmemalloc`

## Offline image qualification

The qualified compressed image passed:

- locked TI SDK userspace identity
- TI source development-header identity
- TI vendor-plugin preservation
- selected TIOVX compatibility-plugin provenance
- private runtime SHA-256 manifest
- required kernel configuration
- Wave5 module
- IMX219 module
- Cadence CSI2RX module
- TI J721E CSI2RX module
- R5 remoteproc module
- DSP remoteproc module
- CC33xx modules
- compiled `ti,dma-buf-phys`
- exact R2 reserved-memory map
- `dma-heap-carveout`
- qualified remote-firmware hashes
- remote-firmware aliases
- accelerator systemd target and utilities
- OpenHD application boundary
- legacy UDP 5500 boundary

Result:

`ARMBIAN_ACCELERATOR_PREFLASH=PASS`

## Physical cold-boot qualification

Qualification used a complete physical power cycle. A warm reboot was not
substituted for cold boot.

No manual writes were made to `/sys/class/remoteproc/*/state`.

Cold boot verified:

- zero failed systemd units
- `ti-k3-accelerators.target` active
- Main R5 running
- C7x 0 running
- C7x 1 running
- RPMsg endpoints 13 and 21 ready on all three Vision Apps remote cores
- exact live firmware identity and aliases
- exact live R2 memory map
- Vision Apps carveout DMA heap
- `dma-buf-phys`
- Wave5 codec runtime
- TIOVX runtime
- TI K3 self-test

## Camera qualification

Sensor:

`IMX219`

Physical camera interface:

`CSI0`

Qualified camera media path:

- IMX219 sensor
- Cadence CSI2RX bridge
- TI J721E CSI2RX
- raw Bayer capture
- VPAC/TIOVX ISP
- TIOVX multiscaler
- Wave5 H.264 encoder

Raw capture:

- 1920x1080
- RGGB
- 30 fps
- observed approximately 30.01 fps

ISP output:

- 1920x1080
- NV12
- 30 fps

Scaled output:

- 1280x720
- NV12
- 30 fps

Encoded output:

- H.264
- byte-stream
- access-unit alignment

Qualification gates:

- `IMX219_DETECT=PASS`
- `IMX219_RAW_CAPTURE=PASS`
- `IMX219_TIOVX_ISP=PASS`
- `IMX219_FULL_ACCELERATOR_PIPELINE=PASS`

Final result:

- `ACCELERATOR_COLD_BOOT_QUALIFIED=PASS`
- `ARMBIAN_R2_HARDWARE_QUALIFIED=PASS`

## Ownership boundary

This repository owns the reusable TI K3 accelerator platform:

- board/kernel integration
- reserved-memory contract
- remoteproc firmware contract
- RPMsg
- dma-buf / carveout support
- TIOVX/VPAC runtime
- camera topology
- Wave5
- platform services and validation utilities

OpenHD remains a separate consumer integration and is not part of this
hardware-qualified accelerator base.

## Source-origin hardening status

The following source-origin work is qualified in this release:

1. official TI SDK archive as deterministic userspace input
2. package/path locked TI userspace import
3. TI development headers from release packages and pinned TI sources

Additional provenance hardening remains separate future work, including
formalization of the compatibility-plugin patch stack, TI 2A provider
provenance, yaml-cpp provenance, exact kernel-patch lineage, memory-map source
lineage, and RTOS build-input provenance.

Those remaining items do not invalidate the hardware qualification recorded
here, but this document does not claim they are complete.
