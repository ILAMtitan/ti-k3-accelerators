# BeagleY-AI IMX415 R3 stability checkpoint — 2026-09-02

Hardware:
- BeagleY-AI / J722S
- Arducam B0569 / Sony IMX415
- I2C address 0x37
- CSI0
- 3864x2192 SGBRG10
- two CSI-2 lanes
- 720 MHz link frequency

Kernel:
- 6.12.49-vendor-k3-beagle

R3 lifecycle changes:
- MCU_GPIO0_15 is assigned as active-low camera reset.
- IMX415 driver owns reset through reset-gpios.
- post-reset settling interval increased from 100-200 us to 20-22 ms.

Qualified installed module SHA256:

02d841efb2a8a33e90ebd7bb06d4ab4e17f94f2982f3a87ebf403c61735672d4

Qualified reset-enabled DTBO SHA256:

195c32206e935a61ff8235b75823a7cb9f34c51757553fb2b0f92a5f324fe894

Results:
- Warm reboot works without physical power removal.
- Runtime resume works without IMX415 -EREMOTEIO failures.
- RAW: 5400 frames / 181 seconds / about 30.02 fps.
- VISS-only: about 30.03 fps for about 185 seconds.
- VISS + scaler: stable at about 27.12 fps.
- VISS + scaler + Wave5: stable at about 25.63 fps.
- OpenHD-style pre-encoder leaky queue + Wave5: stable at about 26.97 fps.
- No camera-side hard stream collapse was observed after R3.

The remaining OpenHD corruption has been isolated downstream of local H.264
encoding; a local Wave5 H.264 motion recording was clean.

The full pipeline is stable but currently remains below the nominal 30 fps
target after scaling/encoding.
