# BeagleY-AI R3 Source-Built Accelerator Hardware Qualification

Qualification date: 2026-08-14  
Status: PASS

## Scope

This qualification covers the TI K3 accelerator platform for BeagleY-AI / J722S
(AM67A) integrated into Armbian, with the Main R5, both C7x firmware images, and
the TI 2A provider reconstructed from source rather than supplied as frozen
build inputs.

OpenHD remains outside this qualification boundary. It is a consumer of the
qualified accelerator platform.

## Qualified source identity

- TI K3 tested source commit:
  `83c62656be0a725c691cda8727421cba552c32bf`
- Armbian build commit:
  `259c7b157f9cc7968f077f5483ff0537f691c712`
- TI Processor SDK Linux release:
  `11.02.01.03`
- TI Processor SDK RTOS source release:
  `11.02.01.03`
- TI Linux image input:
  `tisdk-adas-image-j722s-evm`
- TI Linux rootfs archive SHA-256:
  `01b8e762db99673108b423e8dcb1e5f2c00bdba17359dcd00600b49db030ded4`

The tested firmware source contract is application-neutral:

- Main R5 generated driver source: `ti_drivers_config_j722s.c`
- Main R5 generated power/clock source: `ti_power_clock_config_j722s.c`
- Main R5 diagnostic prefix: `J7DBG`
- memory profile: `j722s-beagley-ai-4gb-r73341`

No OpenHD-specific compiler-visible firmware basename or diagnostic prefix is
part of the qualified production firmware source contract.

## Zero-frozen build-input result

The qualified image was constructed from:

- pinned Armbian source
- this repository
- official TI Processor SDK Linux input
- official TI Processor SDK RTOS source
- pinned TI/public source dependencies
- TI/public toolchains

The image build did not consume the historical frozen Vision Apps firmware
cohort or a frozen TI 2A provider as required build inputs.

Historical frozen firmware remains valid only as qualification/reproduction
evidence and is not part of the R3 production build path.

## Qualified image

Image:

`Armbian-unofficial_26.08.0-trunk_Beagley-ai_noble_vendor_6.12.49_minimal.img.xz`

SHA-256:

`8e263e15bd7c436bd410b774427db0a50f365810e72f8e6859f9b0f47e0f89e5`

Kernel:

`6.12.49-vendor-k3-beagle`

The image SHA-256 is the exact artifact identity of the disk image that was
flashed and physically hardware-qualified.

The image's build-time metadata intentionally records
`qualification_status=unqualified_source_candidate`. Qualification occurs only
after the built artifact is flashed and tested; this document and the immutable
qualification tag are the post-build attestation for this exact artifact.

## Qualified source-built remote firmware

Main R5:

`fc56b2a0e5110dac22ba3f25e997190aa07ccaf50bee36f21cc1703c61d6c41a`

C7x 0:

`00ddc57e33a02a683c0077d9ef424aa1c3fa6b6a82935f335306052f355cb16b`

C7x 1:

`10f3b472aa7d260c0f978356a12a539f15c5e49297b408f84ee92c66f91600d5`

Firmware aliases:

- `j722s-main-r5f0_0-fw -> vision_apps_evm/vx_app_rtos_linux_mcu2_0.out`
- `j722s-c71_0-fw       -> vision_apps_evm/vx_app_rtos_linux_c7x_1.out`
- `j722s-c71_1-fw       -> vision_apps_evm/vx_app_rtos_linux_c7x_2.out`

Whole-file ELF hashes are recorded as deployment/build provenance. Earlier
reproduction work established that differences from the historical qualified
cohort can be confined to compiler-visible naming/debug metadata or other
non-runtime ELF content. The R3 application-neutral Main R5 is intentionally a
new load image and is qualified by the physical hardware results below rather
than by identity with the old R2 Main R5 image.

## TI 2A source-build identity

The TI 2A provider was rebuilt from:

`imaging/ti_2a_wrapper`

Qualified provider SHA-256:

`4f7b2acf81511fc0dabf7f61b88b7a7574d153cab435c178b238ecc689e6c567`

The source-built provider reproduced the historical provider byte-for-byte.

## Physical cold-boot qualification

Qualification used a complete physical power cycle. A warm reboot was not
substituted for the cold-boot gate.

No manual writes were made to `/sys/class/remoteproc/*/state`.

Cold boot verified:

- `ti-k3-accelerators.target` active
- Main R5 running on `remoteproc2`
- C7x 0 running on `remoteproc3`
- C7x 1 running on `remoteproc4`
- RPMsg endpoints 13 and 21 ready on all three Vision Apps remote cores
- installed source-built firmware hashes match recorded provenance
- R2/J722S 4 GiB memory map contract
- Vision Apps DMA heap initialization
- Wave5 codec runtime
- TIOVX runtime
- TI K3 self-test

Base self-test result:

`TI_K3_SELF_TEST=PASS`

## Camera qualification

Sensor:

`IMX219`

Physical interface:

`CSI0`

The corrected qualification helper configured the complete media graph before
streaming:

`IMX219 -> Cadence CSI2RX bridge -> TI J721E CSI2RX -> V4L2 capture`

Raw capture qualification:

- resolution: 1920x1080
- format: RGGB / SRGGB8_1X8
- target frame rate: 30 fps
- observed frame rate: approximately 30.01 fps
- raw capture preflight: PASS
- 300-frame raw stream: PASS

TIOVX ISP qualification:

- input: 1920x1080 RGGB @ 30 fps
- sensor profile: `SENSOR_SONY_IMX219_RPI`
- VISS DCC: IMX219 1920x1080
- 2A DCC: IMX219 1920x1080
- output: 1920x1080 NV12 @ 30 fps
- result: PASS

Full accelerator video qualification:

- IMX219 CSI0 raw Bayer input
- TIOVX ISP
- 1920x1080 NV12
- TIOVX multiscaler
- 1280x720 NV12 @ 30 fps
- Wave5 `v4l2h264enc`
- H.264 byte-stream / access-unit alignment
- H.264 baseline output
- result: PASS

Qualification gates:

- `IMX219_DETECT=PASS`
- `IMX219_RAW_CAPTURE=PASS`
- `IMX219_TIOVX_ISP=PASS`
- `IMX219_FULL_ACCELERATOR_PIPELINE=PASS`

## Final result

- `ZERO_FROZEN_FIRMWARE_BUILD_INPUT=PASS`
- `TI_2A_SOURCE_BUILD=PASS`
- `ACCELERATOR_COLD_BOOT_QUALIFIED=PASS`
- `IMX219_CSI0_QUALIFIED=PASS`
- `TIOVX_ISP_QUALIFIED=PASS`
- `TIOVX_MULTISCALER_QUALIFIED=PASS`
- `WAVE5_H264_QUALIFIED=PASS`
- `ARMBIAN_R3_SOURCE_HARDWARE_QUALIFIED=PASS`

## Qualification tag

The immutable qualification tag identifies the exact tested source commit, not
this later documentation commit:

`beagley-ai-r3-source-hw-qualified-20260814`

Tag target:

`83c62656be0a725c691cda8727421cba552c32bf`

The previous tag `beagley-ai-r2-hw-qualified-20260813` remains frozen and must
not be moved.

## Ownership boundary

This repository owns the reusable TI K3 accelerator platform:

- board/kernel integration
- reserved-memory contract
- source-built remote firmware contract
- RPMsg
- DMA heap / dma-buf support
- TIOVX/VPAC runtime
- camera topology and qualification helpers
- Wave5
- platform services and validation utilities

OpenHD, wifibroadcast/RF policy, bitrate/GOP policy, and flight-controller policy
remain separate consumer concerns.
