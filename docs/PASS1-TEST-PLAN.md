# Pass-1 standalone qualification

The first milestone is **not** OpenHD video. It is proving that a normal Armbian
image can expose the accelerator stack with OpenHD completely absent.

After an untouched cold boot:

```bash
ti-k3-info
ti-k3-memory-map-verify
ti-k3-rpmsg-ready --wait 120
ti-k3-wave5-verify --prepare
ti-k3-self-test
```

Then exercise codecs:

```bash
ti-k3-test-wave5-codecs h264
ti-k3-test-wave5-codecs h265
```

With IMX219 attached:

```bash
sudo systemctl start ti-k3-imx219-prepare.service
ti-k3-test-imx219 isp
ti-k3-test-imx219 encode
```

Acceptance for pass 1:

- memory map passes
- exact R5/C7x hashes pass
- R5 endpoint 13 precedes the 10-second C7x delay
- all three cores expose endpoints 13 and 21
- OpenVX/TIOVX initializes
- Wave5 encode and decode work
- IMX219 -> VISS -> MSC -> Wave5 works
- `grep -R openhd /etc/systemd/system/ti-k3-* /usr/local/sbin/ti-k3-*` finds no
  application dependency (forensic identifiers in provenance are exempt)

Only after this passes should OpenHD be installed as a consumer.
