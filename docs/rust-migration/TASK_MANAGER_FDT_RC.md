# Task Manager FDT Rust-Default RC

Captured: 2026-06-30 CEST.

`tm_fdt` is now in a Rust-default release-candidate window for QSOE/L. Normal
LQ taskman builds use `qsoe-tm-fdt` through the shared `qsoe-tm-providers`
archive. The C parser in `lq/taskman/sys/fdt.c` remains available as explicit
rollback with `QSOE_RUST_TM_FDT=0`.

## Selectors

```sh
make tm-fdt-rc-smoke
make tm-fdt-rc-rollback-smoke
make tm-fdt-evidence
QSOE_RUST_TM_FDT=0 make -C lq taskman
```

`make tm-fdt-rc-smoke` verifies that the LQ taskman link plan omits
`sys/fdt.o`, builds the Rust-default taskman, and boots through the existing
FDT runtime smoke. `make tm-fdt-rc-rollback-smoke` verifies that the C rollback
link plan includes `sys/fdt.o` and boots the same `/chosen`, `/sys`, and
`sysinfo` consumers with `QSOE_RUST_TM_FDT=0`.

## Evidence Boundary

The RC covers the current QEMU/LQ boot consumers:

- `/chosen` bootargs;
- syscfg and sysmap construction markers;
- `/sys/board`;
- `/sys/cmdline`;
- `/usr/bin/sysinfo`.

This RC does not retire C. Broader PCI and memory-topology confidence is still
required before opening a separate C removal PR under the global retirement
checklist.
