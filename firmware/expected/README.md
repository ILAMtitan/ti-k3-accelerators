# J722S Split-R1 Firmware Oracle

`j722s-r1-hardware-oracle.sha256` contains the full ELF SHA256
fingerprints of the hardware-qualified Split-R1 firmware cohort.

Fresh source builds are accepted by runtime equivalence:

- ELF entry point identical
- all PT_LOAD metadata identical
- all PT_LOAD contents byte-identical
- all SHF_ALLOC sections byte-identical

Full ELF SHA256 equality is a stronger forensic result but is not
required for a reconstructed build because non-runtime debug/symbol
metadata can encode build provenance.

Observed clean-room residual differences:

- R5: non-runtime DWARF/symbol metadata; semantic symbol inventory
  is equivalent and DWARF CU inventory is equivalent after build-root
  normalization.
- C7x_1: non-runtime metadata only.
- C7x_2: non-runtime metadata only.

The hardware oracle binaries themselves are not source dependencies and
must not be required to generate firmware.

## Build-root sensitivity

The qualified Split-R1 reconstruction is currently build-root sensitive.

The hardware-oracle runtime image was reconstructed successfully when the
TI SDK was built at:

    /home/bart/ti-sdk-11.02.01/rtos-src

Building byte-identical source with the same toolchain and make policy at
a different absolute SDK path changes allocated/runtime-loaded data because
absolute source paths are embedded by the TI builds.

Until a compiler prefix-map solution is independently qualified, an
oracle-equivalent build must therefore use the recorded ORACLE_BUILD_ROOT.
