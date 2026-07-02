## 2026-07-02 CEST - tm_cap_plan C Seam Evidence

Scope:

- Added a C-only `tm_cap_plan` seam for child CSpace publication operations in
  `spawn.c`.
- Covered taskman endpoint, child untyped, CNode self, and stdio connection cap
  publication through a typed cap operation list with a C-owned commit helper.
- Added `spawn-cap-plan-c-evidence`, CI wiring, and the LQ component patch while
  keeping TCB setup, objcnode relocation, resume, and broader authority paths in
  C.

Commands:

- Not run locally; PR CI is the formal evidence path.

Result:

- #154 has a second narrow C-owned planning seam. Broader spawn/capability/
  loader ownership remains deferred.

## 2026-07-02 CEST - tm_spawn_argpack C Seam Evidence

Scope:

- Added a C-only `tm_spawn_argpack` planning seam in `spawn.c` so argv/envp/auxv
  bounds and initial-stack byte accounting are validated before child stack
  writes.
- Added `spawn-argpack-c-evidence` and CI wiring to make the seam verifiable
  next to the existing spawn/loader boundary and stress evidence.
- Kept spawn, capability, loader, scratch mapping, and stack commit authority in
  C; no Rust provider candidate is introduced in this step.

Commands:

- Not run locally; PR CI is the formal evidence path.

Result:

- #154 now has its first narrow C-owned planning seam while the broader
  spawn/capability/loader milestone remains deferred.

## 2026-07-01 CEST - tm_sysfs/qrvfs CI Posture and tm_reloc Metadata Cleanup

Scope:

- Renamed trusted CI qrvfs and `tm_sysfs` steps so they reflect the retired
  Rust-only/default posture already enforced by Makefile selectors.
- Added the qrvfs production-root Rust writer comparison to trusted CI via
  `make container-check-qrvfs-rust-writer-production-root`.
- Added `TASK_MANAGER_RELOC_RETIREMENT.md` and updated status, inventory,
  README, retirement, task-manager, and boundary-review docs so `tm_reloc` is
  recorded as a retired/default Rust provider while broader spawn/capability
  and loader ownership stays deferred.

Commands:

- Not run locally; this is CI wiring and roadmap-facing documentation. The PR
  CI is the formal evidence path for the added qrvfs production-root gate.

Result:

- `tm_sysfs`, host qrvfs tools, and `tm_reloc` now have consistent
  roadmap-facing posture: retired/default Rust paths with stale C selectors
  rejected, and no claim that authority-owning spawn/capability/loader code has
  moved to Rust.

## 2026-07-01 CEST - Host qrvfs C Retirement

Scope:

- Retired C `host_tools/treeqrvfs.c` and `host_tools/mkfs-qrv.c`.
- Made Rust `qrvfs-tree` and `mkfs-qrv-rs` mandatory in Makefile selectors.
- Converted qrvfs fixture and production-root checks to Rust-only oracles.
- Removed qrvfs rollback make and container targets.
- Updated CI to run Rust-only tree and mkfs-qrv live smokes.
- Added `HOST_QRVFS_RETIREMENT.md` and updated roadmap-facing docs.

Commands:

- `bash -n scripts/treeqrvfs-artifact.sh scripts/treeqrvfs-rc-smoke.sh scripts/check-qrvfs-fixture.sh scripts/check-qrvfs-rust-fixture.sh scripts/check-qrvfs-rust-writer-fixture.sh scripts/check-qrvfs-rust-writer-production-root.sh scripts/mkfs-qrv-rs-artifact.sh scripts/rust-mkfs-qrv-live-smoke.sh scripts/mkfs-qrv-rc-live-smoke.sh`
- `make check-qrvfs-fixture`
- `make check-qrvfs-rust-fixture`
- `make treeqrvfs-rc-smoke`
- `make check-qrvfs-rust-writer-fixture`
- `make check-qrvfs-rust-writer-production-root`
- `make rust-mkfs-qrv-live-smoke`
- `make mkfs-qrv-rc-live-smoke`
- `QSOE_RUST_TREEQRVFS=0 make tree`
- `QSOE_RUST_MKFS_QRV=0 make fsqrv-image`
- `TREEQRVFS_RC_ROLLBACK=1 scripts/treeqrvfs-rc-smoke.sh`
- `MKFS_QRV_RC_ROLLBACK=1 scripts/mkfs-qrv-rc-live-smoke.sh`

Result:

- Shell syntax passed for all qrvfs retirement scripts.
- Rust-only qrvfs fixture, selected tree artifact, and `treeqrvfs-rc-smoke` passed.
- Rust writer fixture and production-root comparison passed using Rust `qrvfs-tree` as the oracle.
- Retired selectors `QSOE_RUST_TREEQRVFS=0`, `QSOE_RUST_MKFS_QRV=0`, `TREEQRVFS_RC_ROLLBACK=1`, and `MKFS_QRV_RC_ROLLBACK=1` fail fast.
- `make rust-mkfs-qrv-live-smoke` and `make mkfs-qrv-rc-live-smoke` passed with the `rust-virtio-file-smoke: read /usr/conf/passwd ok` marker.
- `make rust-quality` passed, including 7 `qsoe-qrvfs` parser/writer tests.

Follow-up:

- Update #136 metadata after PR and main CI complete.

# QSOE Rust Migration Development Log

Last updated: 2026-07-01 CEST.

This log tracks the development process for the Rust migration and reproducible
toolchain work. It records what changed, what was observed, what failed, and
what was verified. Append new entries at the top.

Entry template:

```text
## YYYY-MM-DD HH:MM TZ - Short Title

Scope:
- ...

Commands:
- ...

Result:
- ...

Follow-up:
- ...
```

## 2026-07-01 08:22 CEST - tm_fdt C Retirement

Scope:

- Retired the LQ C `tm_fdt` provider after the Rust-default RC window.
- Added mandatory `QSOE_RUST_TM_FDT=1` guards to the umbrella, LQ component
  overrides, LQ taskman overrides, and the shared Rust provider archive builder.
- Removed the C `tm_fdt` host fixture and rollback make/CI targets.
- Reworked `tm-fdt-evidence`, `tm-fdt-runtime-smoke`, and `tm-fdt-rc-smoke`
  so they verify Rust-only taskman links, absence of `sys/fdt.o`, source
  removal through component overrides, and retired selector rejection.
- Updated adjacent taskman evidence so `tm_elf` and `tm_sysmap` no longer pin
  `QSOE_RUST_TM_FDT=0` while isolating their own providers.
- Added `TASK_MANAGER_FDT_RETIREMENT.md` and updated status, inventory,
  handover, README, and retirement-gate docs from RC-with-rollback to retired.

Commands:

- `bash -n scripts/tm-fdt-evidence.sh scripts/tm-fdt-runtime-smoke.sh scripts/tm-fdt-rc-smoke.sh scripts/build-rust-tm-providers.sh scripts/apply-component-overrides.sh scripts/tm-sysmap-evidence.sh scripts/tm-elf-evidence.sh`
- `./scripts/apply-component-overrides.sh`
- `make tm-fdt-evidence`
- `make tm-fdt-runtime-smoke`
- `make tm-fdt-rc-smoke`
- `make tm-providers-evidence`

Result:

- Component overrides apply cleanly and remove `lq/taskman/sys/fdt.c`.
- `make tm-fdt-evidence` passed: Rust host tests passed, the shared provider
  archive had 413/413 soft-float members, LQ taskman omitted `sys/fdt.o`, and
  `QSOE_RUST_TM_FDT=0` was rejected for LQ and provider-archive builds.
- `make tm-fdt-runtime-smoke` passed and reached the `/chosen`, syscfg,
  sysmap, `/sys/board`, `/sys/cmdline`, and `sysinfo` boot markers.
- `make tm-fdt-rc-smoke` passed with `lq-rust-retired sys/fdt.o plan count: 0`
  before rerunning the runtime smoke.
- `make tm-providers-evidence` passed with one `rust_begin_unwind` symbol,
  413/413 soft-float provider members, NQ/LQ shared taskman links with retired
  C provider objects omitted, and the shared-provider `/proc` smoke.

Follow-up:

- Open the retirement PR for #146, record PR/main CI evidence, then update
  issue #146 roadmap metadata to `retired`.

## 2026-07-01 00:00 CEST - #202/#203 Warning-Mode Tooling Rollout

Scope:

- Added non-blocking CodeQL static security scanning for trusted pull-request
  and main contexts using CodeQL C/C++ no-build extraction.
- Added non-blocking dependency review for dependency manifest and lockfile
  pull requests.
- Added warning-mode CI steps for `container-rust-deep` and
  `container-rust-fuzz-smoke` so #203 can gather nextest/fuzz signal without
  blocking unrelated migration work.
- Pinned new GitHub Actions references by SHA to match the existing workflow
  supply-chain style.
- Updated #202 and #203 roadmap metadata from `status:future` to
  `status:in-progress` and recorded the warning-mode baseline/promotion plan.
- Updated handover, workflow, and top-level status text for the active tooling
  milestone.

Commands:

- `gh issue edit 202 --repo dmytro-yemelianov/qsoe-os-rust-handover --body-file /tmp/issue202-body.md --add-label status:in-progress --remove-label status:future`
- `gh issue edit 203 --repo dmytro-yemelianov/qsoe-os-rust-handover --body-file /tmp/issue203-body.md --add-label status:in-progress --remove-label status:future`
- `git ls-remote https://github.com/github/codeql-action.git refs/tags/v3^{} refs/tags/v3`
- `git ls-remote --tags https://github.com/actions/dependency-review-action.git`
- `rg -n "uses: .*@(v[0-9]|main|master)" .github/workflows`
- `make roadmap-validate`
- `gh run view 28479551482 --repo dmytro-yemelianov/qsoe-os-rust-handover --job 84412476167 --log`

Result:

- #202 and #203 now render as active tooling roadmap items and match the
  checked-in warning-mode workflow shape. Roadmap metadata validates with 38
  issue-backed items.
- The first PR CodeQL attempt proved `autobuild` was the wrong baseline for
  this repository because it ran plain `make` before `make prepare` populated
  the release components. The workflow now uses CodeQL `build-mode: none`.

Follow-up:

- Record the first PR and main CI baseline runs in #202/#203 before marking
  either item complete or promoting any check to required.

## 2026-06-30 23:40 CEST - tm_pathmgr, tm_pseudodev, and tm_rsrcdb C Provider Retirement

Scope:

- Retired C `tm_pathmgr` by removing `libtaskman/src/pathmgr.c` and the old C
  host fixture `tests/tm_pathmgr_model_test.c`.
- Retired LQ C `tm_pseudodev` by removing `lq/taskman/sys/devnull.c` and
  `lq/taskman/sys/devzero.c` through tracked component overrides.
- Retired LQ C `tm_rsrcdb` by removing `lq/taskman/sys/rsrcdb.c` through
  tracked component overrides and removing `tests/tm_rsrcdb_model_test.c`.
- Made `QSOE_RUST_TM_PATHMGR=1`, `QSOE_RUST_TM_PSEUDODEV=1`, and
  `QSOE_RUST_TM_RSRCDB=1` mandatory in umbrella, component, and provider
  builder paths.
- Removed the three C rollback make targets and converted the RC smoke scripts
  into retired selector checks plus Rust-only runtime coverage.
- Added retirement notes for `tm_pathmgr`, `tm_pseudodev`, and `tm_rsrcdb`.

Commands:

- `bash -n scripts/check-tm-pathmgr-model.sh scripts/check-tm-rsrcdb-model.sh scripts/tm-pathmgr-evidence.sh scripts/tm-pathmgr-runtime-smoke.sh scripts/tm-pathmgr-rc-smoke.sh scripts/tm-pseudodev-evidence.sh scripts/tm-pseudodev-runtime-smoke.sh scripts/tm-pseudodev-rc-smoke.sh scripts/tm-rsrcdb-evidence.sh scripts/tm-rsrcdb-runtime-smoke.sh scripts/tm-rsrcdb-rc-smoke.sh scripts/build-rust-tm-providers.sh scripts/apply-component-overrides.sh`
- `scripts/apply-component-overrides.sh`
- `make check-tm-pathmgr-model`
- `cargo test --manifest-path rust/Cargo.toml -p qsoe-tm-pseudodev --features host-tests`
- `make check-tm-rsrcdb-model`
- `make tm-pathmgr-evidence`
- `make tm-pseudodev-evidence`
- `make tm-rsrcdb-evidence`
- `QSOE_RUST_TM_PATHMGR=0 make -C libtaskman --no-print-directory`
- `QSOE_RUST_TM_PATHMGR=0 scripts/build-rust-tm-providers.sh build/tmp/libqsoe_tm_providers.a`
- `QSOE_RUST_TM_PSEUDODEV=0 scripts/build-rust-tm-providers.sh build/tmp/libqsoe_tm_providers.a`
- `QSOE_RUST_TM_RSRCDB=0 scripts/build-rust-tm-providers.sh build/tmp/libqsoe_tm_providers.a`
- `TM_PATHMGR_RC_ROLLBACK=1 scripts/tm-pathmgr-rc-smoke.sh`
- `TM_PSEUDODEV_RC_ROLLBACK=1 scripts/tm-pseudodev-rc-smoke.sh`
- `TM_RSRCDB_RC_ROLLBACK=1 scripts/tm-rsrcdb-rc-smoke.sh`

Result:

- Rust host model tests passed for all three providers.
- NQ/LQ taskman links omit C `pathmgr.o`; LQ taskman links omit C
  `sys/devnull.o`, `sys/devzero.o`, and `sys/rsrcdb.o`.
- Final taskman ELFs retain the exported Rust ABI symbols through the shared
  provider archive.
- The retired selectors and old rollback flags fail fast instead of selecting
  C.

Follow-up:

- Run roadmap gates, runtime/RC smokes, shared provider evidence, and Rust
  quality checks; then update #149, #151, and #152 to retired and open the
  retirement PR.

## 2026-06-30 22:20 CEST - tm_cred C Provider Retirement

Scope:

- Retired C `tm_cred` by removing `libtaskman/src/cred.c` and the old C host
  fixture `tests/tm_cred_model_test.c`.
- Made `QSOE_RUST_TM_CRED=1` mandatory in the umbrella, standalone
  `libtaskman`, provider archive builder, and tracked NQ/LQ component override
  patches.
- Converted `tm-cred-*` evidence/smoke scripts from RC-with-rollback to
  Rust-only retirement checks with retired selector rejection.
- Added `TASK_MANAGER_CRED_RETIREMENT.md`, updated status/readme/inventory docs,
  and moved issue #150 to open `status:retired` pending final PR/main CI
  evidence.

Commands:

- `bash -n scripts/check-tm-cred-model.sh scripts/tm-cred-evidence.sh scripts/tm-cred-runtime-smoke.sh scripts/tm-cred-rc-smoke.sh scripts/build-rust-tm-providers.sh scripts/apply-component-overrides.sh`
- `scripts/apply-component-overrides.sh`
- `make -n tm-cred-rc-smoke`
- `make -n tm-cred-rc-rollback-smoke`
- `QSOE_RUST_TM_CRED=0 make -C libtaskman --no-print-directory`
- `QSOE_RUST_TM_CRED=0 scripts/build-rust-tm-providers.sh build/tmp/libqsoe_tm_providers.a`
- `TM_CRED_RC_ROLLBACK=1 scripts/tm-cred-rc-smoke.sh`
- `make check-tm-cred-model`
- `make tm-cred-evidence`
- `make tm-cred-runtime-smoke`
- `make tm-cred-rc-smoke`
- `make tm-providers-evidence`
- `make rust-quality`
- `make roadmap-validate`
- `make roadmap-component-gate COMPONENT=tm-cred`

Result:

- Rust host model tests passed, covering ABI layout, cwd/getcwd, umask, init,
  self-info, and credential-change policy.
- NQ and LQ taskman links omit C `cred.o`; final taskman ELFs retain the
  exported `tm_cred_*` ABI from the Rust provider archive.
- `QSOE_RUST_TM_CRED=0`, `TM_CRED_RC_ROLLBACK=1`, and the removed rollback make
  target fail fast instead of selecting C.
- QSOE/L runtime and retired compatibility smokes reached all credential probe
  markers for root ids, cwd, umask, mutation, permission rejection, child
  inheritance, and spawn inheritance.
- Shared provider evidence still reports one Rust panic handler and passes the
  shared-provider `/proc` boot smoke.

Follow-up:

- Open the retirement PR, wait for trusted PR and main CI, record final PR/main
  evidence in #150, close #150, merge, and reindex codebase memory.

## 2026-06-30 20:50 CEST - tm_pseudodev Rust-Default RC

Scope:

- Promoted `tm_pseudodev` from Rust opt-in to Rust-default RC for QSOE/L while
  preserving C rollback through `QSOE_RUST_TM_PSEUDODEV=0`.
- Changed the umbrella and tracked LQ component override defaults to
  `QSOE_RUST_TM_PSEUDODEV ?= 1`.
- Added `tm-pseudodev-rc-smoke` and `tm-pseudodev-rc-rollback-smoke` targets
  plus CI hooks and artifact upload coverage.
- Updated `tm-pseudodev-runtime-smoke` so the Rust path remains default but the
  RC rollback path can explicitly reuse the live `/dev/null` and `/dev/zero`
  probe with `TM_PSEUDODEV_RUNTIME_ALLOW_C=1`.
- Updated shared provider evidence so `tm_pseudodev` is audited with the
  default LQ provider set.
- Added `TASK_MANAGER_PSEUDODEV_RC.md`, updated status/docs/readmes, and moved
  issue #152 to open `status:rc` / `rust-default-rc`.

Commands:

- `bash -n scripts/tm-pseudodev-evidence.sh scripts/tm-pseudodev-runtime-smoke.sh scripts/tm-pseudodev-rc-smoke.sh scripts/tm-providers-evidence.sh scripts/apply-component-overrides.sh`
- `scripts/apply-component-overrides.sh`
- `make -n tm-pseudodev-rc-smoke`
- `make -n tm-pseudodev-rc-rollback-smoke`
- `make tm-pseudodev-evidence`
- `make tm-pseudodev-runtime-smoke`
- `make tm-pseudodev-rc-smoke`
- `make tm-pseudodev-rc-rollback-smoke`
- `make tm-providers-evidence`
- `make rust-quality`
- `make roadmap-validate`
- `make roadmap-component-gate COMPONENT=tm-pseudodev`

Result:

- Rust-default LQ links omit C `sys/devnull.o` and `sys/devzero.o`; C rollback
  links include both objects.
- Rust-default and C rollback boot smokes both reached `/dev/null` write,
  stat, read-EOF and `/dev/zero` write, stat, zero-fill read, and
  `pseudodev_probe` markers.
- Shared provider evidence exports the pseudo-device handlers from the
  combined archive and links the LQ taskman with `tm_pseudodev` selected.
- C `lq/taskman/sys/devnull.c` and `lq/taskman/sys/devzero.c` remain present as
  rollback; no C source was retired.

Follow-up:

- Keep #152 open as `rust-default-rc` until trusted PR and main CI evidence is
  recorded. C removal still requires #26, the global retirement checklist, and
  a separate removal PR.

## 2026-06-30 20:17 CEST - tm_pathmgr Rust-Default RC

Scope:

- Promoted `tm_pathmgr` from Rust opt-in to Rust-default RC for standalone
  `libtaskman`, NQ, and LQ while preserving C rollback through
  `QSOE_RUST_TM_PATHMGR=0`.
- Changed umbrella, standalone `libtaskman`, and tracked NQ/LQ component
  override defaults to `QSOE_RUST_TM_PATHMGR ?= 1`.
- Added `tm-pathmgr-rc-smoke` and `tm-pathmgr-rc-rollback-smoke` targets plus
  CI hooks and artifact upload coverage.
- Updated `tm-pathmgr-runtime-smoke` so the Rust path remains default while the
  rollback path can explicitly reuse the live path registry probe with
  `TM_PATHMGR_RUNTIME_ALLOW_C=1`.
- Updated shared provider evidence so `tm_pathmgr` is audited with the default
  provider set.
- Added `TASK_MANAGER_PATHMGR_RC.md`, updated status/docs/readmes, and moved
  issue #149 to open `status:rc` / `rust-default-rc`.

Commands:

- `bash -n scripts/tm-pathmgr-runtime-smoke.sh scripts/tm-pathmgr-evidence.sh scripts/tm-pathmgr-rc-smoke.sh scripts/tm-providers-evidence.sh scripts/apply-component-overrides.sh`
- `scripts/apply-component-overrides.sh`
- `make -n tm-pathmgr-rc-smoke`
- `make -n tm-pathmgr-rc-rollback-smoke`
- `make tm-pathmgr-evidence`
- `make tm-pathmgr-runtime-smoke`
- `make tm-pathmgr-rc-smoke`
- `make tm-pathmgr-rc-rollback-smoke`
- `make tm-providers-evidence`
- `make roadmap-validate`
- `make roadmap-component-gate COMPONENT=tm-pathmgr`

Result:

- Rust-default NQ/LQ links omit C `pathmgr.o`; C rollback links include
  `pathmgr.o`.
- Rust-default and C rollback boot smokes both reached `/dev` readdir,
  `/etc/passwd` symlink, `/dev/console` repath, helper register/resolve,
  duplicate rejection, helper unregister, and `pathmgr_probe` markers.
- Shared provider evidence exports `tm_pathmgr_resolve` from the combined
  archive and links NQ/LQ taskman with `tm_pathmgr` selected.
- C `libtaskman/src/pathmgr.c` remains present as rollback; no C source was
  retired.

Follow-up:

- Keep #149 open as `rust-default-rc` until trusted PR and main CI evidence is
  recorded. C removal still requires #26, the global retirement checklist, and
  a separate removal PR.

## 2026-06-30 19:20 CEST - tm_rsrcdb Rust-Default RC

Scope:

- Promoted `tm_rsrcdb` from Rust opt-in to Rust-default RC for QSOE/L while
  preserving C rollback through `QSOE_RUST_TM_RSRCDB=0`.
- Changed the umbrella and tracked LQ component override defaults to
  `QSOE_RUST_TM_RSRCDB ?= 1`.
- Added `tm-rsrcdb-rc-smoke` and `tm-rsrcdb-rc-rollback-smoke` targets plus CI
  hooks and artifact upload coverage.
- Updated `tm-rsrcdb-runtime-smoke` so the Rust path remains default but the RC
  rollback path can explicitly reuse the live `rsrcdb_probe` with
  `TM_RSRCDB_RUNTIME_ALLOW_C=1`.
- Updated shared provider evidence so `tm_rsrcdb` is audited with the default
  LQ provider set.
- Added `TASK_MANAGER_RSRCDB_RC.md`, updated status/docs/readmes, and moved
  issue #151 to `status:rc` / `rust-default-rc`.

Commands:

- `bash -n scripts/check-tm-rsrcdb-model.sh scripts/build-rust-tm-rsrcdb-provider.sh scripts/tm-rsrcdb-evidence.sh scripts/tm-rsrcdb-runtime-smoke.sh scripts/tm-rsrcdb-rc-smoke.sh scripts/tm-providers-evidence.sh scripts/apply-component-overrides.sh`
- `make tm-rsrcdb-evidence`
- `make tm-rsrcdb-runtime-smoke`
- `make tm-rsrcdb-rc-smoke`
- `make tm-rsrcdb-rc-rollback-smoke`
- `make tm-providers-evidence`
- `make rust-quality`
- `make roadmap-validate`
- `make roadmap-component-gate COMPONENT=tm-rsrcdb`
- `git diff --check`

Result:

- Rust-default selector omits C `sys/rsrcdb.o` from the LQ taskman dry-run
  plan; C rollback includes two `sys/rsrcdb.o` dry-run entries.
- Rust-default and C rollback boot smokes both reached the live
  `rsrcdbmgr_*` create, query, attach, detach, destroy, and probe markers.
- Shared provider evidence exported `tm_rsrc_*` symbols from the combined
  archive and linked the LQ taskman with `tm_rsrcdb` selected.
- C `lq/taskman/sys/rsrcdb.c` remains present as rollback; no C source was
  retired.

Follow-up:

- Keep #151 open as `rust-default-rc` until trusted PR and main CI evidence is
  recorded. C removal still requires #26, the global retirement checklist, and
  a separate removal PR.

## 2026-06-30 18:26 CEST - tm_fdt Rust-Default RC

Scope:

- Promoted `tm_fdt` from Rust opt-in to Rust-default RC for QSOE/L while
  preserving C rollback through `QSOE_RUST_TM_FDT=0`.
- Changed the umbrella and tracked LQ component override defaults to
  `QSOE_RUST_TM_FDT ?= 1`.
- Added `tm-fdt-rc-smoke` and `tm-fdt-rc-rollback-smoke` targets plus CI hooks
  and artifact upload coverage.
- Updated `tm-fdt-runtime-smoke` so the Rust path remains default but the RC
  rollback path can explicitly reuse the live `/chosen`, `/sys`, and `sysinfo`
  boot probe with `TM_FDT_RUNTIME_ALLOW_C=1`.
- Updated shared provider evidence so `tm_fdt` is audited with the default LQ
  provider set.

Commands:

- `make tm-fdt-evidence`
- `make tm-fdt-rc-smoke`
- `make tm-fdt-rc-rollback-smoke`
- `make tm-providers-evidence`
- `make rust-quality`

Result:

- Pending validation in this worktree. C `lq/taskman/sys/fdt.c` remains present
  as rollback; no C source was retired.

Follow-up:

- Keep #146 open as `rust-default-rc` until trusted PR and main CI evidence is
  recorded. C removal still requires broader PCI/memory-topology confidence,
  the global retirement checklist, and a separate removal PR.

## 2026-06-30 18:30 CEST - tm_cred Rust-Default RC

Scope:

- Promoted `tm_cred` from Rust opt-in to Rust-default RC while preserving C
  rollback through `QSOE_RUST_TM_CRED=0`.
- Changed the umbrella, standalone `libtaskman`, and tracked NQ/LQ component
  override defaults to `QSOE_RUST_TM_CRED ?= 1`.
- Added `tm-cred-rc-smoke` and `tm-cred-rc-rollback-smoke` targets plus CI
  hooks and artifact upload coverage.
- Updated `tm-cred-runtime-smoke` so the Rust path remains default but the RC
  rollback path can explicitly reuse the live credential probe with
  `TM_CRED_RUNTIME_ALLOW_C=1`.
- Updated shared provider evidence so `tm_cred` is audited with the default
  provider set.
- Added `TASK_MANAGER_CRED_RC.md`, updated status/docs/readmes, and moved issue
  #150 to `status:rc` / `rust-default-rc`.

Commands:

- `mcp__codebase_memory_mcp.index_status(...)` for root, `lq`, and `nq`
- `mcp__codebase_memory_mcp.search_code(pattern="QSOE_RUST_TM_CRED")`
- `bash -n scripts/tm-cred-rc-smoke.sh scripts/tm-cred-runtime-smoke.sh scripts/tm-cred-evidence.sh scripts/tm-providers-evidence.sh scripts/apply-component-overrides.sh scripts/build-rust-tm-providers.sh`
- `scripts/apply-component-overrides.sh`
- `QSOE_RUST_TM_CRED=0 make -C libtaskman --no-print-directory`
- `make -C libtaskman --no-print-directory`
- `make check-tm-cred-model`
- `make tm-cred-evidence`
- `timeout 300 make tm-cred-rc-smoke`
- `timeout 300 make tm-cred-rc-rollback-smoke`
- `timeout 300 make tm-providers-evidence`
- `make roadmap-validate`
- `make roadmap-component-gate COMPONENT=tm-cred`
- `git diff --check`
- `make rust-quality`

Result:

- Root, `lq`, and `nq` codebase-memory indexes were confirmed ready before code
  discovery; `nq` was indexed when it was missing.
- Default `libtaskman.a` now omits `cred.o`; explicit
  `QSOE_RUST_TM_CRED=0` still builds the C rollback archive with `cred.o`.
- `make tm-cred-evidence` passed C/Rust host tests, soft-float archive audit,
  exported symbol checks, and NQ/LQ C rollback plus Rust-default membership
  checks.
- `make tm-cred-rc-smoke` passed the Rust-default LQ boot probe with all live
  credential markers.
- `make tm-cred-rc-rollback-smoke` passed the same LQ boot probe with the C
  rollback selected.
- `make tm-providers-evidence` passed with `tm_cpio`, `tm_cred`, and
  `tm_procfs` selected through the shared provider archive.
- Roadmap metadata validates with issue #150 reopened as an RC item.

Follow-up:

- Let trusted CI establish the RC baseline before considering any C retirement
  PR for `libtaskman/src/cred.c`.

## 2026-06-30 17:00 CEST - tm_sysfs C Retirement

Scope:

- Retired the portable task-manager `tm_sysfs` C provider after its
  Rust-default RC window.
- Removed `libtaskman/src/tm_sysfs.c` and the C host fixture
  `tests/tm_sysfs_model_test.c`.
- Made `QSOE_RUST_TM_SYSFS=1` mandatory in the umbrella, standalone
  `libtaskman`, and applied NQ/LQ component Makefiles. The old
  `QSOE_RUST_TM_SYSFS=0` selector now fails fast.
- Removed the `tm-sysfs-rc-rollback-smoke` and
  `container-tm-sysfs-rc-rollback-smoke` targets and CI step.
- Converted `check-tm-sysfs-model`, `tm-sysfs-evidence`,
  `tm-sysfs-runtime-smoke`, and `tm-sysfs-rc-smoke` to Rust-only retirement
  semantics.
- Updated adjacent provider evidence scripts so they pin
  `QSOE_RUST_TM_SYSFS=1` instead of the retired C rollback selector.
- Added `TASK_MANAGER_SYSFS_RETIREMENT.md` and updated the README, status,
  inventory, retirement, handover, and Rust workspace docs.

Commands:

- `mcp__codebase_memory_mcp.search_code(pattern="QSOE_RUST_TM_SYSFS")`
- `scripts/apply-component-overrides.sh`
- `scripts/c-index.sh files`
- `bash -n scripts/build-rust-tm-providers.sh scripts/check-tm-sysfs-model.sh scripts/tm-sysfs-evidence.sh scripts/tm-sysfs-runtime-smoke.sh scripts/tm-sysfs-rc-smoke.sh scripts/apply-component-overrides.sh scripts/tm-fdt-evidence.sh scripts/tm-rsrcdb-evidence.sh scripts/tm-cpio-evidence.sh scripts/tm-pathmgr-evidence.sh scripts/tm-script-evidence.sh`
- `QSOE_RUST_TM_SYSFS=0 scripts/build-rust-tm-providers.sh /tmp/should-not-build-tm-sysfs.a`
- `TM_SYSFS_RC_ROLLBACK=1 scripts/tm-sysfs-rc-smoke.sh`
- `QSOE_RUST_TM_SYSFS=0 scripts/tm-sysfs-rc-smoke.sh`
- `QSOE_RUST_TM_SYSFS=0 scripts/tm-sysfs-runtime-smoke.sh`
- `QSOE_RUST_TM_SYSFS=0 make -C libtaskman --no-print-directory`
- `QSOE_RUST_TM_SYSFS=0 make -n tm-sysfs-rc-smoke`
- `make -n tm-sysfs-rc-rollback-smoke`
- `make check-tm-sysfs-model`
- `make tm-sysfs-evidence`
- `timeout 300 make tm-sysfs-rc-smoke`
- `make tm-cpio-evidence`
- `make tm-script-evidence`
- `make tm-fdt-evidence`
- `make tm-rsrcdb-evidence`
- `make tm-pathmgr-evidence`
- `make tm-providers-evidence`
- `make roadmap-validate`
- `git diff --check`
- `make rust-quality`

Result:

- The component override stack applies cleanly and represents sysfs retirement
  in NQ and LQ taskman Makefiles.
- The C index now contains 807 QSOE-owned C/ASM/linker files. The indexed C
  file count drops to 515 after removing `libtaskman/src/tm_sysfs.c`.
- `qsoe-tm-sysfs` host tests pass as the canonical `/sys` model evidence.
- The sysfs evidence gate rejects retired C selectors, builds Rust provider
  archives, and verifies that NQ/LQ taskman archives contain no `tm_sysfs.o`.
- The RC smoke boots QSOE/L with the Rust `/sys` provider and reaches the
  expected `/sys/board`, `/sys/builddate`, `/sys/cmdline`, `/sys/osname`, and
  `/sys/version` checks.
- Adjacent task-manager evidence for cpio, script, fdt, rsrcdb, and pathmgr
  still passes with `QSOE_RUST_TM_SYSFS=1`.
- The aggregate task-manager provider evidence passes, including the shared
  Rust provider archive and dual-provider `/proc` smoke.
- Roadmap metadata validation, diff whitespace checks, and the Rust quality
  suite pass.

Follow-up:

- Publish the PR, wait for trusted CI, merge, and update #148 to
  `status:retired`.

## 2026-06-30 16:24 CEST - `tm_sysmap` C Provider Retirement

Scope:

- Removed the LQ C `tm_sysmap` provider implementation from
  `lq/taskman/sys/sysmap.c` through the tracked component override patch.
- Removed the C host model fixture `tests/tm_sysmap_model_test.c` and
  `tests/tm_sysmap_model_prelude.h`; the Rust `qsoe-tm-sysmap` host tests are
  now the canonical taskman sysmap model evidence.
- Made `QSOE_RUST_TM_SYSMAP=1` mandatory in the top-level and LQ taskman
  makefiles, Rust provider archive builder, and sysmap smoke/evidence scripts.
- Removed the tm_sysmap C rollback smoke target and converted rollback
  selector attempts into fail-fast configuration errors.
- Updated adjacent taskman evidence (`tm_pathmgr`) so its link-plan setup uses
  the retired Rust sysmap provider.
- Updated docs, inventory/status summaries, and component patch overlays to
  mark `tm_sysmap` as a retired C provider.

Commands:

- `mcp__codebase_memory_mcp.search_graph`
- `bash -n scripts/build-rust-tm-providers.sh scripts/check-tm-sysmap-model.sh scripts/tm-sysmap-evidence.sh scripts/tm-sysmap-runtime-smoke.sh scripts/tm-sysmap-rc-smoke.sh scripts/apply-component-overrides.sh scripts/tm-pathmgr-evidence.sh`
- `QSOE_RUST_TM_SYSMAP=0 scripts/build-rust-tm-providers.sh /tmp/should-not-build-tm-sysmap.a`
- `TM_SYSMAP_RC_ROLLBACK=1 scripts/tm-sysmap-rc-smoke.sh`
- `QSOE_RUST_TM_SYSMAP=0 scripts/tm-sysmap-rc-smoke.sh`
- `QSOE_RUST_TM_SYSMAP=0 scripts/tm-sysmap-runtime-smoke.sh`
- `scripts/apply-component-overrides.sh`
- `make check-tm-sysmap-model`
- `make tm-sysmap-evidence`
- `timeout 300 make tm-sysmap-rc-smoke`
- `make tm-pathmgr-evidence`
- `scripts/c-index.sh files`

Result:

- C index now reports 808 tracked C/asm/linker files and 129,946 LOC after
  removing the retired sysmap implementation from the LQ component overlay.
- `qsoe-tm-sysmap` host tests pass for get-before-build, minimal END-only
  syscfg, and timebase/PLIC/PCI/DesignWare syscfg page construction.
- Rust provider archives still build with the required `tm-sysmap` feature, and
  explicit `QSOE_RUST_TM_SYSMAP=0` use is rejected before archive builds or
  smoke execution.
- LQ taskman builds no longer include C `sys/sysmap.o`; the retained
  `lq/taskman/sys/sysmap.h` ABI is still used by taskman glue.
- `make tm-sysmap-rc-smoke` booted QSOE/L and observed `syscfg built from FDT`,
  `sysmap page built`, `[pci-server] scan complete`, and spawned-child
  `/usr/bin/sysinfo` output for QEMU timebase, PLIC, and PCI data.

Follow-up:

- Completed by PR #213 and roadmap issue #147. `tm_sysfs` became the next
  task-manager retirement candidate.

## 2026-06-30 15:44 CEST - `tm_syscfg` C Provider Retirement

Scope:

- Removed the C `tm_syscfg` provider implementation from
  `libtaskman/src/syscfg.c`.
- Removed the C host model fixture `tests/tm_syscfg_model_test.c`; the Rust
  `qsoe-tm-syscfg` host tests are now the canonical taskman syscfg model
  evidence.
- Made `QSOE_RUST_TM_SYSCFG=1` mandatory in the top-level, `libtaskman`, NQ/LQ
  component makefiles, Rust provider archive builder, and syscfg smoke/evidence
  scripts.
- Removed the tm_syscfg C rollback smoke target and converted rollback selector
  attempts into fail-fast configuration errors.
- Updated adjacent taskman evidence (`tm_fdt`, `tm_pathmgr`, `tm_rsrcdb`) so
  their link-plan setup uses the retired Rust syscfg provider.
- Updated docs, inventory/status summaries, and component patch overlays to
  mark `tm_syscfg` as a retired C provider.

Commands:

- `mcp__codebase_memory_mcp.list_projects`
- `mcp__codebase_memory_mcp.index_status`
- `mcp__codebase_memory_mcp.query_graph`
- `bash -n scripts/build-rust-tm-providers.sh scripts/check-tm-syscfg-model.sh scripts/tm-syscfg-evidence.sh scripts/tm-syscfg-runtime-smoke.sh scripts/tm-syscfg-rc-smoke.sh scripts/apply-component-overrides.sh scripts/tm-fdt-evidence.sh scripts/tm-pathmgr-evidence.sh scripts/tm-rsrcdb-evidence.sh`
- `QSOE_RUST_TM_SYSCFG=0 scripts/build-rust-tm-providers.sh /tmp/should-not-build-tm-syscfg.a`
- `TM_SYSCFG_RC_ROLLBACK=1 scripts/tm-syscfg-rc-smoke.sh`
- `QSOE_RUST_TM_SYSCFG=0 scripts/tm-syscfg-rc-smoke.sh`
- `QSOE_RUST_TM_SYSCFG=0 scripts/tm-syscfg-runtime-smoke.sh`
- `make check-tm-syscfg-model`
- `make tm-syscfg-evidence`
- `timeout 300 make tm-syscfg-rc-smoke`
- `make tm-fdt-evidence`
- `make tm-pathmgr-evidence`
- `make tm-rsrcdb-evidence`
- `scripts/c-index.sh files`
- `make prepare` in a fresh worktree rooted at the PR base plus the current
  patch.
- `make roadmap-validate`
- `git diff --check`
- `make rust-quality`

Result:

- C index now reports 809 tracked C/asm/linker files after removing the retired
  syscfg implementation and C fixture.
- `qsoe-tm-syscfg` host tests pass and cover finalized blob construction,
  bounded find/get behavior, malformed payload lengths, empty ASCIZ handling,
  raw NUL payload preservation, and typed length rejection.
- Rust provider archives still build with the required `tm-syscfg` feature, and
  explicit `QSOE_RUST_TM_SYSCFG=0` use is rejected before archive builds or
  smoke execution.
- NQ and LQ taskman builds no longer include `libtaskman` `syscfg.o`; the LQ
  private FDT-backed runtime syscfg builder remains C and out of scope for this
  portable provider retirement.
- The retired RC smoke boots the Rust-only syscfg path and reaches `/sys/board`,
  `/sys/cmdline`, and `/usr/bin/sysinfo` syscfg consumer milestones.
- Clean release-tag component patch application passes in a fresh worktree.
- Adjacent taskman evidence paths (`tm-fdt`, `tm-pathmgr`, `tm-rsrcdb`) pass
  after switching their link-plan setup to mandatory Rust tm_syscfg.
- Roadmap metadata validates with 38 issue-backed items.

Follow-up:

- `tm_sysmap` and `tm_sysfs` were the remaining Rust-default RC providers at
  this point and each needed its own separate retirement PR.

## 2026-06-30 15:07 CEST - `tm_elf` C Provider Retirement

Scope:

- Removed the C `tm_elf` provider implementation from `libtaskman/src/elf.c`.
- Removed the C host model fixture `tests/tm_elf_model_test.c`; the Rust
  `qsoe-tm-elf` host tests are now the canonical taskman ELF parser evidence.
- Made `QSOE_RUST_TM_ELF=1` mandatory in the top-level, `libtaskman`, NQ/LQ
  component makefiles, the Rust provider archive builder, and tm_elf
  smoke/evidence scripts.
- Removed the tm_elf C rollback smoke target and converted rollback selector
  attempts into fail-fast configuration errors.
- Updated docs, inventory/status summaries, and component patch overlays to
  mark `tm_elf` as a retired C provider.

Commands:

- `mcp__codebase_memory_mcp.index_status`
- `mcp__codebase_memory_mcp.search_graph`
- `bash -n scripts/build-rust-tm-providers.sh scripts/check-tm-elf-model.sh scripts/tm-elf-evidence.sh scripts/tm-elf-runtime-smoke.sh scripts/tm-elf-rc-smoke.sh scripts/apply-component-overrides.sh scripts/tm-fdt-evidence.sh scripts/tm-pathmgr-evidence.sh scripts/tm-sysmap-evidence.sh`
- `scripts/c-index.sh files`
- `scripts/apply-component-overrides.sh`
- `make prepare` in a fresh worktree rooted at the PR commit
- `make check-tm-elf-model`
- `QSOE_RUST_TM_ELF=0 scripts/build-rust-tm-providers.sh /tmp/should-not-build-tm-elf.a`
- `make tm-elf-evidence`
- `TM_ELF_RC_ROLLBACK=1 scripts/tm-elf-rc-smoke.sh`
- `QSOE_RUST_TM_ELF=0 scripts/tm-elf-rc-smoke.sh`
- `QSOE_RUST_TM_ELF=0 scripts/tm-elf-runtime-smoke.sh`
- `timeout 300 make tm-elf-rc-smoke`
- `make tm-fdt-evidence`
- `make tm-pathmgr-evidence`
- `make tm-sysmap-evidence`
- `make roadmap-validate`
- `git diff --check`
- `make rust-quality`

Result:

- C index now reports 810 tracked C/asm/linker files after removing the retired
  ELF implementation and C fixture.
- `qsoe-tm-elf` host tests pass and cover C ABI layout, load/interpreter range
  parsing, zero-file-size loads, malformed input rejection, wrapped span
  rejection, and load-count bounds.
- Rust provider archives still build with the required `tm-elf` feature, and
  explicit `QSOE_RUST_TM_ELF=0` use is rejected before archive builds.
- NQ and LQ taskman builds no longer include `libtaskman` `elf.o`; final
  taskman symbols resolve to the Rust `tm_elf_parse` provider.
- Clean release-tag component patch application passes in a fresh worktree.
- The retired RC smoke still boots the dynamic `/usr/bin/sysinfo` ELF spawn
  probe in Rust-retired mode.
- Adjacent taskman evidence paths (`tm-fdt`, `tm-pathmgr`, `tm-sysmap`) pass
  after switching their link-plan setup to mandatory Rust tm_elf.
- Roadmap metadata validates with 38 issue-backed items.

Follow-up:

- Open the retirement PR, watch QSOE CI, merge after green, then close issue
  #144 with the PR and main-branch CI evidence.

## 2026-06-30 14:16 CEST - `tm_cpio` C Provider Retirement

Scope:

- Removed the C `tm_cpio` provider implementation from `libtaskman/src/cpio.c`.
- Removed the C host model fixture `tests/tm_cpio_model_test.c`; the Rust
  `qsoe-tm-cpio` host tests are now the canonical CPIO model evidence.
- Made `QSOE_RUST_TM_CPIO=1` mandatory in the top-level, `libtaskman`, NQ/LQ
  component makefiles, the Rust provider archive builder, and tm_cpio
  smoke/evidence scripts.
- Removed the tm_cpio C rollback smoke target and converted rollback selector
  attempts into fail-fast configuration errors.
- Updated docs, inventory/status summaries, and component patch overlays to
  mark `tm_cpio` as a retired C provider.

Commands:

- `mcp__codebase_memory_mcp.list_projects`
- `mcp__codebase_memory_mcp.index_status`
- `mcp__codebase_memory_mcp.search_graph`
- `mcp__codebase_memory_mcp.trace_path`
- `mcp__codebase_memory_mcp.get_code_snippet`
- `bash -n scripts/build-rust-tm-providers.sh scripts/check-tm-cpio-model.sh scripts/tm-cpio-evidence.sh scripts/tm-cpio-runtime-smoke.sh scripts/tm-cpio-rc-smoke.sh scripts/apply-component-overrides.sh`
- `scripts/c-index.sh files`
- `scripts/apply-component-overrides.sh`
- `make check-tm-cpio-model`
- `QSOE_RUST_TM_CPIO=0 scripts/build-rust-tm-providers.sh /tmp/should-not-build-tm-cpio.a`
- `make tm-cpio-evidence`
- `TM_CPIO_RC_ROLLBACK=1 scripts/tm-cpio-rc-smoke.sh`
- `QSOE_RUST_TM_CPIO=0 scripts/tm-cpio-rc-smoke.sh`
- `timeout 300 make tm-cpio-rc-smoke`
- `make tm-fdt-evidence`
- `make tm-pathmgr-evidence`
- `make tm-rsrcdb-evidence`
- `make roadmap-validate`
- `git diff --check`
- `make rust-quality`

Result:

- C index now reports 811 tracked C/asm/linker files and 130,410 approximate
  LOC after removing the retired CPIO implementation and C fixture.
- `qsoe-tm-cpio` host tests pass and cover archive iteration, exact lookup,
  symlink resolution, directory entries, directory existence, short output
  buffers, missing paths, malformed archive stopping, and unaligned archive
  pointers.
- Rust provider archives still build with the required `tm-cpio` feature, and
  explicit `QSOE_RUST_TM_CPIO=0` use is rejected before archive builds.
- NQ and LQ taskman builds no longer include `libtaskman` `cpio.o`; final
  taskman symbols resolve to the Rust `tm_cpio_*` provider.
- The retired RC smoke still boots the CPIO symlink listing, `/etc/passwd`
  symlink read, direct `/sbin/init` boot-CPIO read, and `/bin/sh` symlink
  spawn probes in Rust-retired mode.
- Adjacent taskman evidence paths (`tm-fdt`, `tm-pathmgr`, `tm-rsrcdb`) pass
  after switching their link-plan setup to mandatory Rust tm_cpio.
- Roadmap metadata validates with 38 issue-backed items.

Follow-up:

- Open the retirement PR, watch QSOE CI, merge after green, then close issue
  #142 with the PR and main-branch CI evidence.

## 2026-06-30 12:40 CEST - `tm_script` C Provider Retirement

Scope:

- Removed the C `tm_script` provider implementation from
  `libtaskman/src/script.c`.
- Removed the C host model fixture `tests/tm_script_model_test.c`; the Rust
  `qsoe-tm-script` host tests are now the canonical parser evidence.
- Made `QSOE_RUST_TM_SCRIPT=1` mandatory in the top-level and libtaskman
  makefiles, the Rust provider archive builder, component override patches, and
  tm_script smoke/evidence scripts.
- Removed the tm_script C rollback smoke target and converted rollback selector
  attempts into fail-fast configuration errors.
- Updated docs, inventory/status summaries, and the component patch overlay to
  mark `tm_script` as a retired C provider.

Commands:

- `mcp__codebase_memory_mcp.list_projects`
- `mcp__codebase_memory_mcp.index_status`
- `mcp__codebase_memory_mcp.search_graph`
- `bash -n scripts/build-rust-tm-providers.sh scripts/check-tm-script-model.sh scripts/tm-script-evidence.sh scripts/tm-script-runtime-smoke.sh scripts/tm-script-rc-smoke.sh scripts/apply-component-overrides.sh`
- `scripts/apply-component-overrides.sh`
- `make check-tm-script-model`
- `QSOE_RUST_TM_SCRIPT=0 scripts/build-rust-tm-providers.sh /tmp/should-not-build-tm-script.a`
- `make tm-script-evidence`
- `TM_SCRIPT_RC_ROLLBACK=1 scripts/tm-script-rc-smoke.sh`
- `QSOE_RUST_TM_SCRIPT=0 scripts/tm-script-rc-smoke.sh`
- `timeout 300 make tm-script-rc-smoke`
- `make tm-fdt-evidence`
- `make tm-pathmgr-evidence`
- `make tm-rsrcdb-evidence`
- `make roadmap-validate`
- `git diff --check`
- `make rust-quality`

Result:

- `qsoe-tm-script` host tests pass and cover shebang parsing, empty or invalid
  interpreter rejection, CR line endings, and C-compatible truncation behavior.
- Rust provider archives still build with the required `tm-script` feature, and
  explicit `QSOE_RUST_TM_SCRIPT=0` use is rejected before any archive build.
- NQ and LQ taskman builds no longer include `script.o`; final taskman symbols
  resolve to the Rust `tm_script_parse_shebang` provider.
- The runtime RC smoke still boots the direct shebang spawn probe and exits
  cleanly in Rust-retired mode.
- Adjacent taskman evidence paths (`tm-fdt`, `tm-pathmgr`, `tm-rsrcdb`) pass
  after switching their link-plan setup to the mandatory Rust tm_script provider.
- Roadmap metadata validates with 38 issue-backed items.

Follow-up:

- Open the retirement PR, watch QSOE CI, merge after green, then close issue
  #143 with the PR and main-branch CI evidence.

## 2026-06-30 11:21 CEST - CI Cache And `sccache` Prototype

Scope:

- Added `sccache` to the Debian toolchain image.
- Added persistent container cache mounts under `.qsoe-cache/container` for
  home, Cargo registry/git state, and the `sccache` object store.
- Added `QSOE_SCCACHE=1` for Rust `RUSTC_WRAPPER=sccache` and
  `QSOE_SCCACHE_C=1` for compiler-name-preserving C/C++ wrappers inside the
  container.
- `QSOE_SCCACHE=1` defaults `CARGO_INCREMENTAL=0` unless the caller overrides
  it, because incremental Rust dev-profile builds are not cacheable by
  `sccache`.
- Added a pinned `actions/cache` restore/save step for Cargo registry/git and
  `sccache` data only; QSOE build products, `rust/target`, images, and logs
  remain uncached.
- Added `make container-sccache-stats` for ad hoc cache-store visibility.
- Added `QSOE_SCCACHE_STATS=1` for CI so each container invocation prints its
  own `sccache --show-stats` output before exiting.

Commands:

- `mcp__codebase_memory_mcp.index_status`
- `mcp__codebase_memory_mcp.search_graph`
- `mcp__codebase_memory_mcp.get_code_snippet`
- `docker run --rm debian:trixie bash -lc 'apt-get update >/dev/null && apt-cache policy sccache'`
- `bash -n scripts/container-toolchain.sh scripts/sccache-compiler-wrapper.sh`
- `git diff --check`
- `make container-toolchain-build`
- `QSOE_SCCACHE=1 QSOE_SCCACHE_C=1 scripts/container-toolchain.sh run bash -c '...'`
- `QSOE_SCCACHE=1 QSOE_SCCACHE_C=1 scripts/container-toolchain.sh run bash -lc '...'`
- `QSOE_SCCACHE=1 QSOE_SCCACHE_STATS=1 scripts/container-toolchain.sh run bash -c 'rm -rf /tmp/qsoe-rust-sccache-smoke; CARGO_TARGET_DIR=/tmp/qsoe-rust-sccache-smoke cargo check --manifest-path rust/Cargo.toml -p qsoe-abi'`
- `QSOE_SCCACHE=1 QSOE_SCCACHE_C=1 QSOE_SCCACHE_STATS=1 make container-rust-fast`
- `QSOE_SCCACHE=1 QSOE_SCCACHE_C=1 QSOE_SCCACHE_STATS=1 scripts/container-toolchain.sh run bash -c 'QSOE_INDEX_CLEAN=1 QSOE_INDEX_DB_FLAVOR=container make index-c-compile-db; QSOE_TIDY_LIMIT=10 make tidy-c'`

Result:

- Debian trixie provides `sccache` 0.10.0-4 from `main`.
- The wrapper path works for both non-login and login shells; both resolve
  `gcc` and `riscv64-linux-gnu-gcc` through `/tmp/qsoe-sccache-wrappers`.
- The C/C++ smoke records cacheable host and RISC-V GCC requests, then repeats
  as cache hits from the persisted `.qsoe-cache/container/sccache` store.
- A forced Rust `qsoe-abi` compile first records one Rust cache miss and then
  repeats as one Rust cache hit when run again with a fresh target directory.
- `make container-rust-fast` passes with the CI cache environment and recorded
  32 cacheable Rust misses during the first post-incremental-disable run.
- PR CI run 28434537628 failed in the compile-database step when the initial
  `build/cache/container` location was removed by `make clean` while mounted as
  `/tmp/qsoe-sccache`; the cache root was moved to `.qsoe-cache/container`.
- The failed CI step was reproduced locally after the move: it generated 878
  compile commands, ran bounded clang-tidy, and finished with 871 executed
  C/C++ `sccache` requests and no cache errors.
- Baseline before the cache change: `main` CI run 28431125597 completed in
  7m41s wall time on 2026-06-30, and the taskman RC smoke steps were 6-8s each.
- After timings are pending the cache PR run and the follow-up `main` run,
  because the first run may be a cold cache population.

Follow-up:

- Record the PR/main CI timings and `sccache --show-stats` output in #201.
- Close #201 only after the cache wiring passes CI and the issue records the
  before/after evidence.

## 2026-06-30 10:21 CEST - Component Gate Harness

Scope:

- Added `scripts/roadmap-gates.py` with two commands:
  - `validate` parses every `qsoe-roadmap:v1` issue block from live GitHub
    Issues API data and checks roadmap/kind/status label consistency.
  - `component <selector>` prints the selectors, evidence, runtime/boot smoke,
    RC, rollback, and issue-update checklist for a roadmap component.
- Added top-level Make targets:
  - `make roadmap-validate`
  - `make roadmap-component-gate COMPONENT=<id-or-issue-number>`
- Wired `make roadmap-validate` into main CI before build work and into the
  Roadmap Pages workflow before dashboard publication.
- Documented the commands in `WORKFLOW.md`, the top-level README, and the
  migration docs index.

Commands:

- `mcp__codebase_memory_mcp.list_projects`
- `gh issue view 200 --json number,title,state,labels,body,comments`
- `make roadmap-validate`
- `make roadmap-component-gate COMPONENT=tm-elf-view`
- `make roadmap-component-gate COMPONENT=146`

Result:

- Live roadmap metadata currently validates: 38 metadata items across 17
  components, 11 phases, 6 backlog candidates, and 4 tooling gates.
- Component checklists now come directly from issue metadata instead of manual
  reconstruction during RC and retirement work.
- Codebase Memory MCP still failed with `Transport closed`, so this change used
  the documented fallback discovery path.

Follow-up:

- After this PR lands, update #200 from `status:future` to complete and close
  it with the PR/main CI run evidence.

## 2026-06-30 09:58 CEST - Graph-First Workflow Rule

Scope:

- Documented the Codebase Memory MCP graph as the first stop for code
  discovery in the Rust migration workflow.
- Added explicit fallback rules for literal/config/non-code searches and MCP
  outage cases.
- Updated the top-level README and migration index so the workflow entry points
  advertise graph-first discovery.

Commands:

- `mcp__codebase_memory_mcp.list_projects`
- `rg -n "Codebase|codebase|MCP|Tooling|Operating Loop|Issue-Backed" README.md docs/rust-migration docs/roadmap || true`

Result:

- The process now matches `AGENTS.md`: use `search_graph`, `trace_path`, and
  `get_code_snippet` before broad local text search for code navigation.
- Current MCP attempt failed with `Transport closed`, so this documentation
  update used the defined fallback path.

Follow-up:

- Keep #200 as the automation point for enforcing roadmap and per-component
  workflow checks.

## 2026-06-30 09:37 CEST - Issue-Backed Tooling Gates

Scope:

- Created `roadmap:tooling` tracking for migration process improvements.
- Opened tooling roadmap issues:
  - #200 component gate harness and roadmap sync;
  - #201 CI cache and `sccache` acceleration;
  - #202 CodeQL, dependency review, and static security gates;
  - #203 `cargo-nextest`, parser fuzzing, and coverage workflow.
- Extended the GitHub Pages roadmap dashboard to parse `kind: "tooling"` issue
  metadata and render a separate Tooling Gates table.
- Updated `WORKFLOW.md`, `README.md`, and `HANDOVER.md` so quality/speed
  tooling is part of the normal migration process instead of an informal
  recommendation list.

Commands:

- `gh label create roadmap:tooling --description 'Roadmap item for migration tooling and process automation' --color 5319e7`
- `gh issue create ...` for #200, #201, #202, and #203
- `gh issue list --label roadmap:tooling --state open --json number,title,labels,body`

Result:

- Tooling work now has issue-backed source-of-truth metadata and dashboard
  visibility.
- The process distinguishes non-blocking/new tooling gates from required
  component migration gates until each tool has a clean baseline.

Follow-up:

- Implement #200 first so future component RC/retirement work can generate and
  validate evidence checklists from issue metadata.

## 2026-06-30 09:00 CEST - tm_elf Rust-Default RC

Scope:

- Promoted the portable task-manager `tm_elf` view parser to a Rust-default
  release-candidate selector: `QSOE_RUST_TM_ELF ?= 1` in the umbrella and
  applied NQ/LQ component Makefiles.
- Added component override patches that flip ignored NQ/LQ checkouts to the
  new default while preserving `QSOE_RUST_TM_ELF=0` as C rollback.
- Added `make tm-elf-rc-smoke` and `make tm-elf-rc-rollback-smoke`; both verify
  NQ/LQ taskman link-plan membership before booting the live dynamic
  `/usr/bin/sysinfo` spawn probe.
- Added CI wiring and `TASK_MANAGER_ELF_RC.md` to record the RC window and
  rollback drill. Segment mapping, dynamic-linker admission, relocation,
  process tables, CPIO/script handling, capability ownership, and seL4 object
  code remain C.

Commands:

- `bash -n scripts/tm-elf-rc-smoke.sh scripts/tm-elf-runtime-smoke.sh scripts/tm-elf-evidence.sh scripts/apply-component-overrides.sh scripts/boot-smoke.sh`
- `make -n tm-elf-rc-smoke tm-elf-rc-rollback-smoke container-tm-elf-rc-smoke container-tm-elf-rc-rollback-smoke`
- `patch -d nq --dry-run --fuzz=0 -p1 < patches/components/nq-taskman-rust-tm-elf-rc-default.patch`
- `patch -d lq --dry-run --fuzz=0 -p1 < patches/components/lq-makefile-rust-tm-elf-rc-default.patch`
- `patch -d lq --dry-run --fuzz=0 -p1 < patches/components/lq-taskman-rust-tm-elf-rc-default.patch`
- `./scripts/apply-component-overrides.sh`
- `patch -d nq --dry-run --fuzz=0 -R -p1 < patches/components/nq-taskman-rust-tm-elf-rc-default.patch`
- `patch -d lq --dry-run --fuzz=0 -R -p1 < patches/components/lq-makefile-rust-tm-elf-rc-default.patch`
- `patch -d lq --dry-run --fuzz=0 -R -p1 < patches/components/lq-taskman-rust-tm-elf-rc-default.patch`
- `make tm-elf-rc-smoke`
- `make tm-elf-rc-rollback-smoke`
- `make tm-elf-evidence`
- `make tm-elf-runtime-smoke`

Result:

- The component override stack applies cleanly and leaves NQ/LQ selectors at
  `QSOE_RUST_TM_ELF ?= 1`.
- Default RC builds omit C `elf.o` from both NQ and LQ `libtaskman.a`; rollback
  builds restore exactly one C `elf.o` in each archive.
- Both default and rollback RC smokes boot QSOE/L and reach
  `tm-elf-runtime-smoke: /usr/bin/sysinfo dynamic ELF spawn ok`.
- `make tm-elf-evidence` passes the C host fixture, Rust host tests, soft-float
  archive audit, exported-symbol audit, and C-rollback/Rust-default link-plan
  checks.

Follow-up:

- Keep `libtaskman/src/elf.c` as rollback until #26's retirement checklist and
  a separate removal PR are satisfied.
- `tm_fdt` remains the only open Rust opt-in provider with enough runtime
  evidence for the next small RC candidate.

## 2026-06-30 08:36 CEST - tm_sysmap Rust-Default RC

Scope:

- Promoted the LQ `tm_sysmap` page builder to a Rust-default
  release-candidate selector: `QSOE_RUST_TM_SYSMAP ?= 1` in the umbrella and
  applied LQ component Makefiles.
- Added component override patches that flip ignored LQ checkouts to the new
  default while preserving `QSOE_RUST_TM_SYSMAP=0` as C rollback.
- Added `make tm-sysmap-rc-smoke` and
  `make tm-sysmap-rc-rollback-smoke`; both verify LQ taskman link-plan
  membership before booting the live spawned-child `PSYS`/`sysinfo` consumer
  probe.
- Added CI wiring and `TASK_MANAGER_SYSMAP_RC.md` to record the RC window and
  rollback drill. FDT parsing, syscfg construction, child VSpace mapping, and
  seL4 object code remain C.

Commands:

- `bash -n scripts/tm-sysmap-rc-smoke.sh scripts/tm-sysmap-runtime-smoke.sh scripts/tm-sysmap-evidence.sh scripts/apply-component-overrides.sh scripts/boot-smoke.sh`
- `make -n tm-sysmap-rc-smoke tm-sysmap-rc-rollback-smoke container-tm-sysmap-rc-smoke container-tm-sysmap-rc-rollback-smoke`
- `patch -d lq --dry-run --fuzz=0 -p1 < patches/components/lq-makefile-rust-tm-sysmap-rc-default.patch`
- `patch -d lq --dry-run --fuzz=0 -p1 < patches/components/lq-taskman-rust-tm-sysmap-rc-default.patch`
- `./scripts/apply-component-overrides.sh`
- `patch -d lq --reverse --dry-run --fuzz=0 -p1 < patches/components/lq-makefile-rust-tm-sysmap-rc-default.patch`
- `patch -d lq --reverse --dry-run --fuzz=0 -p1 < patches/components/lq-taskman-rust-tm-sysmap-rc-default.patch`
- `make tm-sysmap-rc-smoke`
- `make tm-sysmap-rc-rollback-smoke`
- `make tm-sysmap-evidence`
- `make tm-sysmap-runtime-smoke`
- `git diff --check`
- `make check-qrvfs-rust-writer-production-root`
- `make -C libtaskman --no-print-directory`

Result:

- `make tm-sysmap-rc-smoke` passed with the default Rust link plan omitting
  `sys/sysmap.o`, then reached the live syscfg, sysmap, pci-server, and
  `sysinfo` timebase/PLIC/PCI runtime markers.
- `make tm-sysmap-rc-rollback-smoke` passed with C rollback selected and the
  link plan containing `sys/sysmap.o`, then reached the same live runtime
  markers under `QSOE_RUST_TM_SYSMAP=0`.
- The existing `tm-sysmap-evidence` and `tm-sysmap-runtime-smoke` gates still
  pass after the default flip.

Follow-up:

- Publish the PR, wait for trusted CI, merge, and update #147 to
  `status:rc`.

## 2026-06-30 08:15 CEST - tm_syscfg Rust-Default RC

Scope:

- Promoted the portable `tm_syscfg` provider to a Rust-default
  release-candidate selector: `QSOE_RUST_TM_SYSCFG ?= 1` in the umbrella,
  `libtaskman`, and applied NQ/LQ component Makefiles.
- Added component override patches that flip ignored NQ/LQ checkouts to the
  new default while preserving `QSOE_RUST_TM_SYSCFG=0` as C rollback.
- Added `make tm-syscfg-rc-smoke` and
  `make tm-syscfg-rc-rollback-smoke`; both verify NQ/LQ `libtaskman.a`
  archive membership before booting the live LQ `/sys` and `sysinfo`
  consumer probe.
- Added CI wiring and `TASK_MANAGER_SYSCFG_RC.md` to record the RC window and
  rollback drill. LQ's private FDT-backed runtime syscfg builder remains C.

Commands:

- `bash -n scripts/tm-syscfg-rc-smoke.sh scripts/tm-syscfg-runtime-smoke.sh scripts/tm-syscfg-evidence.sh scripts/apply-component-overrides.sh scripts/boot-smoke.sh`
- `make -n tm-syscfg-rc-smoke tm-syscfg-rc-rollback-smoke container-tm-syscfg-rc-smoke container-tm-syscfg-rc-rollback-smoke`
- `patch -d nq --dry-run --fuzz=0 -p1 < patches/components/nq-taskman-rust-tm-syscfg-rc-default.patch`
- `patch -d lq --dry-run --fuzz=0 -p1 < patches/components/lq-makefile-rust-tm-syscfg-rc-default.patch`
- `patch -d lq --dry-run --fuzz=0 -p1 < patches/components/lq-taskman-rust-tm-syscfg-rc-default.patch`
- `./scripts/apply-component-overrides.sh`
- `patch -d nq --reverse --dry-run --fuzz=0 -p1 < patches/components/nq-taskman-rust-tm-syscfg-rc-default.patch`
- `patch -d lq --reverse --dry-run --fuzz=0 -p1 < patches/components/lq-makefile-rust-tm-syscfg-rc-default.patch`
- `patch -d lq --reverse --dry-run --fuzz=0 -p1 < patches/components/lq-taskman-rust-tm-syscfg-rc-default.patch`
- `make tm-syscfg-rc-smoke`
- `make tm-syscfg-rc-rollback-smoke`
- `make tm-syscfg-evidence`
- `make tm-syscfg-runtime-smoke`
- `git diff --check`
- `make check-qrvfs-rust-writer-production-root`
- `make -C libtaskman --no-print-directory`

Result:

- `make tm-syscfg-rc-smoke` passed with `nq-rust-default syscfg.o count: 0`
  and `lq-rust-default syscfg.o count: 0`, then reached the live syscfg,
  sysmap, `/sys/board`, `/sys/cmdline`, and `sysinfo` runtime markers.
- `make tm-syscfg-rc-rollback-smoke` passed with
  `nq-c-rollback syscfg.o count: 1` and
  `lq-c-rollback syscfg.o count: 1`, then reached the same live runtime
  markers under `QSOE_RUST_TM_SYSCFG=0`.
- The existing `tm-syscfg-evidence` and `tm-syscfg-runtime-smoke` gates still
  pass after the default flip.

Follow-up:

- Publish the PR, wait for trusted CI, merge, and update #145 to
  `status:rc`.

## 2026-06-30 02:17 CEST - tm_sysfs Rust-Default RC

Scope:

- Promoted `tm_sysfs` to a Rust-default release-candidate selector:
  `QSOE_RUST_TM_SYSFS ?= 1` in the umbrella, `libtaskman`, and applied NQ/LQ
  component Makefiles.
- Added component override patches that flip ignored NQ/LQ checkouts to the
  new default while preserving `QSOE_RUST_TM_SYSFS=0` as C rollback.
- Added `make tm-sysfs-rc-smoke` and `make tm-sysfs-rc-rollback-smoke`; both
  verify NQ/LQ `libtaskman.a` archive membership before booting the live LQ
  `/sys` readdir and file-read probe.
- Added CI wiring and `TASK_MANAGER_SYSFS_RC.md` to record the RC window and
  rollback drill.

Commands:

- `bash -n scripts/tm-sysfs-rc-smoke.sh scripts/tm-sysfs-runtime-smoke.sh scripts/tm-sysfs-evidence.sh scripts/apply-component-overrides.sh scripts/boot-smoke.sh`
- `make -n tm-sysfs-rc-smoke tm-sysfs-rc-rollback-smoke container-tm-sysfs-rc-smoke container-tm-sysfs-rc-rollback-smoke`
- `patch -d nq --dry-run -p1 < patches/components/nq-taskman-rust-tm-sysfs-rc-default.patch`
- `patch -d lq --dry-run -p1 < patches/components/lq-makefile-rust-tm-sysfs-rc-default.patch`
- `patch -d lq --dry-run -p1 < patches/components/lq-taskman-rust-tm-sysfs-rc-default.patch`
- `./scripts/apply-component-overrides.sh`
- `patch -d nq --reverse --dry-run -p1 < patches/components/nq-taskman-rust-tm-sysfs-rc-default.patch`
- `patch -d lq --reverse --dry-run -p1 < patches/components/lq-makefile-rust-tm-sysfs-rc-default.patch`
- `patch -d lq --reverse --dry-run -p1 < patches/components/lq-taskman-rust-tm-sysfs-rc-default.patch`
- `make tm-sysfs-rc-smoke`
- `make tm-sysfs-rc-rollback-smoke`
- `make tm-sysfs-evidence`
- `make tm-sysfs-runtime-smoke`
- `git diff --check`
- `make check-qrvfs-rust-writer-production-root`
- `make -C libtaskman --no-print-directory`

Result:

- `make tm-sysfs-rc-smoke` passed with `nq-rust-default tm_sysfs.o count: 0`
  and `lq-rust-default tm_sysfs.o count: 0`, then reached all live `/sys`
  runtime markers.
- `make tm-sysfs-rc-rollback-smoke` passed with
  `nq-c-rollback tm_sysfs.o count: 1` and
  `lq-c-rollback tm_sysfs.o count: 1`, then reached the same live runtime
  markers under `QSOE_RUST_TM_SYSFS=0`.
- The existing `tm-sysfs-evidence` and `tm-sysfs-runtime-smoke` gates still
  pass after the default flip.

Follow-up:

- Publish the PR, wait for trusted CI, merge, and update #148 to
  `status:rc`.

## 2026-06-30 01:52 CEST - tm_script Rust-Default RC

Scope:

- Promoted `tm_script` to a Rust-default release-candidate selector:
  `QSOE_RUST_TM_SCRIPT ?= 1` in the umbrella, `libtaskman`, and applied NQ/LQ
  component Makefiles.
- Added component override patches that flip ignored NQ/LQ checkouts to the
  new default while preserving `QSOE_RUST_TM_SCRIPT=0` as C rollback.
- Added `make tm-script-rc-smoke` and `make tm-script-rc-rollback-smoke`; both
  verify NQ/LQ `libtaskman.a` archive membership before booting the live LQ
  shebang parser probe.
- Added CI wiring and `TASK_MANAGER_SCRIPT_RC.md` to record the RC window and
  rollback drill.

Commands:

- `bash -n scripts/tm-script-rc-smoke.sh scripts/tm-script-runtime-smoke.sh scripts/tm-script-evidence.sh scripts/apply-component-overrides.sh scripts/boot-smoke.sh`
- `make -n tm-script-rc-smoke tm-script-rc-rollback-smoke container-tm-script-rc-smoke container-tm-script-rc-rollback-smoke`
- `patch -d nq --reverse --dry-run -p1 < patches/components/nq-taskman-rust-tm-script-rc-default.patch`
- `patch -d lq --reverse --dry-run -p1 < patches/components/lq-makefile-rust-tm-script-rc-default.patch`
- `patch -d lq --reverse --dry-run -p1 < patches/components/lq-taskman-rust-tm-script-rc-default.patch`
- `./scripts/apply-component-overrides.sh`
- `make tm-script-rc-smoke`
- `make tm-script-rc-rollback-smoke`
- `make tm-script-evidence`
- `make tm-script-runtime-smoke`
- `git diff --check`
- `make check-qrvfs-rust-writer-production-root`
- `make -C libtaskman --no-print-directory`

Result:

- `make tm-script-rc-smoke` passed with `nq-rust-default script.o count: 0`
  and `lq-rust-default script.o count: 0`, then reached the live shebang
  runtime markers.
- `make tm-script-rc-rollback-smoke` passed with
  `nq-c-rollback script.o count: 1` and `lq-c-rollback script.o count: 1`,
  then reached the same live runtime markers under `QSOE_RUST_TM_SCRIPT=0`.
- The existing `tm-script-evidence` and `tm-script-runtime-smoke` gates still
  pass after the default flip.

Follow-up:

- Publish the PR, wait for trusted CI, merge, and update #143 to
  `status:rc`.

## 2026-06-30 01:30 CEST - tm_cpio Rust-Default RC

Scope:

- Promoted `tm_cpio` to a Rust-default release-candidate selector:
  `QSOE_RUST_TM_CPIO ?= 1` in the umbrella, `libtaskman`, and applied NQ/LQ
  component Makefiles.
- Added component override patches that flip ignored NQ/LQ checkouts to the
  new default while preserving `QSOE_RUST_TM_CPIO=0` as C rollback.
- Added `make tm-cpio-rc-smoke` and `make tm-cpio-rc-rollback-smoke`; both
  verify NQ/LQ `libtaskman.a` archive membership before booting the live LQ
  CPIO symlink, file-read, and `/bin/sh` symlink-spawn probes.
- Added CI wiring and `TASK_MANAGER_CPIO_RC.md` to record the RC window and
  rollback drill.

Commands:

- `bash -n scripts/tm-cpio-rc-smoke.sh scripts/tm-cpio-runtime-smoke.sh scripts/tm-cpio-evidence.sh scripts/apply-component-overrides.sh scripts/boot-smoke.sh`
- `make -n tm-cpio-rc-smoke tm-cpio-rc-rollback-smoke container-tm-cpio-rc-smoke container-tm-cpio-rc-rollback-smoke`
- `patch -d nq --reverse --dry-run -p1 < patches/components/nq-taskman-rust-tm-cpio-rc-default.patch`
- `patch -d lq --reverse --dry-run -p1 < patches/components/lq-makefile-rust-tm-cpio-rc-default.patch`
- `patch -d lq --reverse --dry-run -p1 < patches/components/lq-taskman-rust-tm-cpio-rc-default.patch`
- `./scripts/apply-component-overrides.sh`
- `make tm-cpio-rc-smoke`
- `make tm-cpio-rc-rollback-smoke`
- `make tm-cpio-evidence`
- `make tm-cpio-runtime-smoke`
- `git diff --check`
- `make check-qrvfs-rust-writer-production-root`
- `make -C libtaskman --no-print-directory`

Result:

- `make tm-cpio-rc-smoke` passed with `nq-rust-default cpio.o count: 0` and
  `lq-rust-default cpio.o count: 0`, then reached all live CPIO runtime
  markers.
- `make tm-cpio-rc-rollback-smoke` passed with `nq-c-rollback cpio.o count: 1`
  and `lq-c-rollback cpio.o count: 1`, then reached the same live runtime
  markers under `QSOE_RUST_TM_CPIO=0`.
- The existing `tm-cpio-evidence` and `tm-cpio-runtime-smoke` gates still pass
  after the default flip.

Follow-up:

- Publish the PR, wait for trusted CI, merge, and update #142 to
  `status:rc`.

## 2026-06-30 01:12 CEST - tm_pseudodev Runtime Smoke

Scope:

- Added `make tm-pseudodev-runtime-smoke` and container CI wiring.
- Added `/usr/bin/pseudodev_probe`, a qrvfs-staged helper that exercises live
  `/dev/null` and `/dev/zero` open, write, read, and fstat calls through libc.
- The smoke rebuilds QSOE/L with `QSOE_RUST_TM_PSEUDODEV=1` and mandatory
  `QSOE_RUST_TM_PROCFS=1`, verifies the selected `libtaskman.a` omits C
  `devnull.o` and `devzero.o`, and verifies the Rust provider archive exports
  the six `tm_dev*` ABI symbols.
- The helper is staged only through the smoke-specific `FSQRV_BINS`, keeping the
  production qrvfs root unchanged.

Commands:

- `bash -n scripts/tm-pseudodev-runtime-smoke.sh scripts/apply-component-overrides.sh scripts/boot-smoke.sh`
- `make -n tm-pseudodev-runtime-smoke container-tm-pseudodev-runtime-smoke`
- `patch -d quser --reverse --dry-run -p1 < patches/components/quser-pseudodev-probe.patch`
- `./scripts/apply-component-overrides.sh`
- `make tm-pseudodev-runtime-smoke`
- `make tm-pseudodev-evidence`
- `git diff --check`
- `make check-qrvfs-rust-writer-production-root`

Result:

- `make tm-pseudodev-runtime-smoke` passes locally with markers for
  `/dev/null` write discard, `/dev/null` fstat, `/dev/null` EOF read,
  `/dev/zero` write discard, `/dev/zero` fstat, `/dev/zero` zero-filled read,
  and final probe success.
- `make tm-pseudodev-evidence` continues to pass, including Rust host tests,
  provider archive audit, and LQ C-default/Rust-selected link checks.
- The runtime smoke closes the pseudo-device runtime coverage gate for #152,
  but `tm_pseudodev` remains Rust opt-in pending a separate Rust-default RC
  decision.

Follow-up:

- Publish the PR, wait for trusted CI, merge, and update #152.

## 2026-06-30 00:56 CEST - tm_rsrcdb Runtime Smoke

Scope:

- Added `make tm-rsrcdb-runtime-smoke` and container CI wiring.
- Added `/usr/bin/rsrcdb_probe`, a qrvfs-staged smoke helper that exercises
  public `rsrcdbmgr_*` create, attach, query, detach, and destroy calls.
- The smoke rebuilds QSOE/L with `QSOE_RUST_TM_RSRCDB=1` and mandatory
  `QSOE_RUST_TM_PROCFS=1`, verifies the selected `libtaskman.a` omits C
  `rsrcdb.o`, and verifies the Rust provider archive exports the `tm_rsrc_*`
  ABI.
- The helper is staged only through the smoke-specific `FSQRV_BINS`, keeping the
  production qrvfs root unchanged.

Commands:

- `bash -n scripts/tm-rsrcdb-runtime-smoke.sh scripts/apply-component-overrides.sh scripts/boot-smoke.sh`
- `make -n tm-rsrcdb-runtime-smoke container-tm-rsrcdb-runtime-smoke`
- `patch -d quser --reverse --dry-run -p1 < patches/components/quser-rsrcdb-probe.patch`
- `./scripts/apply-component-overrides.sh`
- `make tm-rsrcdb-runtime-smoke`
- `make tm-rsrcdb-evidence`
- `git diff --check`
- `make check-qrvfs-rust-writer-production-root`

Result:

- `make tm-rsrcdb-runtime-smoke` passes locally with markers for create, query
  after create, attach, query after attach, detach merge, destroy, and final
  probe success.
- `make tm-rsrcdb-evidence` continues to pass, including C/Rust host tests,
  provider archive audit, and LQ C-default/Rust-selected link checks.
- The runtime smoke closes the resource-DB caller coverage gate for #151, but
  `tm_rsrcdb` remains Rust opt-in pending a separate Rust-default RC decision.

Follow-up:

- Publish the PR, wait for trusted CI, merge, and update #151.

## 2026-06-30 00:37 CEST - tm_cred Runtime Smoke

Scope:

- Added `make tm-cred-runtime-smoke` and container CI wiring.
- Added `/usr/bin/cred_probe`, a qrvfs-staged smoke helper that exercises
  taskman-backed `getuid`/`geteuid`/`getgid`/`getegid`, `setregid`, `setgid`,
  `setreuid`, `seteuid`, `setuid`, `umask`, `chdir`, `getcwd`, and child spawn
  inheritance.
- The smoke rebuilds QSOE/L with `QSOE_RUST_TM_CRED=1` and mandatory
  `QSOE_RUST_TM_PROCFS=1`, verifies the selected `libtaskman.a` omits C
  `cred.o`, and verifies the Rust provider archive exports the `tm_cred_*` ABI.
- The helper is staged only through the smoke-specific `FSQRV_BINS`, keeping the
  production qrvfs root unchanged.

Commands:

- `bash -n scripts/tm-cred-runtime-smoke.sh scripts/apply-component-overrides.sh scripts/boot-smoke.sh`
- `make -n tm-cred-runtime-smoke container-tm-cred-runtime-smoke`
- `./scripts/apply-component-overrides.sh`
- `patch -d quser --reverse --dry-run -p1 < patches/components/quser-cred-probe.patch`
- `make tm-cred-runtime-smoke`
- `make tm-cred-evidence`
- `make check-qrvfs-rust-writer-production-root`
- `git diff --check`

Result:

- `make tm-cred-runtime-smoke` passes locally with markers for initial root ids,
  umask exchange, cwd round-trip, uid/gid mutation, non-root permission
  rejection, child inherited state, spawn inheritance, and final probe success.
- `make tm-cred-evidence` continues to pass, including C/Rust host tests,
  provider archive audit, and NQ/LQ C-default/Rust-selected link checks.
- The runtime smoke closes the credential-specific next gate for #150, but
  `tm_cred` remains Rust opt-in pending a separate Rust-default RC decision.

Follow-up:

- Publish the PR, wait for trusted CI, merge, and update #150.

## 2026-06-29 23:51 CEST - tm_pathmgr Runtime Smoke

Scope:

- Added `make tm-pathmgr-runtime-smoke` and container CI wiring.
- Added `/usr/bin/pathmgr_probe`, a small qrvfs-staged test helper that spawns
  a child, registers `/dev/pathmgr_probe`, resolves the child binding,
  rejects duplicate registration, sends through the resolved channel, reaps the
  child, and verifies the registration disappears after process teardown.
- The smoke rebuilds QSOE/L with `QSOE_RUST_TM_PATHMGR=1` and mandatory
  `QSOE_RUST_TM_PROCFS=1`.
- It verifies the Rust-selected `libtaskman.a` omits C `pathmgr.o`, verifies
  all nine `tm_pathmgr_*` ABI symbols in the shared Rust provider archive, and
  exercises `/dev` PMDIR readdir, `/etc/passwd` through the cpio-root symlink,
  `/dev/console` repath to `/dev/ser1`, and the helper lifecycle.
- Added a tracked LQ component override that raises taskman's bootstrap stack
  from 8 KiB to 32 KiB. Rust `tm_pathmgr` exposed that the on-disk sysinit
  shebang spawn path could drive the dispatcher stack within roughly one frame
  of `_stack_bottom`, causing the next seL4 extra-cap lookup to use a bogus
  stack-adjacent CPtr before sysinit ran.

Commands:

- `bash -n scripts/tm-pathmgr-runtime-smoke.sh scripts/tm-pathmgr-evidence.sh scripts/boot-smoke.sh`
- `make -n tm-pathmgr-runtime-smoke container-tm-pathmgr-runtime-smoke`
- `./scripts/apply-component-overrides.sh`
- `make tm-pathmgr-runtime-smoke`
- `make tm-pathmgr-evidence`

Result:

- The initial Rust-pathmgr boot faulted after loading
  `/usr/sbin/sysinit/level1.sh`; the 32 KiB taskman stack override fixed it.
- `make tm-pathmgr-runtime-smoke` passes locally with all runtime markers.
- `make tm-pathmgr-evidence` passes locally, including C/Rust host tests,
  provider archive audit, and NQ/LQ C-default/Rust-selected link checks.
- The runtime smoke closes the open/device-registration coverage gap that kept
  `tm_pathmgr` behind the previous next gate, but the provider remains Rust
  opt-in pending a separate Rust-default RC decision.

Follow-up:

- Publish, open the PR, wait for trusted CI, merge, and update #149.

## 2026-06-29 23:26 CEST - tm_sysfs Runtime Smoke

Scope:

- Added `make tm-sysfs-runtime-smoke` and container CI wiring.
- The smoke rebuilds QSOE/L with `QSOE_RUST_TM_SYSFS=1` and mandatory
  `QSOE_RUST_TM_PROCFS=1`.
- It verifies the Rust-selected `libtaskman.a` omits C `tm_sysfs.o`, verifies
  all six `tm_sysfs_*` ABI symbols in the shared Rust provider archive, waits
  for taskman's syscfg/sysmap markers, then runs `/bin/ls /sys` and reads all
  five portable `/sys` files from sysinit.
- Updated `tm_sysfs` status docs so the next gate is a separate Rust-default RC
  decision rather than missing focused `/sys` runtime coverage.

Commands:

- `bash -n scripts/tm-sysfs-runtime-smoke.sh scripts/tm-sysfs-evidence.sh scripts/boot-smoke.sh`
- `make -n tm-sysfs-runtime-smoke container-tm-sysfs-runtime-smoke`
- `make tm-sysfs-runtime-smoke`

Result:

- The local `make tm-sysfs-runtime-smoke` run passed.
- The smoke proves the Rust-selected `/sys` model is exercised through LQ's
  existing C open/read/readdir dispatch in a booted system.

Follow-up:

- Keep `tm_sysfs` Rust opt-in while deciding whether to open a separate
  Rust-default RC window.

## 2026-06-29 23:58 CEST - tm_sysmap Runtime Smoke

Scope:

- Added `make tm-sysmap-runtime-smoke` and container CI wiring.
- The smoke rebuilds QSOE/L with `QSOE_RUST_TM_SYSMAP=1` and mandatory
  `QSOE_RUST_TM_PROCFS=1`.
- It captures the Rust-selected LQ taskman dry-run plan, rejects any remaining
  `sys/sysmap.o` link, verifies the selected Rust provider archive exports
  `tm_sysmap_build` and `tm_sysmap_get`, waits for taskman's syscfg/sysmap boot
  markers, waits for pci-server scan completion, then runs `/usr/bin/sysinfo`
  from sysinit and checks its QEMU timebase, PLIC, and PCI output.
- Updated `tm_sysmap` status docs so the next gate is a separate Rust-default
  RC decision rather than missing basic spawned-child `PSYS` page coverage.

Commands:

- `bash -n scripts/tm-sysmap-runtime-smoke.sh scripts/tm-sysmap-evidence.sh scripts/boot-smoke.sh`
- `make -n tm-sysmap-runtime-smoke container-tm-sysmap-runtime-smoke`
- `make tm-sysmap-runtime-smoke`

Result:

- The local `make tm-sysmap-runtime-smoke` run passed.
- The smoke proves the Rust-selected sysmap builder is exercised through a
  booted child process consuming the mapped `PSYS` page.

Follow-up:

- Keep `tm_sysmap` Rust opt-in while deciding whether to open a separate
  Rust-default RC window.

## 2026-06-29 23:45 CEST - tm_fdt Runtime Smoke

Scope:

- Added `make tm-fdt-runtime-smoke` and container CI wiring.
- The smoke rebuilds QSOE/L with `QSOE_RUST_TM_FDT=1` and mandatory
  `QSOE_RUST_TM_PROCFS=1`.
- It captures the Rust-selected LQ taskman dry-run plan, rejects any remaining
  `sys/fdt.o` link, verifies the selected Rust provider archive exports all
  nine `tm_fdt_*` ABI symbols, waits for `/chosen` command-line,
  `syscfg built from FDT`, and `sysmap page built` boot markers, then checks
  `/sys/board`, `/sys/cmdline`, and `/usr/bin/sysinfo` from sysinit.
- Updated `tm_fdt` status docs so the next gate is a separate Rust-default RC
  decision rather than missing basic boot/syscfg runtime coverage.

Commands:

- `bash -n scripts/tm-fdt-runtime-smoke.sh scripts/tm-fdt-evidence.sh scripts/boot-smoke.sh`
- `make -n tm-fdt-runtime-smoke container-tm-fdt-runtime-smoke`
- `make tm-fdt-runtime-smoke`

Result:

- The local `make tm-fdt-runtime-smoke` run passed.
- The smoke proves the Rust-selected FDT parser is exercised through the LQ
  `/chosen`, syscfg/sysmap, `/sys`, and `sysinfo` boot-consumer path.

Follow-up:

- Keep `tm_fdt` Rust opt-in while deciding whether to open a separate
  Rust-default RC window. Broader PCI and memory-topology risk still needs
  explicit acceptance before any C removal.

## 2026-06-29 23:20 CEST - tm_syscfg Runtime Smoke

Scope:

- Added `make tm-syscfg-runtime-smoke` and container CI wiring.
- The smoke rebuilds QSOE/L with `QSOE_RUST_TM_SYSCFG=1` and mandatory
  `QSOE_RUST_TM_PROCFS=1`.
- It verifies the selected `libtaskman.a` omits C `syscfg.o`, verifies the
  selected Rust provider archive exports `tm_syscfg_init`, waits for taskman's
  `syscfg built from FDT` and `sysmap page built` boot markers, then checks
  `/sys/board`, `/sys/cmdline`, and `/usr/bin/sysinfo` from sysinit.
- Updated `tm_syscfg` status docs so the next gate is a separate Rust-default
  RC decision that accepts the LQ private-runtime-syscfg boundary.

Commands:

- `bash -n scripts/tm-syscfg-runtime-smoke.sh scripts/tm-syscfg-evidence.sh scripts/boot-smoke.sh`
- `make -n tm-syscfg-runtime-smoke container-tm-syscfg-runtime-smoke`
- `make tm-syscfg-runtime-smoke`

Result:

- The local `make tm-syscfg-runtime-smoke` run passed.
- The smoke proves a Rust-selected portable `tm_syscfg` taskman build still
  boots and serves syscfg-backed consumers. LQ's private FDT-backed runtime
  syscfg builder remains C by design.

Follow-up:

- Keep `tm_syscfg` Rust opt-in while deciding whether to open a separate
  Rust-default RC window with that boundary accepted.

## 2026-06-29 22:55 CEST - tm_elf Runtime Smoke

Scope:

- Added `make tm-elf-runtime-smoke` and container CI wiring.
- The smoke rebuilds QSOE/L with `QSOE_RUST_TM_ELF=1` and mandatory
  `QSOE_RUST_TM_PROCFS=1`.
- It injects a temporary sysinit fragment that runs `/usr/bin/sysinfo`,
  verifies the staged `sysinfo` binary is a dynamic ELF, and waits for a
  successful dynamic-spawn marker.
- Updated `tm_elf` status docs so the next gate is a separate Rust-default RC
  decision rather than missing basic loader/runtime coverage.

Commands:

- `bash -n scripts/tm-elf-runtime-smoke.sh scripts/tm-elf-evidence.sh scripts/boot-smoke.sh`
- `make -n tm-elf-runtime-smoke container-tm-elf-runtime-smoke`
- `make tm-elf-runtime-smoke`

Result:

- The local `make tm-elf-runtime-smoke` run passed.
- The smoke proves the Rust-selected ELF parser is exercised through dynamic
  `/usr/bin/sysinfo` spawn while segment mapping, dynamic linker admission,
  relocation, process tables, and seL4 invocation code remain C.

Follow-up:

- Keep `tm_elf` Rust opt-in while deciding whether to open a separate
  Rust-default RC window.

## 2026-06-29 22:40 CEST - tm_script Runtime Smoke

Scope:

- Added `make tm-script-runtime-smoke` and container CI wiring.
- The smoke rebuilds QSOE/L with `QSOE_RUST_TM_SCRIPT=1` and mandatory
  `QSOE_RUST_TM_PROCFS=1`.
- It stages a temporary executable `/usr/bin/tm_script_probe` shell script into
  the virtio qrvfs image, injects a sysinit fragment that invokes the probe by
  path, and waits for the probe marker and clean-exit marker.
- Updated `tm_script` status docs so the next gate is a separate Rust-default
  RC decision rather than missing basic runtime coverage.

Commands:

- `bash -n scripts/tm-script-runtime-smoke.sh scripts/tm-script-evidence.sh scripts/boot-smoke.sh`
- `make -n tm-script-runtime-smoke container-tm-script-runtime-smoke`
- `make tm-script-runtime-smoke`

Result:

- The local `make tm-script-runtime-smoke` run passed.
- The smoke proves the Rust-selected shebang parser is exercised through direct
  script spawn, not by sourcing a sysinit fragment in the current shell.

Follow-up:

- Keep `tm_script` Rust opt-in while deciding whether to open a separate
  Rust-default RC window.

## 2026-06-29 22:20 CEST - tm_cpio Runtime Smoke

Scope:

- Added `make tm-cpio-runtime-smoke` and container CI wiring.
- The smoke rebuilds QSOE/L with `QSOE_RUST_TM_CPIO=1` and mandatory
  `QSOE_RUST_TM_PROCFS=1`.
- It injects a temporary sysinit fragment that exercises CPIO-root symlink
  readlink output, `/etc/passwd` through the `/etc` CPIO symlink, direct
  `/sbin/init` reads from the boot CPIO, and `/bin/sh` symlink spawn.
- Updated `tm_cpio` status docs so the next gate is a separate Rust-default RC
  decision rather than missing basic runtime coverage.

Commands:

- `bash -n scripts/tm-cpio-runtime-smoke.sh scripts/tm-cpio-evidence.sh scripts/procfs-smoke.sh`
- `make -n tm-cpio-runtime-smoke`
- `make -n container-tm-cpio-runtime-smoke`
- `make tm-cpio-runtime-smoke`

Result:

- The first local run reached every behavior marker but expected symlink text
  without leading slashes; the harness now matches QSOE's
  `etc -> /usr/conf` and `home -> /usr/home` output.
- The corrected local `make tm-cpio-runtime-smoke` run passed.

Follow-up:

- Keep `tm_cpio` Rust opt-in while deciding whether to open a separate
  Rust-default RC window.

## 2026-06-29 22:05 CEST - Retired C tm_procfs Provider

Scope:

- Retired the C `libtaskman/src/tm_procfs.c` provider after the Rust-default RC
  path and shared-provider archive prerequisite.
- Made `QSOE_RUST_TM_PROCFS=1` mandatory in root, NQ, LQ, libtaskman, and the
  shared Rust provider builder.
- Added component override patches that make fresh NQ/LQ checkouts reject
  `QSOE_RUST_TM_PROCFS=0`.
- Reworked `tm-procfs-evidence` for Rust-only membership, retired selector
  rejection, and `/proc` smoke validation.
- Removed the top-level `tm-procfs-rc-rollback-smoke` and container rollback
  targets; direct `TM_PROCFS_RC_ROLLBACK=1` script use fails fast.
- Updated status, inventory, retirement, task-manager, and provider docs.

Commands:

- `scripts/c-index.sh files`
- `bash -n scripts/build-rust-tm-providers.sh scripts/check-tm-procfs-model.sh scripts/procfs-smoke.sh scripts/tm-procfs-evidence.sh scripts/tm-procfs-rc-smoke.sh scripts/apply-component-overrides.sh`
- `./scripts/apply-component-overrides.sh`
- `QSOE_RUST_TM_PROCFS=0 scripts/build-rust-tm-providers.sh`
- `TM_PROCFS_RC_ROLLBACK=1 scripts/tm-procfs-rc-smoke.sh`
- `make check-tm-procfs-model`
- `make rust-tm-procfs-provider`
- `make tm-procfs-evidence`
- `make tm-providers-evidence`
- `make tm-fdt-evidence`
- `make rust-check`

Result:

- `tm_procfs` is now the first retired task-manager Rust provider.
- The public `tm_procfs.h` ABI remains for taskman C glue, but the provider
  implementation is Rust-only.
- Normal taskman builds link `qsoe-tm-procfs` through the shared
  `qsoe-tm-providers` archive; `QSOE_RUST_TM_PROCFS=0` is rejected.

Follow-up:

- Merge the retirement PR, then update #141 to `status:retired`.

## 2026-06-29 21:08 CEST - Shared Taskman Rust Provider Archive

Scope:

- Added `qsoe-tm-providers`, a no-std staticlib wrapper that packages selected
  task-manager Rust providers behind one panic handler.
- Changed individual `qsoe-tm-*` provider crates to build as `rlib` provider
  crates instead of independent staticlibs with their own panic handlers.
- Added `scripts/build-rust-tm-providers.sh` and kept legacy
  `rust-tm-*-provider` targets delegating to it for focused evidence.
- Updated NQ/LQ taskman link plumbing and tracked component overrides so any
  enabled `QSOE_RUST_TM_*` selector links one shared provider archive.
- Added `make tm-providers-evidence`, selecting `tm_cpio + tm_procfs` together.
- Updated roadmap, status, task-manager, and handover docs for the shared
  archive model.

Commands:

- `cargo check --manifest-path rust/Cargo.toml -p qsoe-tm-providers --no-default-features --features "tm-cpio tm-procfs"`
- `QSOE_RUST_TM_CPIO=1 QSOE_RUST_TM_PROCFS=1 scripts/build-rust-tm-providers.sh`
- `make -C nq/taskman --no-print-directory QSOE_RUST_TM_PROCFS=1 QSOE_RUST_TM_CPIO=1`
- `make -C lq --no-print-directory QSOE_RUST_TM_PROCFS=1 QSOE_RUST_TM_CPIO=1 taskman`
- `./scripts/apply-component-overrides.sh`
- `bash -n scripts/build-rust-tm-providers.sh scripts/build-rust-tm-cpio-provider.sh scripts/build-rust-tm-cred-provider.sh scripts/build-rust-tm-elf-provider.sh scripts/build-rust-tm-fdt-provider.sh scripts/build-rust-tm-pathmgr-provider.sh scripts/build-rust-tm-procfs-provider.sh scripts/build-rust-tm-pseudodev-provider.sh scripts/build-rust-tm-rsrcdb-provider.sh scripts/build-rust-tm-script-provider.sh scripts/build-rust-tm-syscfg-provider.sh scripts/build-rust-tm-sysfs-provider.sh scripts/build-rust-tm-sysmap-provider.sh scripts/apply-component-overrides.sh scripts/rust-check.sh scripts/tm-providers-evidence.sh`
- `make rust-tm-procfs-provider`
- `make rust-tm-cpio-provider`
- `QSOE_RUST_TM_CPIO=1 QSOE_RUST_TM_PROCFS=1 make rust-tm-providers`
- `make rust-check`
- `make tm-providers-evidence`
- `git diff --check`
- `patch -d nq --reverse --silent --dry-run -p1 < patches/components/nq-taskman-rust-tm-shared-providers.patch`
- `patch -d lq --reverse --silent --dry-run -p1 < patches/components/lq-makefile-rust-tm-shared-providers.patch`
- `patch -d lq --reverse --silent --dry-run -p1 < patches/components/lq-taskman-rust-tm-shared-providers.patch`

Result:

- A single shared archive can package multiple selected taskman Rust providers
  without duplicate panic-handler symbols.
- Legacy single-provider build targets still work and preserve historical
  output paths for focused evidence scripts.
- NQ and LQ taskman link successfully with both `tm_cpio` and `tm_procfs`
  selected.
- The shared archive exports the expected `tm_cpio_*`, `tm_procfs_*`, and
  `qsoe_tm_providers_archive_anchor` symbols and has only one
  `rust_begin_unwind` symbol.
- `make tm-providers-evidence` verified selected C objects are absent from
  NQ/LQ `libtaskman.a`, final taskman ELFs pass soft-float/no-TLS/no-unwind
  audits, and the dual-provider `/proc` smoke reaches the expected milestones.
- `make rust-check`, shell syntax checks, whitespace checks, and component
  patch reverse dry-runs pass.

Follow-up:

- Merge the shared archive PR, then update #179 to `status:complete`.
- Resume #141 `tm_procfs` retirement work only after the #26 checklist is
  satisfied for that C removal.

## 2026-06-29 20:01 CEST - Retired C devb-virtio Driver

Scope:

- Retired the C `quser/dev/virtio` block driver after the Rust-default
  `devb-virtio-rs` RC and rollback evidence.
- Changed `QSOE_RUST_VIRTIO` to default to Rust and reject `0` because the C
  driver is no longer staged.
- Removed the `virtio-rc-rollback-smoke` and container rollback targets.
- Added tracked NQ/LQ component patches so fresh CPIO builds call top-level
  `make virtio-artifact` and pass `SBIN_VIRTIO_ELF` into `quser`.
- Removed the C `devb-virtio` source from the `quser` component override.
- Removed the retired C `devb-virtio` ELF from the `qsoe-elf` relocation
  fixture list.
- Updated README/status/inventory/retirement docs and added
  `VIRTIO_RETIREMENT.md`.

Commands:

- `./scripts/apply-component-overrides.sh`
- `patch -d nq --reverse --silent --dry-run -p1 < patches/components/nq-makefile-rust-virtio-retired.patch`
- `patch -d lq --reverse --silent --dry-run -p1 < patches/components/lq-makefile-rust-virtio-retired.patch`
- `patch -d quser --reverse --silent --dry-run -p1 < patches/components/quser-retire-virtio-c.patch`
- `bash -n scripts/apply-component-overrides.sh scripts/select-virtio-artifact.sh scripts/rust-virtio-boot-smoke.sh scripts/rust-virtio-file-smoke.sh scripts/virtio-rc-file-smoke.sh scripts/boot-smoke.sh scripts/rust-mkfs-qrv-live-smoke.sh scripts/mkfs-qrv-rc-live-smoke.sh scripts/rust-slogger-boot-smoke.sh scripts/rust-pipe-smoke.sh scripts/rust-pipe-data-smoke.sh scripts/capture-elf-baseline.sh`
- `QSOE_RUST_VIRTIO=0 make virtio-artifact`
- `QSOE_VIRTIO_RC_ROLLBACK=1 scripts/virtio-rc-file-smoke.sh`
- `make rust-virtio-link-smoke`
- `make check-elf-reloc-fixture`
- `make virtio-artifact`
- `make rust-check`
- `make slogger-artifact pipe-artifact virtio-artifact && make -C quser cpio`
- `make rust-virtio-file-smoke`
- `make virtio-rc-file-smoke`
- `make mkfs-qrv-rc-live-smoke`
- `make mkfs-qrv-rc-rollback-smoke`
- `make rust-pipe-data-smoke`
- `make`
- `scripts/boot-smoke.sh -k lq -t 120`
- `make rust-slogger-boot-smoke`
- `make rust-pipe-smoke`
- `scripts/c-index.sh files`

Result:

- Component overrides replayed idempotently and verified
  `quser/dev/virtio` is absent.
- The retired C selector and rollback flags fail fast with status 2 and clear
  retirement messages.
- `qsoe-devb-virtio-rs` links and passes strict user ELF audit with no TLS or
  unwind sections.
- The required relocation fixture test no longer reads the retired C
  `quser/build/dev/virtio/devb-virtio.elf` path.
- Direct `quser` CPIO packaging succeeds when the selected Rust `slogger`,
  `pipe`, and `devb-virtio` artifacts are present.
- CPIO inspection confirms `/sbin/devb-virtio` contains the Rust
  `[devb-virtio-rs] /dev/vblk0 ready` marker.
- The Rust-only virtio file-read smoke and compatibility RC smoke both pass.
- Rust mkfs live smoke, C mkfs rollback live smoke, Rust pipe data smoke,
  focused slogger/pipe smokes, normal source build, and QSOE/L boot smoke all
  pass with Rust `devb-virtio-rs` staged as `/sbin/devb-virtio`.
- The C inventory now reports 810 indexed files and 130,214 approximate LOC;
  `quser` dropped to 121 indexed files after removing C `devb-virtio`.

Follow-up:

- Merge the retirement PR, then update #138 to `status:retired` and close it.
- Continue with the next candidate only after its own evidence and removal PR.

## 2026-06-29 19:27 CEST - Retired C pipe Service

Scope:

- Retired the C `quser/sbin/pipe` service after the Rust-default
  `pipe-rs` RC and rollback evidence.
- Changed `QSOE_RUST_PIPE` to default to Rust and reject `0` because the C
  service is no longer staged.
- Removed the `pipe-rc-rollback-smoke` and container rollback targets.
- Added tracked NQ/LQ component patches so fresh CPIO builds call top-level
  `make pipe-artifact` and pass `SBIN_PIPE_ELF` into `quser`.
- Removed the C `pipe` source from the `quser` component override.
- Updated README/status/inventory/retirement docs and added
  `PIPE_RETIREMENT.md`.

Commands:

- `./scripts/apply-component-overrides.sh`
- `patch -d nq --reverse --silent --dry-run -p1 < patches/components/nq-makefile-rust-pipe-retired.patch`
- `patch -d lq --reverse --silent --dry-run -p1 < patches/components/lq-makefile-rust-pipe-retired.patch`
- `patch -d quser --reverse --silent --dry-run -p1 < patches/components/quser-retire-pipe-c.patch`
- `bash -n scripts/apply-component-overrides.sh scripts/select-pipe-artifact.sh scripts/rust-pipe-smoke.sh scripts/rust-pipe-data-smoke.sh scripts/pipe-rc-data-smoke.sh scripts/pipe-smoke.sh`
- `QSOE_RUST_PIPE=0 make pipe-artifact`
- `QSOE_PIPE_RC_ROLLBACK=1 scripts/pipe-rc-data-smoke.sh`
- `make rust-pipe-link-smoke`
- `make pipe-artifact`
- `make rust-check`
- `make slogger-artifact pipe-artifact && make -C quser cpio`
- `make rust-pipe-data-smoke`
- `make pipe-rc-data-smoke`
- `make pipe-smoke`
- `make`
- `scripts/boot-smoke.sh -k lq -t 120`
- `scripts/c-index.sh files`

Result:

- Component overrides replayed idempotently and verified `quser/sbin/pipe`
  is absent.
- The retired C selector and rollback flags fail fast with status 2 and clear
  retirement messages.
- `qsoe-pipe-rs` links and passes strict user ELF audit with no TLS or unwind
  sections.
- `make rust-check` passed for formatting, check, clippy, and host tests.
- Direct `quser` CPIO packaging succeeds when the selected Rust `slogger` and
  `pipe` artifacts are present.
- The Rust-only pipe data-path smoke passes and observes `/dev/pipe`
  registration, libc `pipe(2)` round trip, EOF behavior, and helper exit.
- The compatibility `pipe-rc-data-smoke` wrapper now exercises the Rust-only
  service path and passes.
- Normal source build, normal QSOE/L boot smoke, and focused `pipe-smoke`
  stage Rust `pipe-rs` as `/sbin/pipe` and reach the expected milestones.
- The C inventory now reports 813 indexed files and 130,795 approximate LOC;
  `quser` dropped to 124 indexed files after removing C `pipe`.

Follow-up:

- Merge the retirement PR, then update #139 to `status:retired` and close it.
- Continue with the next production-service candidate only after its own RC
  evidence and removal PR.

## 2026-06-29 18:45 CEST - Retired C slogger Service

Scope:

- Retired the C `quser/sbin/slogger` service after the `slogger-rs`
  Rust-default RC and rollback evidence.
- Changed `QSOE_RUST_SLOGGER` to default to Rust and reject `0` because the C
  service is no longer staged.
- Removed the `slogger-rc-rollback-smoke` and container rollback targets.
- Added tracked component patches so fresh NQ/LQ CPIO builds call top-level
  `make slogger-artifact` and pass `SBIN_SLOG_ELF` into `quser`.
- Removed the C `slogger` source from the `quser` component override.
- Removed the C `slogger` ELF from the default C baseline and Rust relocation
  fixture list.
- Updated README/status/inventory/retirement docs and added
  `SLOGGER_RETIREMENT.md`.

Commands:

- `./scripts/apply-component-overrides.sh`
- `bash -n scripts/apply-component-overrides.sh scripts/select-slogger-artifact.sh scripts/rust-slogger-boot-smoke.sh scripts/slogger-rc-boot-smoke.sh scripts/capture-elf-baseline.sh`
- `python3 -m py_compile scripts/slog-readback-smoke.py`
- `QSOE_RUST_SLOGGER=0 make slogger-artifact`
- `QSOE_SLOGGER_RC_ROLLBACK=1 scripts/slogger-rc-boot-smoke.sh --prepare-only`
- `make rust-slogger-link-smoke`
- `make slogger-artifact`
- `make rust-check`
- `make -C quser cpio`
- `make slogger-rc-readback-smoke`
- `make`
- `scripts/boot-smoke.sh -k lq -t 120`
- `scripts/c-index.sh files`

Result:

- Component overrides replayed idempotently and verified `quser/sbin/slogger`
  is absent.
- The retired C selector and rollback flags fail fast with status 2 and clear
  retirement messages.
- `qsoe-slogger-rs` links and passes strict user ELF audit with no TLS or
  unwind sections.
- `make rust-check` passed for formatting, check, clippy, and host tests.
- The Rust-only `/dev/slog` readback smoke passes and observes a boot-time
  `pci-server:` entry through `/bin/sloginfo`.
- Normal source build and default QSOE/L boot smoke now stage Rust
  `slogger-rs` as `/sbin/slogger` and reach login.
- Direct `quser` CPIO packaging succeeds when the selected Rust `slogger`
  artifact is present.
- The C inventory now reports 814 indexed files and 131,180 approximate LOC;
  `quser` dropped to 125 indexed files after removing C `slogger`.

Follow-up:

- Merge the retirement PR, then update #137 to `status:retired` and close it.
- Keep future production-service retirements separate and require their own RC
  evidence plus removal PRs.

## 2026-06-29 18:06 CEST - Retired C test_msgpass Helper

Scope:

- Retired the C `quser/test/msgpass` helper after the Rust-default
  `test_msgpass-rs` RC and rollback evidence.
- Changed the umbrella qrvfs test-image path to stage Rust
  `test_msgpass-rs` at `/usr/bin/test_msgpass`.
- Removed the C rollback Make targets and made `QSOE_RUST_TEST_MSGPASS=0` plus
  `QSOE_TEST_MSGPASS_RC_ROLLBACK=1` fail fast.
- Added `quser-retire-test-msgpass-c.patch` so fresh `make prepare` removes the
  C helper component source and nested Makefile.
- Removed the retired C helper from the default C ELF baseline and qsoe-elf
  relocation fixture list.
- Dropped the Rust helper's self-`ProcessTerminate` dependency in the
  no-reply branch; the suite owns QSOE/L process termination before the
  blocking no-reply send.
- Updated README/status/inventory/retirement docs and added
  `TEST_MSGPASS_RETIREMENT.md`.

Commands:

- `bash -n scripts/apply-component-overrides.sh scripts/select-test-msgpass-artifact.sh scripts/rust-test-msgpass-smoke.sh scripts/test-msgpass-rc-smoke.sh scripts/rust-pipe-data-smoke.sh scripts/capture-elf-baseline.sh`
- `./scripts/apply-component-overrides.sh`
- `QSOE_RUST_TEST_MSGPASS=0 make test-msgpass-artifact`
- `QSOE_TEST_MSGPASS_RC_ROLLBACK=1 scripts/test-msgpass-rc-smoke.sh`
- `make rust-test-msgpass-link-smoke`
- `make test-msgpass-artifact`
- `make rust-test-msgpass-smoke`
- `make test-msgpass-rc-smoke`
- `make rust-check`
- `make check-qrvfs-rust-writer-production-root`
- `make rust-pipe-data-smoke`

Result:

- Component overrides replayed idempotently and verified `quser/test/msgpass`
  is absent.
- The retired C selector and rollback flags fail fast with status 2 and clear
  retirement messages.
- `qsoe-test-msgpass-rs` links and passes strict user ELF audit with no TLS or
  unwind sections.
- The Rust-only `[msgpass]` suite smoke passes, including resolve, 4 MiB minus
  2 byte round trip, halfword swap, clean server exit, and the QSOE/L
  no-reply skip marker.
- The qrvfs production-root writer comparison still includes
  `/usr/bin/test_msgpass`.
- `rust-pipe-data-smoke` still passes with the selected Rust helper in the
  qrvfs image.

Follow-up:

- Use this as the first #26 retirement checklist exercise. Keep production
  service retirements separate and require their own RC evidence plus removal
  PRs.

## 2026-06-29 CEST - tm_pathmgr Rust Opt-In Provider

Scope:

- Added `qsoe-tm-pathmgr`, a no-std Rust staticlib exporting the existing
  portable taskman `tm_pathmgr_*` ABI.
- Added `QSOE_RUST_TM_PATHMGR=1` selection for NQ/LQ taskman. The selector
  omits C `pathmgr.o` from `libtaskman.a`, then links
  `build/rust/tm-pathmgr/libqsoe_tm_pathmgr.a`.
- Added a C host-model fixture, Rust host tests, provider build script,
  evidence script, tracked NQ/LQ component patches, CI evidence step, and docs.
- Preserved the C provider's fixed node pool, longest-prefix lookup, PMDIR
  remainder rejection, one-hop symlink behavior, external-only unregister, and
  newest-first child enumeration.
- Kept C as the normal default and rollback implementation.

Commands:

- `make check-tm-pathmgr-model`
- `cargo test --manifest-path rust/Cargo.toml -p qsoe-tm-pathmgr --features host-tests --lib`
- `cargo clippy --manifest-path rust/Cargo.toml -p qsoe-tm-pathmgr --features host-tests -- -D warnings`
- `bash -n scripts/check-tm-pathmgr-model.sh scripts/build-rust-tm-pathmgr-provider.sh scripts/tm-pathmgr-evidence.sh scripts/apply-component-overrides.sh`
- `./scripts/apply-component-overrides.sh`
- `make rust-tm-pathmgr-provider`
- `make tm-pathmgr-evidence`
- `make container-tm-pathmgr-evidence`

Result:

- The focused C fixture and Rust host tests pass for registration, longest
  prefix resolution, PMDIR misses, repath, external-only unregister, symlink
  resolution and expansion, CPIO symlink expansion, and child enumeration.
- The soft-float Rust provider archive builds for
  `riscv64imac-unknown-none-elf`.
- The provider archive exports all nine `tm_pathmgr_*` ABI symbols and all
  archive members report RVC soft-float ABI.
- NQ and LQ C-default taskman archives include one `pathmgr.o` member.
  Rust-selected archives include zero `pathmgr.o` members and link
  `libqsoe_tm_pathmgr.a`.
- The final NQ and LQ taskman ELFs link in both modes and pass the evidence
  script's ELF flag and section audit.
- The container-equivalent `tm_pathmgr` evidence target passes with the same
  C-default/Rust-selected archive membership and link evidence.

Follow-up:

- Keep `tm_pathmgr` Rust opt-in only until open/device-registration runtime
  coverage exists before any Rust-default RC decision.

## 2026-06-29 CEST - tm_sysmap Rust Opt-In Provider

Scope:

- Added `qsoe-tm-sysmap`, a no-std Rust staticlib exporting the existing LQ
  taskman `tm_sysmap_*` ABI.
- Added `QSOE_RUST_TM_SYSMAP=1` selection for LQ taskman. The selector omits C
  `sys/sysmap.o`, then links `build/rust/tm-sysmap/libqsoe_tm_sysmap.a`.
- Added a C host-model fixture, Rust host tests, provider build script,
  evidence script, tracked LQ component patches, CI evidence step, and docs.
- Preserved the current C builder behavior for the 4 KiB `PSYS` page,
  including header patching, END emission, 8-byte TLV padding, MTIME, PLIC,
  PCI ECAM, PCI MEM window, and DesignWare MSI fields.
- Kept C as the normal default and rollback implementation.

Commands:

- `make check-tm-sysmap-model`
- `cargo test --manifest-path rust/Cargo.toml -p qsoe-tm-sysmap --features host-tests --lib`
- `cargo clippy --manifest-path rust/Cargo.toml -p qsoe-tm-sysmap --features host-tests -- -D warnings`
- `bash -n scripts/check-tm-sysmap-model.sh scripts/build-rust-tm-sysmap-provider.sh scripts/tm-sysmap-evidence.sh scripts/apply-component-overrides.sh scripts/rust-check.sh scripts/rust-workflow.sh`
- `./scripts/apply-component-overrides.sh`
- `make -n check-tm-sysmap-model rust-tm-sysmap-provider tm-sysmap-evidence container-rust-tm-sysmap-provider container-tm-sysmap-evidence`
- `make rust-tm-sysmap-provider`
- `make tm-sysmap-evidence`

Result:

- The C host fixture and Rust host tests pass for get-before-build, minimal
  syscfg, and full MTIME/PLIC/PCI/DesignWare syscfg cases.
- The provider archive exports `tm_sysmap_build` and `tm_sysmap_get`, and all
  archive members report RVC soft-float ABI.
- LQ C-default taskman links with C `sys/sysmap.o`; LQ Rust-selected taskman
  omits that object and links `libqsoe_tm_sysmap.a`.
- The final LQ taskman ELF links in both modes and passes the evidence script's
  ELF flag and section audit.

Follow-up:

- Later `make tm-sysmap-runtime-smoke` added focused spawned-child `PSYS` page
  coverage through `sysinfo` timebase, PLIC, and PCI output. Keep `tm_sysmap`
  Rust opt-in pending a separate RC decision.

## 2026-06-29 15:39 CEST - tm_fdt Rust Opt-In Provider

Scope:

- Added `qsoe-tm-fdt`, a no-std Rust staticlib exporting the existing LQ
  taskman `tm_fdt_*` ABI.
- Added `QSOE_RUST_TM_FDT=1` selection for LQ taskman. The selector omits C
  `sys/fdt.o`, then links `build/rust/tm-fdt/libqsoe_tm_fdt.a`.
- Added a C host-model fixture, Rust host tests, provider build script,
  evidence script, tracked LQ component patches, CI evidence step, and docs.
- Preserved the current C parser behavior for minimal big-endian FDT walking:
  header validation, NOP-root skipping, `name@unit` path matching, raw and
  typed property reads, compatible string lists, and `reg` tuple decoding.
- Kept C as the normal default and rollback implementation.

Commands:

- `make check-tm-fdt-model`
- `cargo test --manifest-path rust/Cargo.toml -p qsoe-tm-fdt --features host-tests --lib`
- `cargo clippy --manifest-path rust/Cargo.toml -p qsoe-tm-fdt --features host-tests -- -D warnings`
- `bash -n scripts/check-tm-fdt-model.sh scripts/build-rust-tm-fdt-provider.sh scripts/tm-fdt-evidence.sh scripts/apply-component-overrides.sh scripts/rust-check.sh scripts/rust-workflow.sh`
- `./scripts/apply-component-overrides.sh`
- `make -n check-tm-fdt-model rust-tm-fdt-provider tm-fdt-evidence container-rust-tm-fdt-provider container-tm-fdt-evidence`
- `make rust-tm-fdt-provider`
- `make tm-fdt-evidence`
- `make check-host-tools`
- `make rust-check`
- `make container-tm-fdt-evidence`

Result:

- The C host fixture and Rust host tests pass for header validation, total-size
  reporting, path lookup, string/u32/raw properties, compatible lookup,
  malformed string rejection, and `reg` tuple decoding.
- The provider archive exports all nine `tm_fdt_*` symbols and all archive
  members report RVC soft-float ABI.
- LQ C-default taskman links with C `sys/fdt.o`; LQ Rust-selected taskman
  omits that object and links `libqsoe_tm_fdt.a`.
- The final LQ taskman ELF links in both modes and passes the evidence script's
  ELF flag and section audit.
- The container-equivalent `tm_fdt` evidence target passes and captures the
  same C-default/Rust-selected link evidence.

Follow-up:

- Later `make tm-fdt-runtime-smoke` added focused `/chosen`, syscfg/sysmap,
  `/sys`, and `sysinfo` boot-consumer coverage. Keep `tm_fdt` Rust opt-in
  pending a separate RC decision, with broader PCI and memory-topology risk
  still called out explicitly.

## 2026-06-29 15:05 CEST - tm_elf Rust Opt-In Provider

Scope:

- Added `qsoe-tm-elf`, a no-std Rust staticlib exporting the existing portable
  `tm_elf_parse` ABI.
- Added `QSOE_RUST_TM_ELF=1` selection for NQ and LQ taskman. The selector
  omits C `elf.o` from `libtaskman.a`, then links
  `build/rust/tm-elf/libqsoe_tm_elf.a`.
- Added a C host-model fixture, Rust host tests, provider build script,
  evidence script, tracked NQ/LQ component patches, CI evidence step, and docs.
- Preserved the current C parser behavior for ELF64 little-endian RISC-V
  images, including zero-file-size load offsets, interpreter pointers into the
  caller-owned blob, fixed 8-entry load capture, and wrapping virtual-end
  arithmetic.
- Kept C as the normal default and rollback implementation.

Commands:

- `make check-tm-elf-model`
- `cargo test --manifest-path rust/Cargo.toml -p qsoe-tm-elf --features host-tests --lib`
- `cargo clippy --manifest-path rust/Cargo.toml -p qsoe-tm-elf --features host-tests -- -D warnings`
- `bash -n scripts/check-tm-elf-model.sh scripts/build-rust-tm-elf-provider.sh scripts/tm-elf-evidence.sh scripts/apply-component-overrides.sh`
- `./scripts/apply-component-overrides.sh`
- `make -n check-tm-elf-model rust-tm-elf-provider tm-elf-evidence container-rust-tm-elf-provider container-tm-elf-evidence`
- Clean throwaway checkout `make prepare` plus idempotent
  `./scripts/apply-component-overrides.sh` with the new component files copied
  in.
- `make rust-tm-elf-provider`
- `make tm-elf-evidence`
- `make container-tm-elf-evidence`

Result:

- The first clean patch replay caught malformed LQ top-level and LQ
  `taskman/Makefile` component-patch hunks. Those hunks were regenerated and
  the clean replay now passes.
- The C host fixture and Rust host tests pass for ABI layout, normal ELF parse,
  interpreter validation, malformed headers, too many `PT_LOAD` entries,
  zero-file-size load behavior, and wrapped segment-end rejection.
- The provider archive exports `tm_elf_parse` and all archive members report
  RVC soft-float ABI.
- NQ and LQ C-default taskman archives include one `elf.o` member.
  Rust-selected archives include zero `elf.o` members and link
  `libqsoe_tm_elf.a`.
- The container-equivalent `tm_elf` evidence target passes and captures the
  same C-default/Rust-selected archive and linked-taskman evidence.

Follow-up:

- Later `make tm-elf-runtime-smoke` added focused dynamic ELF spawn coverage.
  Keep `tm_elf` Rust opt-in while deciding whether to open a separate
  Rust-default RC window.

## 2026-06-29 CEST - tm_rsrcdb Rust Opt-In Provider

Scope:

- Added `qsoe-tm-rsrcdb`, a no-std Rust staticlib exporting the existing LQ
  taskman `tm_rsrc_*` ABI.
- Added `QSOE_RUST_TM_RSRCDB=1` selection for LQ taskman. The selector omits C
  `sys/rsrcdb.o`, then links
  `build/rust/tm-rsrcdb/libqsoe_tm_rsrcdb.a`.
- Added a C host-model fixture, Rust host tests, provider build script,
  evidence script, tracked LQ component patches, CI evidence step, and docs.
- Preserved fixed-pool accounting, sorted per-class ranges, create/destroy,
  attach splitting and rollback, detach merging, query count/list modes,
  process-exit release, and syscfg memory seeding.
- Kept C as the normal default and rollback implementation.

Commands:

- `make check-tm-rsrcdb-model`
- `cargo test --manifest-path rust/Cargo.toml -p qsoe-tm-rsrcdb --features host-tests --lib`
- `cargo clippy --manifest-path rust/Cargo.toml -p qsoe-tm-rsrcdb --features host-tests -- -D warnings`
- `bash -n scripts/check-tm-rsrcdb-model.sh scripts/build-rust-tm-rsrcdb-provider.sh scripts/tm-rsrcdb-evidence.sh scripts/apply-component-overrides.sh`
- `./scripts/apply-component-overrides.sh`
- `make -n check-tm-rsrcdb-model rust-tm-rsrcdb-provider tm-rsrcdb-evidence container-rust-tm-rsrcdb-provider container-tm-rsrcdb-evidence`
- `make check-tm-rsrcdb-model`
- `make rust-tm-rsrcdb-provider`
- `make tm-rsrcdb-evidence`

Result:

- The C host fixture and Rust host tests pass for layout, create, attach,
  rollback, detach, merge, query count/list, release-by-pid, syscfg seeding,
  and error paths.
- The provider archive exports all `tm_rsrc_*` symbols and all archive members
  report RVC soft-float ABI.
- LQ C-default taskman links with C `sys/rsrcdb.o`; LQ Rust-selected taskman
  omits that object and links `libqsoe_tm_rsrcdb.a`.

Follow-up:

- Keep `tm_rsrcdb` Rust opt-in only until runtime coverage proves
  `rsrcdbmgr_*` create/attach/query/detach behavior before any Rust-default RC
  decision.

## 2026-06-29 13:25 CEST - tm_syscfg Rust Opt-In Provider

Scope:

- Added `qsoe-tm-syscfg`, a no-std Rust staticlib exporting the existing
  portable `tm_syscfg.h` ABI.
- Added `QSOE_RUST_TM_SYSCFG=1` selection for NQ and LQ taskman. The selector
  omits C `syscfg.o` from `libtaskman.a`, then links
  `build/rust/tm-syscfg/libqsoe_tm_syscfg.a`.
- Added a C host-model fixture, Rust host tests, provider build script,
  evidence script, tracked NQ/LQ component patches, CI evidence step, and docs.
- Preserved the C TLV behavior for little-endian payloads, empty ASCIZ skip,
  END finalization, typed length checks, null raw payload copy suppression, and
  current malformed matching-tag length reporting.
- Kept C as the normal default and rollback implementation.

Commands:

- `make check-tm-syscfg-model`
- `cargo test --manifest-path rust/Cargo.toml -p qsoe-tm-syscfg --features host-tests`
- `cargo clippy --manifest-path rust/Cargo.toml -p qsoe-tm-syscfg --features host-tests -- -D warnings`
- `bash -n scripts/check-tm-syscfg-model.sh scripts/build-rust-tm-syscfg-provider.sh scripts/tm-syscfg-evidence.sh scripts/apply-component-overrides.sh`
- `./scripts/apply-component-overrides.sh`
- `make -n check-tm-syscfg-model rust-tm-syscfg-provider tm-syscfg-evidence container-rust-tm-syscfg-provider container-tm-syscfg-evidence`
- `make rust-tm-syscfg-provider`
- `make tm-syscfg-evidence`

Result:

- The C host fixture and Rust host tests pass for TLV emit/find/get,
  finalization, empty ASCIZ skip, bounds handling, no emit after finalize, raw
  null payload behavior, malformed matching-tag length reporting, and typed
  length rejection.
- The provider archive exports all `tm_syscfg_*` symbols and all archive
  members report RVC soft-float ABI.
- NQ and LQ C-default taskman archives include one `syscfg.o` member.
  Rust-selected archives include zero `syscfg.o` members and link
  `libqsoe_tm_syscfg.a`.
- The final taskman ELFs link in both modes. Runtime use is not claimed yet:
  NQ does not currently call the portable helper, and LQ uses its private
  global FDT-backed syscfg builder.

Follow-up:

- Later `make tm-syscfg-runtime-smoke` added focused `/sys` and `sysinfo`
  runtime coverage with Rust `tm_syscfg` selected. Keep `tm_syscfg` Rust
  opt-in while deciding whether to open a separate Rust-default RC window with
  the LQ private-runtime-syscfg boundary accepted.

## 2026-06-29 12:54 CEST - tm_script Rust Opt-In Provider

Scope:

- Added `qsoe-tm-script`, a no-std Rust staticlib exporting the existing
  portable `tm_script.h` ABI.
- Added `QSOE_RUST_TM_SCRIPT=1` selection for NQ and LQ taskman. The selector
  omits C `script.o` from `libtaskman.a`, then links
  `build/rust/tm-script/libqsoe_tm_script.a`.
- Added a C host-model fixture, Rust host tests, provider build script,
  evidence script, tracked NQ/LQ component patches, CI evidence step, and docs.
- Preserved the C parser's current truncation behavior for too-small output
  buffers.
- Kept C as the normal default and rollback implementation.

Commands:

- `make check-tm-script-model`
- `cargo test --manifest-path rust/Cargo.toml -p qsoe-tm-script --features host-tests`
- `cargo clippy --manifest-path rust/Cargo.toml -p qsoe-tm-script --features host-tests -- -D warnings`
- `bash -n scripts/check-tm-script-model.sh scripts/build-rust-tm-script-provider.sh scripts/tm-script-evidence.sh scripts/apply-component-overrides.sh`
- `./scripts/apply-component-overrides.sh`
- `make -n rust-tm-script-provider tm-script-evidence container-rust-tm-script-provider container-tm-script-evidence`
- `make rust-tm-script-provider`
- `make tm-script-evidence`
- `make check-host-tools`
- `make rust-check`

Result:

- The C host fixture and Rust host tests pass for interpreter and single
  argument parsing, CR/LF line termination, malformed-line rejection, output
  clearing, zero-capacity behavior, and current truncation behavior.
- The provider archive exports `tm_script_parse_shebang` and all archive
  members report RVC soft-float ABI.
- NQ and LQ C-default taskman archives include one `script.o` member.
  Rust-selected archives include zero `script.o` members and link
  `libqsoe_tm_script.a`; linked taskman ELFs export the expected
  `tm_script_parse_shebang` symbol in both modes.
- The provider mutual-exclusion guard rejects invalid multi-provider taskman
  builds until a shared taskman Rust archive exists.

Follow-up:

- Script-spawn runtime coverage was added later by
  `make tm-script-runtime-smoke`; keep `tm_script` Rust opt-in until a separate
  Rust-default RC decision exists.

## 2026-06-29 12:33 CEST - tm_cpio Rust Opt-In Provider

Scope:

- Added `qsoe-tm-cpio`, a no-std Rust staticlib exporting the existing
  portable `tm_cpio.h` ABI.
- Added `QSOE_RUST_TM_CPIO=1` selection for NQ and LQ taskman. The selector
  omits C `cpio.o` from `libtaskman.a`, then links
  `build/rust/tm-cpio/libqsoe_tm_cpio.a`.
- Added a C host-model fixture, Rust host tests, provider build script,
  evidence script, tracked NQ/LQ component patches, CI evidence step, and docs.
- Matched the C walker's absolute pointer-alignment behavior for unaligned
  archive pointers.
- Kept C as the normal default and rollback implementation.

Commands:

- `make check-tm-cpio-model`
- `cargo test --manifest-path rust/Cargo.toml -p qsoe-tm-cpio --features host-tests`
- `cargo clippy --manifest-path rust/Cargo.toml -p qsoe-tm-cpio --features host-tests -- -D warnings`
- `cargo check --manifest-path rust/Cargo.toml --workspace`
- `cargo clippy --manifest-path rust/Cargo.toml --workspace -- -D warnings`
- `cargo fmt --manifest-path rust/Cargo.toml --all`
- `make check-host-tools`
- `make rust-check`
- `bash -n scripts/check-tm-cpio-model.sh scripts/build-rust-tm-cpio-provider.sh scripts/tm-cpio-evidence.sh scripts/rust-check.sh scripts/rust-workflow.sh`
- `make -n rust-tm-cpio-provider tm-cpio-evidence container-rust-tm-cpio-provider container-tm-cpio-evidence`
- `./scripts/apply-component-overrides.sh`
- `make rust-tm-cpio-provider`
- `make tm-cpio-evidence`
- `make container-tm-cpio-evidence`
- `git diff --check -- ':!patches/components/*.patch'`

Result:

- The C host fixture and Rust host tests pass for archive iteration, exact file
  lookup, symlink resolution, directory existence, directory-entry synthesis,
  short output buffers, missing paths, malformed-archive stopping behavior, and
  absolute pointer-alignment compatibility with the C walker.
- The provider archive exports all six expected symbols and all archive members
  report RVC soft-float ABI.
- NQ and LQ C-default taskman archives include one `cpio.o` member.
  Rust-selected archives include zero `cpio.o` members and link
  `libqsoe_tm_cpio.a`; linked taskman ELFs export the expected `tm_cpio_*`
  ABI symbols in both modes.
- The provider mutual-exclusion guard rejects invalid multi-provider taskman
  builds until a shared taskman Rust archive exists.

Follow-up:

- Keep `tm_cpio` Rust opt-in only until boot/runtime coverage proves
  CPIO-backed spawn and file access before any Rust-default RC decision.

## 2026-06-29 11:39 CEST - tm_sysfs Rust Opt-In Provider

Scope:

- Added `qsoe-tm-sysfs`, a no-std Rust staticlib exporting the existing
  portable `tm_sysfs.h` ABI.
- Added `QSOE_RUST_TM_SYSFS=1` selection for NQ and LQ taskman. The selector
  omits C `tm_sysfs.o` from `libtaskman.a`, then links
  `build/rust/tm-sysfs/libqsoe_tm_sysfs.a`.
- Added a C host-model fixture, Rust host tests, provider build script,
  evidence script, tracked NQ/LQ component patches, CI evidence step, and docs.
- Kept C as the normal default and rollback implementation.

Commands:

- `cargo fmt --manifest-path rust/Cargo.toml --all --check`
- `cargo test --manifest-path rust/Cargo.toml -p qsoe-tm-sysfs --features host-tests`
- `cargo clippy --manifest-path rust/Cargo.toml -p qsoe-tm-sysfs --features host-tests -- -D warnings`
- `cargo check --manifest-path rust/Cargo.toml --workspace`
- `cargo clippy --manifest-path rust/Cargo.toml --workspace -- -D warnings`
- `make rust-check`
- `bash -n scripts/build-rust-tm-sysfs-provider.sh scripts/tm-sysfs-evidence.sh scripts/check-tm-sysfs-model.sh scripts/apply-component-overrides.sh scripts/rust-check.sh scripts/rust-workflow.sh`
- `make -n rust-tm-sysfs-provider tm-sysfs-evidence container-rust-tm-sysfs-provider container-tm-sysfs-evidence`
- `./scripts/apply-component-overrides.sh`
- `make rust-tm-sysfs-provider`
- `make tm-sysfs-evidence`
- `make container-tm-sysfs-evidence`
- `make container-source-build`
- `git diff --check -- ':!patches/components/*.patch'`

Result:

- The C host fixture and Rust host tests pass for newline/NUL snapshot behavior,
  null and empty source fallback, truncation, `/sys` path resolution, entry
  order, content lookup, and out-of-range behavior.
- The provider archive exports all six expected symbols and all archive members
  report RVC soft-float ABI.
- NQ and LQ C-default taskman archives include one `tm_sysfs.o` member.
  Rust-selected archives include zero `tm_sysfs.o` members and link
  `libqsoe_tm_sysfs.a`.
- The provider mutual-exclusion guard rejects invalid multi-provider taskman
  builds until a shared taskman Rust archive exists.
- The NQ/LQ component patch stack replays cleanly from fresh temporary
  component worktrees.

Follow-up:

- Later `make tm-sysfs-runtime-smoke` added focused `/sys` readdir and all-file
  runtime coverage. Keep `tm_sysfs` Rust opt-in pending a separate RC decision.

## 2026-06-29 11:06 CEST - tm_pseudodev Rust Opt-In Provider

Scope:

- Added `qsoe-tm-pseudodev`, a no-std Rust staticlib exporting the existing LQ
  `/dev/null` and `/dev/zero` taskman ABI.
- Added `QSOE_RUST_TM_PSEUDODEV=1` selection for LQ taskman. The selector
  omits C `sys/devnull.o` and `sys/devzero.o`, then links
  `build/rust/tm-pseudodev/libqsoe_tm_pseudodev.a`.
- Added tracked `lq` component patches, override-script checks, make targets,
  container targets, CI evidence step, and docs.
- Kept C as the normal default and rollback implementation.

Commands:

- `./scripts/apply-component-overrides.sh`
- `cargo test --manifest-path rust/Cargo.toml -p qsoe-tm-pseudodev --features host-tests`
- `cargo clippy --manifest-path rust/Cargo.toml -p qsoe-tm-pseudodev --features host-tests -- -D warnings`
- `cargo check --manifest-path rust/Cargo.toml --workspace`
- `cargo clippy --manifest-path rust/Cargo.toml --workspace -- -D warnings`
- `make rust-tm-pseudodev-provider`
- `make tm-pseudodev-evidence`
- `make rust-check`
- `make container-tm-pseudodev-evidence`
- `make container-source-build`
- `git diff --check -- ':!patches/components/*.patch'`

Result:

- The Rust provider host tests pass for ABI layout, stat records, `/dev/null`,
  `/dev/zero`, IPC payload zero-fill, and read clamping.
- The provider archive exports all six expected symbols and all archive members
  report RVC soft-float ABI.
- The LQ C-default link plan includes `sys/devnull.o` and `sys/devzero.o`.
  The Rust-selected link plan omits both C objects and links
  `libqsoe_tm_pseudodev.a`.
- LQ taskman links in both C-default and Rust-selected modes.
- The mutual-exclusion guard rejects selecting multiple taskman Rust providers
  until a shared taskman Rust archive exists.

Follow-up:

- Keep `tm_pseudodev` Rust opt-in only until a focused runtime smoke covers
  `/dev/null` and `/dev/zero` and a separate Rust-default RC decision exists.

## 2026-06-29 09:26 CEST - mkfs-qrv Rust-Default RC Path

Scope:

- Added `scripts/mkfs-qrv-rc-live-smoke.sh`, which selects Rust
  `mkfs-qrv-rs` by default and selects C rollback with
  `MKFS_QRV_RC_ROLLBACK=1`.
- Added `make mkfs-qrv-rc-live-smoke`, `make mkfs-qrv-rc-rollback-smoke`, and
  container equivalents.
- Added trusted CI steps for the Rust-default writer RC live smoke and C
  rollback live smoke.
- Added `MKFS_QRV_RC.md` and updated README, STATUS, HOST_TOOLS, and INVENTORY
  docs.

Commands:

- `bash -n scripts/mkfs-qrv-rc-live-smoke.sh scripts/rust-mkfs-qrv-live-smoke.sh`
- `make -n mkfs-qrv-rc-live-smoke mkfs-qrv-rc-rollback-smoke container-mkfs-qrv-rc-live-smoke container-mkfs-qrv-rc-rollback-smoke`
- `make mkfs-qrv-rc-live-smoke`
- `make mkfs-qrv-rc-rollback-smoke`
- `git diff --check`

Result:

- The Rust-default RC smoke builds the normal virtio qrvfs image with
  `mkfs-qrv-rs`, boots QSOE/L, mounts `/usr`, and reads `/usr/conf/passwd`.
- The rollback smoke selects the existing C `mkfs-qrv` writer and validates the
  same guest file-read path.

Follow-up:

- Keep C `mkfs-qrv` in tree until #26's retirement checklist and a separate
  removal PR are satisfied.

## 2026-06-29 09:17 CEST - Rust mkfs-qrv Triple-indirect Coverage

Scope:

- Added a bounded `qsoe-qrvfs` writer unit test that exercises the
  triple-indirect allocation path without building a multi-gigabyte fixture.
- Extended the writer test helper used for block verification so it can walk
  triple-indirect index blocks.
- Updated README, `HOST_TOOLS.md`, `STATUS.md`, and `INVENTORY.md` to record
  bounded triple-indirect allocator coverage and leave the remaining writer
  gate as a default-writer RC with C rollback.

Commands:

- `cargo fmt --manifest-path rust/Cargo.toml --all`
- `cargo test --manifest-path rust/Cargo.toml -p qsoe-qrvfs writer::tests::allocates_triple_indirect_blocks_without_dense_fixture`
- `make rust-quality`
- `make check-qrvfs-rust-writer-fixture`
- `make check-qrvfs-rust-writer-production-root`
- `git diff --check`

Result:

- The new unit test verifies the triple-indirect root, nested double and single
  index blocks, final data-block mapping, and four-block allocation footprint.

Follow-up:

- Keep C `mkfs-qrv` as the default writer until a default-writer
  release-candidate path with explicit C rollback is in place.

## 2026-06-28 22:32 CEST - Rust mkfs-qrv Live Image Smoke

Scope:

- Added `QSOE_RUST_MKFS_QRV=1` as an opt-in selector for the top-level qrvfs
  image writer while keeping C `mkfs-qrv` as the default.
- Added `scripts/mkfs-qrv-rs-artifact.sh` to build the Rust host writer at
  `build/mkfs-qrv-rs`.
- Added `scripts/rust-mkfs-qrv-live-smoke.sh`, `make rust-mkfs-qrv-live-smoke`,
  and the container wrapper target.
- Updated README, `HOST_TOOLS.md`, `STATUS.md`, and `rust/README.md` to record
  Rust-written live-image evidence and the remaining writer gate.

Commands:

- `bash -n scripts/mkfs-qrv-rs-artifact.sh scripts/rust-mkfs-qrv-live-smoke.sh`
- `make -n rust-mkfs-qrv-artifact rust-mkfs-qrv-live-smoke container-rust-mkfs-qrv-live-smoke`
- `make rust-mkfs-qrv-artifact`
- `QSOE_RUST_MKFS_QRV=1 make fsqrv-image`
- `make rust-mkfs-qrv-live-smoke`
- `make rust-quality`
- `make check-qrvfs-rust-writer-production-root`
- `make check-qrvfs-rust-writer-fixture`
- `make check-qrvfs-rust-fixture`
- `git diff --check`

Result:

- `mkfs-qrv-rs-artifact.sh` built `build/mkfs-qrv-rs`.
- `QSOE_RUST_MKFS_QRV=1 make fsqrv-image` wrote `build/fsqrv.img` from
  `build/fsqrv-root` using Rust `mkfs-qrv-rs`.
- `make rust-mkfs-qrv-live-smoke` booted QSOE/L with C `devb-virtio`, mounted
  the Rust-written virtio qrvfs image at `/usr`, reached the login prompt, and
  printed `rust-virtio-file-smoke.sh: /usr file read smoke passed`.
- The boot log includes the guest marker
  `rust-virtio-file-smoke: read /usr/conf/passwd ok`.
- Rust quality and qrvfs fixture/production-root checks passed.

Follow-up:

- Keep C `mkfs-qrv` available until a default-writer release-candidate path and
  rollback evidence are in place.

## 2026-06-24 16:04 CEST - Pipe Rust-Default RC Path

Scope:

- Added `scripts/pipe-rc-data-smoke.sh`, which selects Rust `/sbin/pipe` by
  default and selects C rollback with `QSOE_PIPE_RC_ROLLBACK=1`.
- Generalized `scripts/rust-pipe-data-smoke.sh` so the same pipe(2)
  data-path smoke validates either Rust or C selected artifacts.
- Added `make pipe-rc-data-smoke`, `make pipe-rc-rollback-smoke`, and
  container equivalents.
- Added trusted CI steps for the Rust-default RC data smoke and C rollback
  data smoke.
- Added `PIPE_RC.md` and updated README, STATUS, HANDOVER, and PIPE docs.

Commands:

- `bash -n scripts/rust-pipe-data-smoke.sh scripts/pipe-rc-data-smoke.sh`
- `make -n pipe-rc-data-smoke pipe-rc-rollback-smoke container-pipe-rc-data-smoke container-pipe-rc-rollback-smoke`
- `git diff --check`
- `make rust-quality`
- `make pipe-rc-data-smoke`
- `make pipe-rc-rollback-smoke`

Result:

- `pipe-rs` has a Rust-default release-candidate path with a one-command C
  rollback drill.
- The Rust-default smoke passed and wrote
  `build/pipe-rc/boot-smoke-lq-rust-pipe-data.log`.
- The C rollback smoke passed and wrote
  `build/pipe-rc/boot-smoke-lq-c-pipe-data.log`.
- No C implementation is removed or disabled.

Follow-up:

- Validate both RC targets through trusted CI before any #26 retirement work.

## 2026-06-24 15:38 CEST - Trusted CI Evidence Accepted

Scope:

- Accepted trusted `main` CI evidence for #96, #97, and #103 from run
  `28102250069` at commit
  `1d7b706403b54e8a798d3b1f560f5473d33e020b`.
- Recorded the hosted-runner evidence in README, STATUS, HANDOVER, PIPE,
  TEST_HELPER, TASK_MANAGER_PROCFS, and TASK_MANAGER_PROCFS_BOUNDARY.
- Kept `pipe`, `test_msgpass`, and `tm_procfs` as Rust opt-in only; no default
  selection or C retirement changed.

Commands:

- `gh run view 28102250069 --json url,createdAt,updatedAt,headSha,conclusion,status,jobs`
- `gh run download 28102250069 -n qsoe-boot-smoke-logs -D /tmp/qsoe-run-28102250069-logs`
- `rg` over downloaded `rust-test-msgpass`, `rust-pipe-data`, and
  `tm-procfs-evidence` logs for the required markers.

Result:

- `container-rust-test-msgpass-smoke` passed on runner `qsoe-ci-x64`; the log
  contains `[test_msgpass-rs] alive`, `[test_msgpass-rs] /dev/msgpass
  registered`, targeted `[msgpass]` PASS/SKIP markers, suite exit, and
  boot-to-login.
- `container-rust-pipe-data-smoke` passed; the uploaded log contains
  `[pipe-rs] /dev/pipe registered`, `[test_pipe_data] pipe round-trip ok`,
  `[test_pipe_data] pipe eof ok`, `rust-pipe-data-smoke: helper exited 0`, and
  boot-to-login.
- `container-tm-procfs-evidence` passed; uploaded logs contain C-default and
  Rust-selected `/proc` smoke markers, and archive membership summaries show
  C-default `tm_procfs.o` count `1` and Rust-selected count `0` for both NQ and
  LQ.
- The artifact `qsoe-boot-smoke-logs` was uploaded as artifact ID
  `7851201333`.

Follow-up:

- Close #96, #97, and #103 as evidence-complete.
- Keep #26 blocked until the retirement checklist and a separate removal PR are
  satisfied.

## 2026-06-24 14:20 CEST - Slogger RC Evidence Accepted

Scope:

- Accepted #95's local-equivalent `slogger-rs` Rust-default RC evidence window.
- Re-ran the Rust-default RC readback smoke and the C rollback readback smoke
  on current `main`.
- Updated `SLOGGER_RC.md`, STATUS, HANDOVER, and README to record the accepted
  evidence while keeping C retirement blocked by #26.

Commands:

- `make slogger-rc-readback-smoke`
- `make slogger-rc-rollback-smoke`
- `git diff --check`

Result:

- Rust-default RC readback passed and observed `pci-server:` through
  `/bin/sloginfo` in
  `build/slog-readback-smoke-lq-slogger-rc-rust-default-20260624-142035.log`.
- C rollback readback passed and observed `pci-server:` through `/bin/sloginfo`
  in
  `build/slog-readback-smoke-lq-slogger-rc-c-rollback-20260624-142039.log`.
- `SLOGGER_RC.md` keeps the rollback command and rollback window. No C
  implementation is removed or disabled.

Follow-up:

- Keep #26 blocked until `RETIREMENT.md` is satisfied and a separate removal PR
  is reviewed.

## 2026-06-24 14:09 CEST - tm_procfs Evidence Gate

Scope:

- Added `scripts/tm-procfs-evidence.sh`, which builds the Rust provider,
  audits provider/taskman ELF properties, verifies C-default and Rust-selected
  archive membership, and runs both C-default and Rust-selected `/proc` smokes.
- Added `make tm-procfs-evidence` and `make container-tm-procfs-evidence`.
- Added the trusted CI step on the configured `[self-hosted, X64]` runner and
  uploads for `build/tm-procfs-evidence/**/*.log` and `*.txt`.
- Updated README, STATUS, HANDOVER, `TASK_MANAGER_PROCFS.md`, and
  `TASK_MANAGER_PROCFS_BOUNDARY.md` to track #103 without changing the default
  provider.

Commands:

- `bash -n scripts/tm-procfs-evidence.sh`
- `make -n tm-procfs-evidence container-tm-procfs-evidence`
- `make tm-procfs-evidence`
- `make container-toolchain-build`
- `make container-tm-procfs-evidence`
- `git diff --check`

Result:

- The #103 gate now has one command that captures the Rust opt-in evidence and
  the C rollback evidence side by side.
- The CI job runs the evidence command only for trusted contexts, matching the
  existing smoke-test trust boundary.
- The refreshed Debian toolchain image includes the taskman soft-float Rust
  target and passes the container evidence wrapper.
- C remains the default `tm_procfs` provider.

Follow-up:

- Use a green trusted CI run of `container-tm-procfs-evidence` before opening
  any separate Rust-default `tm_procfs` selection PR.

## 2026-06-24 13:55 CEST - tm_procfs Rust Opt-In Provider

Scope:

- Added `qsoe-tm-procfs`, a no-std Rust staticlib exporting the existing
  `tm_procfs.h` ABI.
- Added `scripts/build-rust-tm-procfs-provider.sh` and
  `make rust-tm-procfs-provider`.
- Added `QSOE_RUST_TM_PROCFS=1` build selection for NQ and LQ taskman:
  selected builds omit C `tm_procfs.o` from `libtaskman.a` and link the Rust
  staticlib separately.
- Added `riscv64imac-unknown-none-elf` to the Debian toolchain image for
  taskman-compatible soft-float Rust archives.
- Updated README, STATUS, HANDOVER, `TASK_MANAGER_PROCFS.md`, and
  `TASK_MANAGER_PROCFS_BOUNDARY.md`.

Commands:

- `cargo fmt --manifest-path rust/Cargo.toml --all --check`
- `cargo test --manifest-path rust/Cargo.toml -p qsoe-tm-procfs --features host-tests`
- `cargo clippy --manifest-path rust/Cargo.toml -p qsoe-tm-procfs -- -D warnings`
- `bash -n scripts/build-rust-tm-procfs-provider.sh scripts/check-tm-procfs-model.sh scripts/procfs-smoke.sh`
- `make -n rust-tm-procfs-provider container-rust-tm-procfs-provider`
- `make rust-tm-procfs-provider`
- `make -C libtaskman O=/tmp/qsoe-libtaskman-c QSOE_RUST_TM_PROCFS=0`
- `make -C libtaskman O=/tmp/qsoe-libtaskman-rust QSOE_RUST_TM_PROCFS=1`
- `make -C nq/taskman QSOE_RUST_TM_PROCFS=0`
- `make -C nq/taskman QSOE_RUST_TM_PROCFS=1`
- `make -C lq QSOE_RUST_TM_PROCFS=0 taskman`
- `make -C lq QSOE_RUST_TM_PROCFS=1 taskman`
- `QSOE_RUST_TM_PROCFS=1 make procfs-smoke`

Result:

- The Rust provider host test passed the same path-resolution, formatting,
  readdir, unset-callback, and disappeared-pid contract as the C model.
- `libqsoe_tm_procfs.a` is built for `riscv64imac-unknown-none-elf` and reports
  RVC soft-float ELF flags.
- C-default `libtaskman.a` includes `tm_procfs.o`; Rust-selected
  `libtaskman.a` contains zero `tm_procfs.o` members after fixing stale archive
  replacement.
- NQ and LQ taskman both link with `QSOE_RUST_TM_PROCFS=1`, and both selector
  flips preserve the C rollback archive membership.
- The Rust-selected LQ image passed `/proc` smoke and reached the normal login
  markers.

Follow-up:

- Use #103 to collect accepted hosted/Linux evidence before any Rust-default
  `tm_procfs` selection decision.
- Keep `QSOE_RUST_TM_PROCFS=0` as the normal default and rollback path.

## 2026-06-24 13:29 CEST - tm_procfs Host Model Tests

Scope:

- Added `tests/tm_procfs_model_test.c`, a host-side fixture that links the
  current C `libtaskman/src/tm_procfs.c` model directly.
- Added `scripts/check-tm-procfs-model.sh`.
- Added `make check-tm-procfs-model` and included it in `make check-host-tools`
  so `container-check` also picks it up.
- Updated README, STATUS, HANDOVER, and the `tm_procfs` selection doc to record
  the host-model evidence before any Rust task-manager provider wiring.

Commands:

- `bash -n scripts/check-tm-procfs-model.sh`
- `make -n check-tm-procfs-model check-host-tools`
- `make check-tm-procfs-model`
- `make check-host-tools`
- `git diff --check`

Result:

- The host fixture covers `/proc` path resolution, malformed and unknown pid
  failure behavior, alive/zombie `info` formatting, the maximum carried process
  name, root readdir cursor behavior, per-pid `info` readdir behavior, unset
  callbacks, and a pid disappearing between operations.
- No task-manager runtime wiring changed; the C `tm_procfs` model remains the
  default and rollback path.

Follow-up:

- Implement a Rust `tm_procfs` provider behind `QSOE_RUST_TM_PROCFS=1`, then
  run artifact audit, boot smoke, and `make procfs-smoke` before any default
  selection decision.

## 2026-06-24 13:22 CEST - Slogger RC Smokes Added To Trusted CI

Scope:

- Added `make container-slogger-rc-readback-smoke` and
  `make container-slogger-rc-rollback-smoke` to the main GitHub Actions CI job
  on the configured `[self-hosted, X64]` runner.
- Gated both self-hosted smoke steps to trusted contexts only: push,
  `workflow_dispatch`, and same-repository pull requests.
- Extended CI artifact upload coverage to include the default `slogger-rc`
  readback log patterns.
- Updated README, STATUS, and HANDOVER to track the trusted-CI RC evidence
  window through #95 while keeping C retirement blocked by #26.

Commands:

- `bash -n scripts/rust-slogger-boot-smoke.sh scripts/slogger-rc-boot-smoke.sh`
- `make -n container-slogger-rc-readback-smoke container-slogger-rc-rollback-smoke`
- `make slogger-rc-readback-smoke && make slogger-rc-rollback-smoke`
- `git diff --check`

Result:

- The `slogger-rs` Rust-default RC and C rollback readback smokes are now
  represented directly in CI for trusted contexts. Green runs can be used as
  #95 evidence before any #26 retirement decision.
- Local serial RC readback smokes passed for `slogger-rc-rust-default` and
  `slogger-rc-c-rollback`; both observed `pci-server:` through `/bin/sloginfo`.

Follow-up:

- Wait for green trusted CI RC evidence before considering C `slogger` removal.
- Keep the C rollback path documented in release notes until #26 is satisfied.

## 2026-06-24 13:16 CEST - Test Msgpass Smoke Added To Trusted CI

Scope:

- Added `make container-rust-test-msgpass-smoke` to the main GitHub Actions CI
  job on the configured `[self-hosted, X64]` runner.
- Gated the self-hosted smoke step to trusted contexts only: push,
  `workflow_dispatch`, and same-repository pull requests.
- Extended CI artifact upload coverage to include `build/rust-test-msgpass/*.log`.
- Updated README, STATUS, and HANDOVER to track the trusted-CI evidence gate
  through #97.

Commands:

- `bash -n scripts/rust-test-msgpass-smoke.sh`
- `make -n container-rust-test-msgpass-smoke`
- `make rust-test-msgpass-smoke`
- `git diff --check`

Result:

- The Rust-selected `test_msgpass-rs` smoke is now represented directly in CI
  for trusted contexts. A green run can be used as evidence before any
  Rust-default test-image decision.
- Local host smoke still passes and verifies the targeted `[msgpass]` suite
  markers before reaching `login:`.

Follow-up:

- Wait for #97's green trusted CI evidence before considering a Rust-default
  test image.
- Keep the C `/usr/bin/test_msgpass` helper as the default until a separate
  default-selection decision lands.

## 2026-06-24 13:03 CEST - Pipe Data Smoke Added To CI

Scope:

- Added `make container-rust-pipe-data-smoke` to the main GitHub Actions CI job
  on the configured `[self-hosted, X64]` runner.
- Gated that self-hosted smoke step to trusted contexts only: push,
  `workflow_dispatch`, and same-repository pull requests.
- Extended CI artifact upload coverage to include `build/rust-pipe-data/*.log`.
- Refreshed the handover and status docs after PR #93 landed at
  `338517613bd507db18bfe82da8c9d2818bc67dfe`.

Commands:

- `bash -n scripts/rust-pipe-data-smoke.sh`
- `make -n container-rust-pipe-data-smoke`
- `make rust-pipe-data-smoke`
- `git diff --check`

Result:

- The next pipe gate is now represented directly in CI. A green run of this
  workflow provides the hosted-runner data-path evidence needed before a
  Rust-default pipe release-candidate decision.
- The new self-hosted smoke step is skipped for forked pull requests.
- Local host smoke still passes and verifies `[pipe-rs] /dev/pipe registered`,
  `[test_pipe_data] pipe round-trip ok`, `[test_pipe_data] pipe eof ok`, and
  `rust-pipe-data-smoke: helper exited 0`.

Follow-up:

- Wait for a green trusted CI run before opening a Rust-default pipe RC PR.
- Keep #26 blocked until the `slogger-rs` RC evidence window is accepted and
  `RETIREMENT.md` is satisfied.

## 2026-06-24 12:21 CEST - Slogger Rust-Default RC Path

Scope:

- Added `scripts/slogger-rc-boot-smoke.sh`, a release-candidate wrapper that
  selects `slogger-rs` by default and selects the C rollback artifact with
  `QSOE_SLOGGER_RC_ROLLBACK=1`.
- Made `scripts/rust-slogger-boot-smoke.sh` mode-aware so the same image
  preparation code can build either the Rust RC image or the C rollback image.
- Added `--slogger-rc` and `--slogger-rc-rollback` modes to
  `scripts/slog-readback-smoke.py`.
- Added `make slogger-rc-boot-smoke`, `make slogger-rc-readback-smoke`,
  `make slogger-rc-rollback-smoke`, and container wrappers.
- Added `SLOGGER_RC.md` and updated migration status, handover, and READMEs.

Commands:

- `bash -n scripts/rust-slogger-boot-smoke.sh scripts/slogger-rc-boot-smoke.sh`
- `python3 -m py_compile scripts/slog-readback-smoke.py`
- `make -n slogger-rc-boot-smoke slogger-rc-readback-smoke slogger-rc-rollback-smoke container-slogger-rc-boot-smoke container-slogger-rc-readback-smoke container-slogger-rc-rollback-smoke`
- `make slogger-rc-readback-smoke`
- `make slogger-rc-rollback-smoke`
- `QSOE_SLOGGER_RC_ROLLBACK=1 scripts/slog-readback-smoke.py --slogger-rc -t 180 -o build/slogger-rc/slog-readback-env-forced-rust.log`
- `make rust-slogger-link-smoke`
- `make rust-quality`

Result:

- The Rust-default RC readback smoke passed and observed `pci-server:` through
  `/bin/sloginfo` with `[slogger-rs] alive`.
- The C rollback readback smoke passed and observed `pci-server:` through
  `/bin/sloginfo` with `[slogger] alive`.
- `--slogger-rc` forces the Rust-default path even if
  `QSOE_SLOGGER_RC_ROLLBACK=1` is present in the caller environment.
- `slogger-rs` remains the only component in a Rust-default RC state.
- No C implementation was retired; #26 remains open until the RC evidence
  window is accepted and the retirement checklist is satisfied.

Follow-up:

- Let the `slogger-rs` RC evidence window run before any C removal PR.
- Keep the C rollback command in release notes until #26 is satisfied.

## 2026-06-24 11:46 CEST - Rust Pipe Data-Path Smoke

Scope:

- Added a script-generated `test_pipe_data` guest helper that calls normal libc
  `pipe(2)`, writes a payload, reads it back, closes the writer, and verifies
  EOF on the read end.
- Added `scripts/rust-pipe-data-smoke.sh`.
- Added `make rust-pipe-data-smoke` and `make container-rust-pipe-data-smoke`.
- Updated pipe migration docs, status, and root README to record the new
  data-path gate.

Commands:

- `bash -n scripts/rust-pipe-data-smoke.sh`
- `make -n rust-pipe-data-smoke container-rust-pipe-data-smoke`
- `make rust-pipe-data-smoke`
- `make rust-quality`
- `cargo test --manifest-path rust/Cargo.toml -p qsoe-pipe`

Result:

- `test_pipe_data` was generated under `build/rust-pipe-data/` and linked
  against the LQ libc path.
- `make rust-pipe-data-smoke` passed.
- `make rust-quality` passed.
- `qsoe-pipe` passed 11 host tests.
- The boot log reached `login:` and contained:
  - `[pipe-rs] /dev/pipe registered`
  - `[test_pipe_data] pipe round-trip ok`
  - `[test_pipe_data] pipe eof ok`
  - `rust-pipe-data-smoke: helper exited 0`

Follow-up:

- Repeat the smoke on the hosted runner before any Rust-default pipe
  release-candidate decision.

## 2026-06-24 11:23 CEST - Stack Merged To Main

Scope:

- Merged the stacked handover PR chain through #89 into `main`.
- Closed completed GitHub issues whose `Closes` references landed through the
  non-default stacked merges.
- Closed the old #82/#83 external blocker trackers and #84 bottom-up merge
  tracker after accepting those states for the merge decision.
- Updated the root README and this handover to remove stale active-blocker
  text.

Commands:

- GitHub connector PR merge and issue update operations.
- `git fetch origin`
- `git switch main`
- `git pull --ff-only origin main`
- `git status --short --branch`

Result:

- `main` is at `a3e75dbc47d1fadc99360f4476147a526f521d9b`.
- The local checkout is on `main` and matches `origin/main`.
- Open issues are #26 for the C retirement gate and #90 for the Rust pipe
  data-path smoke.

Follow-up:

- Continue with #90 or the next bounded `tm_procfs` Rust provider work.
- Keep C retirement blocked by the release-candidate policy in
  `RETIREMENT.md`.

## 2026-06-24 08:32 CEST - Rust Pipe Opt-In

Scope:

- Added `qsoe-pipe`, a dependency-free no-std state machine for the current C
  `/sbin/pipe` behavior: fixed pipe pool, 4 KiB rings, badge decode,
  wrong-end errors, parked reader/writer wakeups, close handling, EOF, and pool
  exhaustion.
- Added `qsoe-pipe-rs`, a direct QSOE resource-server wrapper for `/dev/pipe`.
- Added `QSOE_RUST_PIPE=1 make pipe-artifact`, `make rust-pipe-link-smoke`,
  `make rust-pipe-smoke`, and container wrappers.
- Updated pipe migration docs and the root progress README.

Commands:

- `cargo fmt --manifest-path rust/Cargo.toml --all`
- `cargo test --manifest-path rust/Cargo.toml -p qsoe-pipe`
- `cargo check --manifest-path rust/Cargo.toml -p qsoe-pipe-rs --target riscv64gc-unknown-none-elf`
- `bash -n scripts/select-pipe-artifact.sh scripts/rust-pipe-smoke.sh`
- `make -n rust-pipe-link-smoke pipe-artifact rust-pipe-smoke container-rust-pipe-link-smoke container-pipe-artifact container-rust-pipe-smoke`
- `make rust-pipe-link-smoke`
- `QSOE_RUST_PIPE=1 make pipe-artifact`
- `scripts/rust-pipe-smoke.sh -t 180 -o build/rust-pipe/boot-smoke-lq-rust-pipe.log`

Result:

- `qsoe-pipe` passed 11 host tests.
- `qsoe-pipe-rs` linked as a QSOE RISC-V userland ELF and passed the strict
  ELF audit.
- The Rust-selected LQ boot smoke reached `login:` and found both
  `[pipe-rs] /dev/pipe registered` and
  `rust-pipe-smoke: started /sbin/pipe` in the boot log.

Follow-up:

- Keep the C pipe manager as the default until a data-path smoke exists for
  real pipe creation through libc/taskman and a Rust-default release candidate
  with C rollback is approved. The data-path smoke is tracked by #90.

## 2026-06-24 07:54 CEST - Rust Test Msgpass Helper Opt-In

Scope:

- Added `qsoe-test-msgpass-rs`, a no-std Rust replacement for the C
  `/usr/bin/test_msgpass` helper.
- Added the `QSOE_RUST_TEST_MSGPASS=1` selector and
  `make test-msgpass-artifact`.
- Added `make rust-test-msgpass-link-smoke` and
  `make rust-test-msgpass-smoke`.
- Made top-level `FSQRV_BINS` environment-overridable so focused smokes can
  preserve an explicit qrvfs binary list through `lq/emu.sh`'s idempotent
  `make virtio` rebuild without editing the nested `lq` component.
- Added the root `README.md` migration-progress handover.

Commands:

- `bash -n scripts/rust-test-msgpass-smoke.sh scripts/select-test-msgpass-artifact.sh lq/emu.sh`
- `cargo test --manifest-path rust/Cargo.toml -p qsoe-test-msgpass-rs --features host-tests`
- `make rust-test-msgpass-link-smoke`
- `QSOE_RUST_TEST_MSGPASS=1 make test-msgpass-artifact`
- `scripts/rust-test-msgpass-smoke.sh -t 240 -o build/rust-test-msgpass/boot-smoke-lq-rust-test-msgpass-env-override.log`

Result:

- The initial fixed 4 MiB Rust `.bss` buffer failed QSOE/L spawn with
  `frame table overflow (>256 pages)`. The helper now allocates the receive
  buffer at runtime through libc `malloc`/`free`.
- The first Rust-selected round trip passes the 4 MiB minus 2 byte bulk IPC
  payload and halfword-swap checks.
- The helper retries `/dev/msgpass` registration so the `--no-reply` subcase
  waits for stale path cleanup instead of attaching to an old channel.
- `rust-test-msgpass-smoke.sh` passed. The wider suite still contains the
  known unrelated QSOE/L sync failure, so this smoke verifies the `[msgpass]`
  markers and boot-to-login rather than requiring a clean full-suite exit.

Follow-up:

- Keep the C helper as the default until CI/runner evidence supports a
  Rust-default test-image decision.

## 2026-06-24 07:31 CEST - Rust Slogger Readback Smoke

Scope:

- Added `--rust-slogger` to `scripts/slog-readback-smoke.py`.
- Made the default readback smoke prepare a C-slogger LQ image before checking
  `[slogger] alive`.
- Added `--prepare-only` to `scripts/rust-slogger-boot-smoke.sh` so narrower
  smokes can reuse the Rust-slogger CPIO/image preparation without running the
  login boot smoke first.
- Added `make rust-slog-readback-smoke` and
  `make container-rust-slog-readback-smoke`.
- Updated `SLOGGER.md`, `STATUS.md`, and `rust/README.md` for the new parity
  evidence.

Commands:

- `python3 -m py_compile scripts/slog-readback-smoke.py`
- `bash -n scripts/rust-slogger-boot-smoke.sh`
- `make -n slog-readback-smoke rust-slog-readback-smoke container-rust-slog-readback-smoke`
- `git diff --check`
- `scripts/slog-readback-smoke.py -t 180 -o build/slog-readback-smoke-lq-c-slogger-after-rust.log`
- `scripts/slog-readback-smoke.py --rust-slogger -t 180 -o build/slog-readback-smoke-lq-rust-slogger-final.log`

Result:

- The default C-selected readback smoke rebuilt a C-slogger LQ image and
  observed the `pci-server` slog entry through `/bin/sloginfo`.
- The Rust-selected readback smoke rebuilt an opt-in `slogger-rs` LQ image and
  observed the same `pci-server` slog entry through `/bin/sloginfo`.

Follow-up:

- Use the #86 evidence for #85 before any Rust-default release-candidate
  decision.
- The next `slogger` gate remains a Rust-default release candidate with C
  rollback.

## 2026-06-24 07:25 CEST - Current Follow-up Issues Created

Scope:

- Created GitHub issues for the current handover blockers and next execution
  steps:
  - #82: restore self-hosted runner availability for the draft stack.
  - #83: resolve or explicitly record the CodeRabbit usage-credit blocker.
  - #84: prepare the draft stack for bottom-up merge.
  - #85: add Rust-selected `/dev/slog` readback parity smoke.
- Updated `HANDOVER.md` to reference those issue numbers from the blocker and
  next-work sections.

Commands:

- `gh issue list --state all --limit 120 --json number,title,state,labels,url`
- GitHub issue creation through the connected GitHub tool.

Result:

- The latest plan is tracked in GitHub instead of only in local migration docs.

Follow-up:

- Use #82 and #83 to decide when the draft stack can become ready for review.
- Use #85 as the next slogger parity task after the current stack lands.

## 2026-06-24 07:21 CEST - Handover Status Refreshed

Scope:

- Updated `HANDOVER.md` from the old macOS/GitLab snapshot to the current Linux
  GitHub handover repository.
- Recorded the active stacked PR chain from #42 through #80.
- Documented the #42 self-hosted runner queue and #60 CodeRabbit credit status
  as external blockers.
- Replaced stale next-work items with current merge-readiness and post-stack
  implementation tasks.

Commands:

- `git remote -v`
- `gh pr list --state open --limit 120 --json number,title,headRefName,baseRefName,isDraft,mergeable,statusCheckRollup,url`
- `gh run list --limit 20 --json databaseId,displayTitle,status,conclusion,workflowName,headBranch,event,createdAt,updatedAt,url`

Result:

- The checked-in handover now matches the current machine, branch tip, stack
  shape, validation state, and remaining blockers.

Follow-up:

- Update `HANDOVER.md` again after the draft stack is marked ready, merged, or
  retargeted.

## 2026-06-24 02:46 CEST - Slog Readback Smoke Stacked

Scope:

- Ported the existing `/dev/slog` readback smoke into the active migration
  stack.
- Added `scripts/slog-readback-smoke.py`.
- Added `make slog-readback-smoke`.
- Documented the smoke in `SLOGGER.md`.
- Marked the `/dev/slog` smoke backlog item complete in the stacked docs.

Commands:

- `git cherry-pick 0971d1faf80f0416339875aa7ea36cf761f40201`
- `python3 -m py_compile scripts/slog-readback-smoke.py`
- `make -n slog-readback-smoke`
- `scripts/slog-readback-smoke.py -t 120 -o build/slog-readback-smoke-stacked.log`

Result:

- The stack now carries the readback smoke that had previously lived only on
  side PR #43. This prevents later stacked docs from reopening the completed
  `/dev/slog` smoke task.
- The stacked smoke run observed a `pci-server:` entry through `/bin/sloginfo`.
- Follow-up docs now distinguish the C readback baseline from the later
  Rust-selected readback parity gate.

Follow-up:

- Keep the side PR closed once this stacked PR is open, so issue #2 has one
  active implementation path.

## 2026-06-24 02:42 CEST - Release Note Template Added

Scope:

- Added `RELEASE_NOTE_TEMPLATE.md` for Rust migration release notes.
- Required language-change, rollback, test-evidence, known-limitation, and
  unsafe-review fields in the template.
- Linked the template from the migration index, release/rollback policy, and
  retirement checklist.
- Marked the release-note-template task complete.

Commands:

- `gh issue view 40 --json number,title,body,state,url,labels`
- `rg -n "release note|release-note|language change|rollback|known limitations|template|Release And Rollback|C rollback|Rust default|Retired" docs .github Makefile scripts -g "!build/**" -g "!rust/target/**" -g "!rust/fuzz/target/**"`

Result:

- Future Rust opt-in, Rust-default, and C-retirement notes have one template for
  language changes, rollback flags, test evidence, and limitations.

Follow-up:

- Use the template when a component changes selector state, default language, or
  retirement status.

## 2026-06-24 02:38 CEST - Migration Status Matrix Added

Scope:

- Added `STATUS.md` as the current migration status matrix.
- Listed every tracked replacement candidate with C default, Rust opt-in, Rust
  default, and retired status.
- Linked the matrix from the migration index and retirement gate.
- Marked the migration-status-table task complete.

Commands:

- `gh issue view 39 --json number,title,body,state,url,labels`
- `rg -n "status|default|opt-in|retired|retirement|component|slogger|virtio|pipe|procfs|minimal|service-example|Rust" docs/rust-migration -g "*.md"`
- `rg -n "QSOE_RUST|USE_RUST|RUST_.*=|rust-.*smoke|link-smoke|boot|artifact|retire|default" Makefile scripts rust quser lq docs/rust-migration/SLOGGER.md docs/rust-migration/SLOGGER_BOOT_COMPARE.md docs/rust-migration/VIRTIO_BLOCK.md docs/rust-migration/PIPE.md docs/rust-migration/TEST_HELPER.md docs/rust-migration/TASK_MANAGER_PROCFS_BOUNDARY.md -g "!rust/target/**" -g "!rust/fuzz/target/**"`

Result:

- The docs now show that the host `treeqrvfs` inspector, `slogger`, and
  `devb-virtio` are C-default with Rust opt-in coverage, while `pipe`,
  `test_msgpass`, and `tm_procfs` remain C-default future candidates. No
  component is Rust-default or retired.

Follow-up:

- Update `STATUS.md` whenever a component gains a Rust selector, flips default,
  or enters a retirement PR.

## 2026-06-24 02:34 CEST - Unsafe Review Checklist Added

Scope:

- Added `UNSAFE_REVIEW.md` for Rust migration PRs.
- Required PRs to state either "no new unsafe code" or summarize the unsafe
  review checklist.
- Linked the checklist from the migration index, workflow, and unsafe-code
  policy in `SPEC.md`.
- Marked the cross-cutting unsafe-review checklist task complete.

Commands:

- `gh issue view 38 --json number,title,body,state,url,labels`
- `rg -n "unsafe|checklist|review|SAFETY|unsafe block|Unsafe" docs rust -g '!build/**' -g '!rust/target/**' -g '!rust/fuzz/target/**'`
- `rg -n "unsafe" rust -g '*.rs' -g '!target/**' -g '!fuzz/target/**'`

Result:

- Future Rust migration PRs have a documented unsafe review reference and a
  concrete checklist for invariants, evidence, and residual risk.

Follow-up:

- Use the checklist in PR bodies whenever unsafe Rust, FFI, MMIO, DMA, or
  global mutable state changes.

## 2026-06-24 02:32 CEST - Rust Coverage Reporting Added

Scope:

- Added `scripts/rust-coverage.sh` for host-side parser and ABI coverage.
- Added `make rust-coverage` and `make container-rust-coverage`.
- Wired coverage into `make rust-deep` when cargo-llvm-cov is installed.
- Documented LCOV and text summary outputs under ignored
  `build/rust-coverage/`.
- Marked the cross-cutting Rust coverage task complete.

Commands:

- `gh issue view 37 --json number,title,body,state,url,labels`
- `cargo llvm-cov --version`
- Reviewed cargo-llvm-cov README for `--text`, `--lcov`, and `--output-path`
  report flags.

Result:

- Host crates can now produce coverage for parser and ABI tests without adding
  generated report files to git. The local environment skipped execution
  because cargo-llvm-cov is not installed.

Follow-up:

- Install cargo-llvm-cov in any environment that should publish coverage
  artifacts or enforce coverage thresholds.

## 2026-06-24 02:25 CEST - Parser Fuzz Targets Added

Scope:

- Added a `rust/fuzz` cargo-fuzz package outside the main workspace.
- Added bounded parser fuzz targets for `qrvfs`, `cpio`, `elf`, `syscfg`, and
  `sysmap`.
- Added `scripts/rust-fuzz-smoke.sh`, `make rust-fuzz-smoke`, and
  `make container-rust-fuzz-smoke`.
- Wired the fuzz smoke into `make rust-deep` when cargo-fuzz is installed.
- Documented that GPT should join the same fuzz package once a Rust GPT parser
  crate exists.
- Marked the cross-cutting parser-fuzz task complete.

Commands:

- `gh issue view 36 --json number,title,body,state,url,labels`
- `rg -n "pub struct|pub enum|pub fn|impl<'a>|impl Archive|fn parse|fn new|fn iter|entries|relocations|sections|Sys|View|Image" rust/crates/qsoe-cpio/src/lib.rs rust/crates/qsoe-elf/src/lib.rs rust/crates/qsoe-sysview/src/lib.rs rust/crates/qsoe-qrvfs/src/lib.rs`
- `cargo fuzz --help`

Result:

- Parser fuzzing is available as an optional deep/local gate without changing
  the default Rust workspace or normal CI dependencies.

Follow-up:

- Add a GPT fuzz target when the migration has a Rust GPT parser crate.

## 2026-06-24 02:21 CEST - Installed Artifact Audit Target Added

Scope:

- Added `scripts/audit-artifacts.sh` to discover ELF files installed into the
  boot CPIO staging root and qrvfs `/usr` staging root.
- Added `make audit-artifacts` and `make container-audit-artifacts`.
- Added the installed-artifact audit to GitHub Actions after the source build.
- Documented the CI step in `WORKFLOW.md`.
- Marked the cross-cutting artifact-audit target task complete.

Commands:

- `gh issue view 35 --json number,title,body,state,url,labels`
- `find quser/build/modpkg-root -type f`
- `find build/fsqrv-root -type f`
- `sed -n '1,260p' quser/Makefile`
- `sed -n '1,220p' scripts/capture-elf-baseline.sh`

Result:

- One command now audits the ELF artifacts that are actually staged for
  userland images, instead of only the representative baseline sample.

Follow-up:

- Keep strict Rust artifact gates separate from the current C userland audit,
  because existing C binaries intentionally contain unwind metadata.

## 2026-06-24 02:17 CEST - Kernel Artifact Audit Needs Defined

Scope:

- Added `KERNEL_ARTIFACT_AUDIT.md` for Phase 10.
- Recorded the current NQ kernel compile/link posture from `nq/Makefile` and
  `kernel/arch/riscv/kernel.ld`.
- Defined future audit requirements for Rust codegen assumptions, live
  sections, linker-script compatibility, panic behavior, and forbidden runtime
  references.
- Marked the Phase 10 kernel artifact-audit task complete.

Commands:

- `gh issue view 33 --json number,title,body,state,url`
- `sed -n '1,240p' nq/Makefile`
- `sed -n '1,140p' nq/kernel/arch/riscv/kernel.ld`
- `sed -n '1,130p' rust/targets/riscv64-qsoe-user.json`
- `rg -n 'no_std|panic_handler|eh_personality|compiler_builtins|memcpy|memset|extern "C"|panic' rust -g '*.rs' -g '*.toml'`

Result:

- The kernel audit requirement is documented without adding Rust objects,
  kernel build flags, or `nq` wiring. Future kernel work must inspect both
  Rust input objects and the final linked kernel ELF.

Follow-up:

- Keep Phase 10 blocked on documentation until `D-021` is superseded.

## 2026-06-24 02:13 CEST - Kernel Candidates Inventoried

Scope:

- Added `KERNEL_CANDIDATES.md` for Phase 10.
- Listed explicit exclusions for traps, context switching, scheduler core,
  boot assembly, interrupt routing, syscall/user-copy paths, and QSOE/L seL4
  capability assumptions.
- Ranked only fixture or helper-prototype candidates: trace-ring formatting,
  queue invariant modeling, sysmap TLV encoding, sysinfo record formatting, and
  read-only FDT walking.
- Kept `D-021` intact: no Rust crate or build flag is approved for `nq`.
- Marked the Phase 10 kernel-candidate task complete.

Commands:

- `gh issue view 32 --json number,title,body,state,url`
- `find nq/kernel nq/include/skimmer -path '*/build/*' -prune -o -type f \\( -name '*.c' -o -name '*.h' -o -name '*.S' \\) -print | sort`
- `rg -n "trace_ring|TRACE_FN|trace_ring_dump|ln_put|sysmap_emit|sysmap_init|sysinfo|TM_PRIV_SYSINFO|copy_to_user|fdt_|TAILQ|SLIST|STAILQ" nq/kernel nq/include/skimmer -g '*.c' -g '*.h' -g '*.S'`

Result:

- Kernel work remains documentation-only. The safest future prototype is
  trace-ring formatting because it can be host-tested without entering traps,
  switching, scheduling, boot assembly, or live platform setup.

Follow-up:

- Define the kernel artifact audit needs before any later implementation
  reconsideration.

## 2026-06-24 02:09 CEST - Kernel Rust Decision Recorded

Scope:

- Added decision `D-021` rejecting near-term Rust implementation work inside
  `nq`.
- Based the decision on completed parser, userland pilot, virtio smoke,
  retirement-gate, and task-manager procfs evidence.
- Kept Phase 10 kernel work limited to candidate and artifact-audit
  documentation.
- Marked the Phase 10 kernel decision task complete.

Commands:

- `gh issue view 31 --repo dmytro-yemelianov/qsoe-os-rust-handover --json number,title,body,state,labels,url`
- `rg -n "^## D-[0-9]+" docs/rust-migration/DECISIONS.md`

Result:

- Near-term kernel Rust is explicitly rejected until at least one Rust
  component completes a Rust-default release candidate with C rollback and
  task-manager pilot evidence moves beyond documentation.

Follow-up:

- Identify safe kernel candidates while excluding traps, context switching,
  scheduler core, boot assembly, and seL4 capability assumptions.

## 2026-06-24 02:05 CEST - Procfs Boot Smoke Added

Scope:

- Added `scripts/procfs-smoke.sh`.
- Added `make procfs-smoke` and `make container-procfs-smoke`.
- The smoke injects a temporary `/usr/conf/sysinit` fragment, rebuilds the
  normal C-default QSOE/L image, lists `/proc`, reads `/proc/1/info`, and
  verifies the `taskman` process info lines in the console log.
- Updated the `tm_procfs` selection and boundary docs to require the smoke.
- Marked the Phase 9 targeted-coverage task complete.

Commands:

- `bash -n scripts/procfs-smoke.sh`
- `make -n procfs-smoke container-procfs-smoke`
- `make procfs-smoke`

Result:

- The current C `tm_procfs` path has targeted boot coverage before any Rust
  taskman changes land.

Follow-up:

- Start the Phase 10 kernel reassessment decision record after the Phase 9
  stack lands.

## 2026-06-24 02:03 CEST - Procfs Boundary Designed

Scope:

- Added `TASK_MANAGER_PROCFS_BOUNDARY.md` for the selected task-manager pilot.
- Kept `tm_procfs.h` as the authoritative C ABI.
- Documented data ownership for callbacks, C strings, and caller-owned output
  buffers.
- Recorded failure behavior for path resolution, info formatting, and readdir.
- Defined the opt-in rollback flag shape `QSOE_RUST_TM_PROCFS`.
- Linked the boundary from the migration docs index and procfs selection doc.
- Marked the Phase 9 boundary-design task complete.

Commands:

- `gh issue view 29 --repo dmytro-yemelianov/qsoe-os-rust-handover --json number,title,body,state,labels,url`
- `sed -n '1,220p' libtaskman/include/tm_procfs.h`

Result:

- The boundary review preserves C as the default and keeps spawn, capability,
  relocation, loader, and LQ dispatch code outside the first Rust pilot.

Follow-up:

- Add targeted boot and `/proc` coverage before implementation.

## 2026-06-24 02:02 CEST - Task Manager Procfs Pilot Selected

Scope:

- Added `TASK_MANAGER_PROCFS.md` selecting portable `tm_procfs` as the first
  non-critical internal task-manager module.
- Documented why the module has no direct effect on initial process creation.
- Excluded LQ process table, connection context, open/read dispatch, spawn,
  dispatcher, and seL4 invocation code from the first pilot.
- Compared `tm_procfs` against other candidate modules from the inventory.
- Added required host-test and `/proc` smoke evidence for later implementation.
- Linked the selection from the migration docs index.
- Marked the Phase 9 module-selection task complete.

Commands:

- `sed -n '1,220p' libtaskman/src/tm_procfs.c`
- `sed -n '1,220p' lq/taskman/path/procfs.c`

Result:

- `tm_procfs` is selected because it is bounded, read-only, callback-driven,
  diagnostic logic and avoids spawn, capability, relocation, and loader paths.

Follow-up:

- Design the C/Rust boundary for the `tm_procfs` pilot.

## 2026-06-24 02:00 CEST - Task Manager Modules Inventoried

Scope:

- Added `TASK_MANAGER.md` for the Phase 9 task-manager readiness inventory.
- Split taskman code into portable `libtaskman`, LQ rootserver, and embedded
  archive boundaries.
- Separated pure logic and diagnostic candidates from spawn-critical,
  capability-critical, relocation-critical, and loader-critical paths.
- Identified portable `/proc` model code as the best next candidate because it
  is read-only diagnostic logic with no direct effect on initial process
  creation.
- Linked the inventory from the migration docs index.
- Marked the Phase 9 inventory task complete.

Commands:

- `find libtaskman lq/taskman -path '*/build/*' -prune -o -path '*/.git/*' -prune -o -type f \\( -name '*.c' -o -name '*.h' -o -name '*.S' -o -name 'Makefile' \\) -print | sort`
- `wc -l $(find libtaskman lq/taskman -path '*/build/*' -prune -o -path '*/.git/*' -prune -o -type f \\( -name '*.c' -o -name '*.h' -o -name '*.S' \\) -print | sort)`
- `rg -n "tm_cred|tm_procfs|tm_sysfs|tm_pathmgr|tm_cpio|tm_script|tm_syscfg|tm_elf|tm_reloc" libtaskman lq/taskman -g '*.c' -g '*.h'`

Result:

- The inventory documents that Phase 9 should avoid spawn, capability,
  relocation, and loader code until a later design review. `tm_procfs` is the
  leading non-critical internal module for selection.

Follow-up:

- Select one non-critical internal module for the first task-manager pilot.

## 2026-06-24 01:56 CEST - C Retirement Gate Documented

Scope:

- Added `RETIREMENT.md` to make the C removal gate explicit.
- Recorded the state model from C default through Rust opt-in, Rust-default RC,
  and retired.
- Listed the mandatory evidence for any future C removal PR.
- Recorded that `slogger`, `devb-virtio`, `pipe`, and `test_msgpass` are not
  currently retireable.
- Linked the gate from the migration docs index.
- Left the Phase 8 retirement task open because no component has completed a
  Rust-default release candidate with C rollback.

Commands:

- `rg -n "retire|remove|rollback|release candidate|default|C implementation|parity" docs/rust-migration docs -g '!build/**'`
- `gh issue view 26 --repo dmytro-yemelianov/qsoe-os-rust-handover --json number,title,body,state,labels,assignees,url`

Result:

- No C implementation was removed. Issue #26 is gated on release-candidate
  evidence rather than eligible for immediate retirement.

Follow-up:

- Start Phase 9 task-manager module inventory.

## 2026-06-24 01:53 CEST - First Rust Test Helper Selected

Scope:

- Added `TEST_HELPER.md` selecting `test_msgpass-rs` as the first Rust
  in-guest test helper candidate.
- Documented the existing C helper contract, IPC behavior, safety constraints,
  and Rust acceptance gates.
- Compared `test_msgpass` with `test_syncspace`; selected `test_msgpass`
  because it validates the bulk IPC path on QSOE/L today.
- Linked the selection from the migration docs index.
- Marked the Phase 8 test-helper selection task complete.

Commands:

- `sed -n '1,260p' quser/test/msgpass/main.c`
- `sed -n '450,560p' quser/test/suite/sync.c`
- `sed -n '1,260p' quser/test/suite/msgpass_test.c`

Result:

- `test_msgpass-rs` is selected for later implementation. The C helper remains
  the default `/usr/bin/test_msgpass` until an opt-in Rust artifact passes the
  existing suite `[msgpass]` section.

Follow-up:

- Define the proof period needed before retiring a C implementation.

## 2026-06-24 01:47 CEST - Pipe Selected As Second Rust Service

Scope:

- Added `PIPE.md` as the mini-spec for the selected second Rust service.
- Added `scripts/pipe-smoke.sh`, `make pipe-smoke`, and
  `make container-pipe-smoke` to verify the current C service starts and
  registers `/dev/pipe` before implementation.
- Documented current protocol, state model, rollback path, and later Rust
  acceptance gates.
- Linked the mini-spec from the migration docs index.
- Marked the Phase 8 second-service selection task complete.

Commands:

- `sed -n '1,380p' quser/sbin/pipe/main.c`
- `rg -n "pipe\\(|/dev/pipe|TM_REQ_PIPE_CREATE|PIPE_|pipe" quser libc libtaskman docs scripts -g '!build/**'`
- `make pipe-smoke`

Result:

- `pipe` is selected, but the existing C implementation remains the default.
  The new smoke reached login and confirmed `/dev/pipe` registration.

Follow-up:

- Pick the first Rust test helper.

## 2026-06-24 01:44 CEST - Remaining Userland Services Ranked

Scope:

- Added `SERVICE_RANKING.md` for Phase 8 candidate selection.
- Ranked remaining userland services by size, dependency, ABI surface,
  testability, and rollback scores.
- Excluded `slogger` and `devb-virtio` because they already have Rust pilots.
- Linked the ranking from the migration docs index.
- Marked the Phase 8 ranking task complete.

Commands:

- `find quser/build -type f -name '*.elf' -printf '%s %p\n'`
- `wc -l` over candidate service source files

Result:

- `pipe` is the best next service candidate, with `getty` and `login` close
  behind once focused login-path smoke coverage exists.

Follow-up:

- Use the ranking to pick the second Rust service and write its mini-spec.

## 2026-06-24 01:40 CEST - Parser Reused In Host And Guest Contexts

Scope:

- Reused `qsoe-cpio` from `qsoe-minimal-rs`, the no-std guest link-smoke
  binary.
- Added a static `newc` archive parser smoke that runs through the same
  borrowed `Archive` API used by host tests.
- Added a `host-tests` feature for `qsoe-minimal-rs` so the parser reuse path
  also runs under `cargo test`.
- Added the minimal binary host test to Rust workflow gates.
- Marked the Phase 7 parser reuse task complete.

Commands:

- `cargo test --manifest-path rust/Cargo.toml -p qsoe-minimal-rs --features host-tests`
- `cargo build --manifest-path rust/Cargo.toml -p qsoe-minimal-rs --target riscv64gc-unknown-none-elf --release`

Result:

- The same `qsoe-cpio` crate now builds and runs in host tests and compiles into
  the no-std guest smoke binary.

Follow-up:

- Start Phase 8 candidate ranking.

## 2026-06-24 01:35 CEST - ELF Inspection Crate Added

Scope:

- Added `qsoe-elf`, a dependency-free `no_std` crate for read-only ELF64
  little-endian header, section, and REL/RELA relocation inspection.
- Added RISC-V relocation naming for the relocation types used by QSOE
  userland artifacts.
- Added host tests for a synthetic ELF and for the representative built QSOE C
  binaries recorded in `ELF_BASELINE.md`.
- Added `make check-elf-reloc-fixture` and included it in the container check
  path after the source build.
- Added the crate to Rust workflow gates.
- Marked the Phase 7 ELF inspection task complete.

Commands:

- `cargo test --manifest-path rust/Cargo.toml -p qsoe-elf`
- `make check-elf-reloc-fixture`

Result:

- Host tests identify the existing QSOE binary relocation types and counts:
  `R_RISCV_64` and `R_RISCV_JUMP_SLOT` across the representative C userland
  artifacts.

Follow-up:

- Reuse one shared parser in both host and guest contexts next.

## 2026-06-24 01:05 CEST - Syscfg/Sysmap View Crate Added

Scope:

- Added `qsoe-sysview`, a dependency-free `no_std` crate for read-only
  `syscfg` and `sysmap` TLV views.
- Added bounds-checked scalar, string, range, timebase, cmdline, and generic TLV
  accessors.
- Covered malformed syscfg and sysmap inputs that truncate payloads, omit END
  tags, mis-size scalar/range fields, expose unterminated strings, or carry an
  invalid sysmap header.
- Added the crate to Rust workflow gates.
- Marked the Phase 7 syscfg/sysmap view task complete.

Commands:

- `cargo test --manifest-path rust/Cargo.toml -p qsoe-sysview`

Result:

- The crate exposes no raw struct references; callers receive typed values or
  borrowed payload slices only after the containing TLV and requested field
  bounds are validated.

Follow-up:

- Add ELF inspection coverage next.

## 2026-06-24 00:56 CEST - CPIO Parser Crate Added

Scope:

- Added `qsoe-cpio`, a dependency-free `no_std` crate for parsing `newc` CPIO
  archives.
- Covered valid archives, ordered iteration, lookup by index/name, archive
  info, and malformed header/name/data cases without panics.
- Added the crate to the normal Rust workflow gates.
- Marked the Phase 7 CPIO parser crate task complete.

Commands:

- `cargo test --manifest-path rust/Cargo.toml -p qsoe-cpio`

Result:

- `qsoe-cpio` parsed the valid fixture and rejected truncated, bad-magic,
  invalid-hex, zero-name-size, unterminated-name, invalid-UTF-8-name, and
  truncated-data fixtures through typed errors.

Follow-up:

- Add syscfg/sysmap read-only view coverage next.

## 2026-06-24 00:45 CEST - Rust Virtio File Access Smoke Added

Scope:

- Added `scripts/rust-virtio-file-smoke.sh` to boot with `devb-virtio-rs` and
  a temporary `/usr/conf/sysinit` fragment that runs inside the guest.
- Extended qrvfs image staging to include `/usr/conf/sysinit` fragments.
- Added `make rust-virtio-file-smoke` and a container wrapper.
- Marked the Phase 6 Rust virtio file-access smoke task complete.

Commands:

- `scripts/rust-virtio-file-smoke.sh -t 240 -o build/boot-smoke-lq-rust-virtio-file.log`
- `strings build/boot-smoke-lq-rust-virtio-file.log | rg "rust-virtio-file-smoke|devb-virtio-rs|fs-qrv: mounted|login:"`

Result:

- QEMU reached `login:` with `[devb-virtio-rs] /dev/vblk0 ready`,
  `fs-qrv: mounted qrvfs at /usr (dev=/dev/vblk0)`, and
  `rust-virtio-file-smoke: read /usr/conf/passwd ok` in the console log.

Follow-up:

- Continue Phase 7 shared-parser work.

## 2026-06-24 00:37 CEST - Rust Virtio Boot Smoke Passed

Scope:

- Added `scripts/rust-virtio-boot-smoke.sh` to build a temporary QSOE/L boot
  CPIO with `qsoe-devb-virtio-rs` installed as `/sbin/devb-virtio`.
- Added `QSOE_BOOT_VIRTIO_PATTERN` to `scripts/boot-smoke.sh` so the same boot
  gate can validate C or Rust virtio driver milestones.
- Added `make rust-virtio-boot-smoke` and a container wrapper.
- Marked the Phase 6 Rust virtio boot task complete.

Commands:

- `scripts/rust-virtio-boot-smoke.sh -t 240 -o build/boot-smoke-lq-rust-virtio.log`
- `strings build/boot-smoke-lq-rust-virtio.log | rg "devb-virtio-rs|fs-qrv: mounted|login:|dispatcher ready|spawning /sbin/init|\\[slogger\\] alive"`

Result:

- QEMU reached `login:` with `[devb-virtio-rs] /dev/vblk0 ready` and
  `fs-qrv: mounted qrvfs at /usr (dev=/dev/vblk0)` in the console log.

Follow-up:

- Run a file access smoke through `/usr` while booted with the Rust virtio
  driver.

## 2026-06-24 00:32 CEST - Opt-In Rust Virtio Driver Added

Scope:

- Added `qsoe-devb-virtio-rs`, a no-std Rust `devb-virtio` staticlib that
  discovers QEMU virtio-mmio block slots, initializes the legacy block queue,
  and publishes `/dev/vblk0` through `libressrv`.
- Added QSOE ABI errno/block-mode constants and FFI bindings needed by the
  driver (`munmap`, `sched_yield`).
- Extended the Rust link-smoke script with optional extra link flags/libs so
  Rust resource-server binaries can link `libressrv`.
- Added `make rust-virtio-link-smoke`, `make virtio-artifact`, and container
  wrappers; `QSOE_RUST_VIRTIO=0` keeps the C driver selected by default, while
  `QSOE_RUST_VIRTIO=1` stages the audited Rust ELF.
- Marked the Phase 6 opt-in Rust virtio block driver task complete.

Commands:

- `make rust-quality`
- `make rust-virtio-link-smoke`
- `QSOE_RUST_VIRTIO=1 make virtio-artifact`
- `make virtio-artifact`

Result:

- `build/rust/qsoe-devb-virtio-rs.elf` links as a QSOE RISC-V userland ELF and
  passes `scripts/audit-elf.sh --strict-qsoe-user`.
- The selected artifact path exists for both C-default and Rust opt-in modes.

Follow-up:

- Build an opt-in QSOE/L boot image with the Rust virtio artifact and verify
  `/dev/vblk0`, `/usr` mount, and login.

## 2026-06-24 00:20 CEST - Host-Side Virtqueue Tests Added

Scope:

- Added `DescriptorBuffer`, `DescriptorFreeList`, and queue errors to
  `qsoe-virtio` for fixed-size descriptor chain allocation without hardware.
- Mirrored the C driver's first-free descriptor map behavior.
- Added host tests for three-descriptor request chaining, exhaustion without
  partial consumption, device-owned chain rejection, reclaim, reuse, and double
  free rejection.
- Marked the Phase 6 host-side queue tests task complete.

Commands:

- `make rust-quality`

Result:

- Descriptor chaining and free-list behavior are covered by host-side Rust
  tests before implementing the opt-in Rust block driver.

Follow-up:

- Implement the opt-in Rust virtio block driver binary.

## 2026-06-24 00:16 CEST - Virtqueue Descriptor Model Added

Scope:

- Added C-compatible Rust virtqueue layouts to `qsoe-virtio`: descriptor,
  available ring, used ring, used element, and virtio-blk request header.
- Added `DescriptorIndex`, `DescriptorAccess`, `DescriptorOwner`, and
  `DescriptorModel` so descriptor bounds, device mutability, and
  driver/device ownership are represented explicitly.
- Added host tests for layout sizes, bounded descriptor ids, descriptor flag
  conversion, ownership transitions, and block request direction encoding.
- Marked the Phase 6 virtqueue descriptor model task complete.

Commands:

- `make rust-quality`

Result:

- The Rust virtio pilot has a typed descriptor model without adding allocator
  or free-list behavior yet.

Follow-up:

- Add host-side queue tests for descriptor chain allocation and free-list
  behavior.

## 2026-06-23 23:52 CEST - Virtio MMIO Wrapper Added

Scope:

- Added the `qsoe-virtio` crate with legacy virtio-mmio register constants and
  a `VirtioMmio` volatile register wrapper.
- Isolated volatile pointer reads and writes inside the wrapper; callers only
  provide the mapped register base through an unsafe constructor.
- Added host tests for device probing, register reads/writes, feature masking,
  config reads, and interrupt acknowledgement.
- Included `qsoe-virtio` in the Rust workspace, Rust README, and
  `make rust-quality`.
- Marked the Phase 6 volatile MMIO wrapper task complete.

Commands:

- `make rust-quality`

Result:

- Unsafe MMIO pointer access for the Rust virtio pilot is contained in one
  reviewed wrapper and covered by host tests.

Follow-up:

- Build the virtqueue descriptor model.

## 2026-06-23 23:44 CEST - Virtio Block Behavior Specified

Scope:

- Added `VIRTIO_BLOCK.md` to specify the current C `devb-virtio` behavior
  before starting the Rust driver pilot.
- Documented QEMU virtio-mmio discovery, DMA layout, legacy queue setup,
  request lifecycle, `/dev/vblk0` resource-server surface, and `/usr` mount
  dependency.
- Linked the new spec from the Rust migration README.
- Marked the Phase 6 current-behavior specification task complete.

Commands:

- `git diff --check`

Result:

- The Rust `devb-virtio-rs` pilot now has a concrete behavior contract and
  acceptance baseline.

Follow-up:

- Build typed volatile MMIO wrappers for the virtio-mmio register block.

## 2026-06-23 23:22 CEST - Wrapper State Tests Added

Scope:

- Added `DirectServer::dispatch_received`, the single receive-state dispatch
  step used by the direct-service run loop.
- Added host tests for message, pulse, and receive-error dispatch transitions
  without creating a live QSOE channel.
- Documented that host tests cover wrapper state transitions, while link and
  boot smokes cover QSOE IPC behavior.
- Marked the Phase 5 wrapper-level tests task complete.

Commands:

- `make rust-quality`
- `make container-rust-slogger-link-smoke`
- `make container-rust-service-example-link-smoke`

Result:

- Direct-service wrapper transitions are covered by the normal host test gate
  without requiring QEMU.

Follow-up:

- Start Phase 6 by specifying the current virtio block driver behavior.

## 2026-06-23 23:11 CEST - Error Mapping Defined

Scope:

- Added explicit Rust wrappers for the two existing QSOE status conventions:
  `ReplyStatus` for direct `MsgReply` labels and `MethodStatus` for
  resource-server method returns.
- Added host tests for positive direct errno labels, negative method errno
  results, and the `QSOE_DEFER` sentinel.
- Documented that Rust code preserves the current `0`/positive errno and
  `>=0`/`-errno`/defer ABI conventions.
- Marked the Phase 5 error-mapping task complete.

Commands:

- `make rust-quality`

Result:

- Direct-service and method-style Rust error mapping is explicit and covered
  by the normal host quality gate.

Follow-up:

- Add wrapper-level tests for state transitions and receive-loop behavior.

## 2026-06-23 23:01 CEST - Resource Server Example Documented

Scope:

- Turned `qsoe-service-example-rs` into a documented direct resource-server
  example with a named request classifier.
- Added `host-tests` feature coverage for lifecycle acknowledgements, write
  byte counts, read payload caps, and unsupported request handling.
- Included the example package in `make rust-quality` host tests.
- Marked the Phase 5 resource-server example task complete.

Commands:

- `make rust-quality`
- `make container-rust-service-example-link-smoke`

Result:

- The example compiles, documents its minimal request/reply loop, and links
  through the QSOE userland CRT/libc path.

Follow-up:

- Define common error mapping for Rust direct services.

## 2026-06-23 22:47 CEST - Direct Service Bootstrap Extracted

Scope:

- Added `DirectRequestHandler` and `DirectServer` to `qsoe-ressrv`.
- Moved `slogger-rs` onto the shared direct-service register, detach, and
  receive-loop path.
- Added `qsoe-service-example-rs`, a tiny service that uses the same wrapper
  path for connect, write, read, and close-style requests.
- Added a link-smoke target and Rust README note for the example service.
- Marked the Phase 5 common bootstrap task complete.

Commands:

- `make rust-quality`
- `make container-rust-slogger-link-smoke`
- `make container-rust-service-example-link-smoke`

Result:

- `slogger-rs` and the example service compile through the same direct-service
  bootstrap path.
- Both service binaries link through the QSOE userland CRT/libc path.

Follow-up:

- Expand the example into a documented resource-server sample.

## 2026-06-23 22:37 CEST - C And Rust Slogger Boot Logs Compared

Scope:

- Rebuilt and booted the default C `slogger` LQ image.
- Compared C boot milestones against the latest Rust `slogger-rs` boot-smoke
  log.
- Documented reviewed differences in `SLOGGER_BOOT_COMPARE.md`.
- Marked the Phase 4 boot-log comparison task complete.

Commands:

- `make -C quser cpio LIBC_SO=... RTLD_SO=... DYNLIBC_SO=...`
- `make -C lq`
- `scripts/boot-smoke.sh -k lq -t 180 -o build/boot-smoke-lq-c-compare.log`
- `strings build/boot-smoke-lq-c-compare.log | rg "slogger|fs-qrv: mounted|login:|devb-virtio|dispatcher ready|spawning /sbin/init"`
- `strings build/boot-smoke-lq-20260623-223518.log | rg "slogger|fs-qrv: mounted|login:|devb-virtio|dispatcher ready|spawning /sbin/init"`

Result:

- Both C and Rust boots reached login.
- Rust startup logs are shorter: no pid, chid, or ring-size text yet.
- Device, filesystem, and login milestones matched.

Follow-up:

- Decide whether pid/chid/ring-size startup parity is needed before replacing
  the default C service.

## 2026-06-23 22:35 CEST - Rust Slogger Boot Smoke Added

Scope:

- Added `make rust-slogger-boot-smoke`.
- Added a wrapper that builds an LQ modpkg archive with only
  `sbin/slogger` replaced by the selected Rust artifact.
- Rebuilt the LQ QEMU image with `MODPKG_CPIO` pointing at that opt-in archive.
- Let `boot-smoke.sh` accept a custom slogger startup pattern.
- Marked the Phase 4 Rust boot-image task complete.

Commands:

- `make rust-slogger-boot-smoke`

Result:

- QEMU reached login with `[slogger-rs] alive` in the console log.

Follow-up:

- Compare C and Rust boot logs before making the Rust service less
  experimental.

## 2026-06-23 22:28 CEST - Rust Slogger Build Flag Added

Scope:

- Added `QSOE_RUST_SLOGGER`, defaulting to the existing C `slogger`.
- Added `make slogger-artifact`, which stages the selected implementation at
  `build/rust/selected/sbin/slogger.elf`.
- Added `QSOE_RUST_SLOGGER=1 make slogger-artifact` for the Rust pilot.
- Kept CPIO and boot-image substitution for the next task.
- Marked the Phase 4 build-flag task complete.

Commands:

- `make slogger-artifact`
- `QSOE_RUST_SLOGGER=1 make slogger-artifact`
- `make container-slogger-artifact`
- `QSOE_RUST_SLOGGER=1 make container-slogger-artifact`

Result:

- The C service remains the default selected artifact.
- One explicit make variable selects the Rust `slogger-rs` artifact.

Follow-up:

- Use the selected artifact in an opt-in boot image and run the Rust `slogger`
  boot smoke.

## 2026-06-23 22:25 CEST - Rust Slogger Entry Point Added

Scope:

- Added `qsoe-slogger-rs`, a no-std staticlib that exports the QSOE userland
  `main(argc, argv, envp)` entry point.
- Registered `/dev/slog` through the direct resource-server wrapper.
- Wired `_IO_CONNECT`, `_IO_DUP`, close, write, read, and fstat handlers to the
  Rust slog ring.
- Added QSOE `EOK` and `ENOSYS` ABI constants.
- Parameterized the Rust QSOE link smoke helper and added
  `make rust-slogger-link-smoke`.
- Marked the Phase 4 service-entry-point task complete.

Commands:

- `make rust-quality`
- `make container-rust-qsoe-link-smoke`
- `make container-rust-slogger-link-smoke`
- `bash -n scripts/rust-qsoe-link-smoke.sh scripts/rust-workflow.sh scripts/rust-check.sh`

Result:

- `slogger-rs` links through the QSOE `crt0.o` and `libc.so` userland path.
- The link smoke strips inert unwind metadata before the strict ELF audit.
- The existing minimal Rust link smoke still passes with the parameterized
  script.
- The C `slogger` remains the default boot service.

Follow-up:

- Add the explicit build flag that selects Rust `slogger` for boot images.

## 2026-06-23 21:32 CEST - Rust Slogger Ring Added

Scope:

- Added the `qsoe-slogger` no-std crate.
- Implemented the byte-ring behavior needed by `slogger-rs`.
- Documented that the slog event header is the current 24-byte LP64 ABI layout,
  not the stale 16-byte wording in the ignored component header.
- Recorded that the stale `sys/slog.h` ring-size comment still needs an
  upstream component-source correction because `libc/` is ignored here.
- Added the crate to Rust workflow test coverage.
- Marked the Phase 4 Rust ring-buffer task complete.

Commands:

- `cargo test --manifest-path rust/Cargo.toml -p qsoe-slogger`
- `make rust-quality`
- `scripts/container-toolchain.sh run bash -lc 'cd rust && cargo check -p qsoe-slogger --target riscv64gc-unknown-none-elf'`
- RISC-V C layout probe for `qsoe_slog_event_t` with
  `riscv64-linux-gnu-gcc`.

Result:

- Host tests passed, including append, drain, wraparound, exact-full,
  drop-oldest eviction, oversized rejection, incomplete-event read guard, read
  caps, and corrupt head-event clamping during eviction.
- `qsoe-slogger` compiled for the RISC-V no-std target in the Debian
  container. The compile emitted the existing `f`/`d` target-feature warnings.

Follow-up:

- Add the `/dev/slog` readback smoke before replacing the C service.
- Correct the stale `libc/include/sys/slog.h` comments in the component source
  repository.

## 2026-06-23 21:25 CEST - Direct Resource-Server Wrapper Added

Scope:

- Added shared Rust ABI constants for the `_IO_*` resource-manager protocol.
- Added `tm_stat_t` as `qsoe_abi::TmStat`.
- Added a direct-service wrapper surface in `qsoe-ressrv` for the current
  `slogger` model: channel ownership, path registration, daemon-ready detach,
  receive, pulse detection, replies, and explicit shutdown.
- Added `IoRequest` and `IoReply` wire buffers for the `slogger` request/reply
  shape.
- Marked the Phase 3 `slogger` wrapper task complete.

Commands:

- `cargo check --manifest-path rust/Cargo.toml --workspace`
- `cargo test --manifest-path rust/Cargo.toml -p qsoe-abi -p qsoe-ressrv`
- `make rust-quality`
- `scripts/container-toolchain.sh run bash -lc 'cd rust && cargo check -p qsoe-ressrv --target riscv64gc-unknown-none-elf'`

Result:

- Host Rust quality checks passed.
- `qsoe-abi` and `qsoe-ressrv` layout and helper tests passed.
- `qsoe-ressrv` compiled for the RISC-V no-std target in the Debian
  container. The compile emitted the existing `f`/`d` target-feature warnings.

Follow-up:

- Implement the Rust `slogger` ring buffer with host tests before linking a
  `slogger-rs` binary.

## 2026-06-23 21:20 EEST - Linux Handover Written

Scope:

- Added `HANDOVER.md`.
- Linked it from the migration README.

Commands:

- `gh --version`
- `gh auth status`
- `git status -sb --untracked-files=all`
- `git remote -v`

Result:

- The active GitHub CLI account is `dmytro-yemelianov`.
- Current `origin` remains `https://gitlab.com/qsoe/os.git`.
- Handover now records Linux package setup, restore commands, validation state,
  caveats, and next tasks.

Follow-up:

- Create a private GitHub handover repository and push this snapshot without
  changing the GitLab `origin`.

## 2026-06-23 21:00 EEST - Rust Workflow Tiers Added

Scope:

- Added `WORKFLOW.md`.
- Added `scripts/rust-env.sh` for scoped Cargo target directories.
- Added `scripts/rust-workflow.sh`.
- Added Make targets for `rust-fast`, `rust-quality`, `rust-abi`, and
  `rust-deep`, plus container aliases.
- Added rust-analyzer to the Debian Rust toolchain component list.
- Added `rust/deny.toml` for the first Rust dependency policy gate.

Commands:

- `make rust-fast`
- `make rust-quality`
- `make check-qrvfs-rust-fixture`
- `make rust-deep`
- `cargo deny --manifest-path rust/Cargo.toml check -c rust/deny.toml`
- `make container-toolchain-build`
- `make container-check`
- `make container-rust-abi`
- `make -n rust-abi rust-deep container-rust-fast container-rust-quality`

Result:

- Rust workflow now has separate fast, normal-quality, ABI, and optional deep
  gates.
- Host and container Cargo artifacts no longer share the same default target
  directory.
- `rust-deep` exposed the missing cargo-deny policy; adding `rust/deny.toml`
  made the deep gate pass when cargo-deny is installed.
- The rebuilt Debian container image accepts the rust-analyzer component and
  passes `container-check`.
- Container Rust ABI smoke still links `build/rust/qsoe-minimal-rs.elf` with
  no TLS or unwind sections.

Follow-up:

- Revisit cargo-vet once third-party Rust dependencies appear.
- Add cargo-fuzz targets when qrvfs/GPT/ELF/CPIO parser work expands.

## 2026-06-23 21:00 EEST - C Indexing Workflow Added

Scope:

- Added `.clangd`.
- Added `scripts/c-index.sh`.
- Added C indexing Make targets.
- Added container wrapper commands for static C indexes and compile database
  capture.
- Added C indexing/analysis packages to the Debian toolchain image.
- Added `INDEXING.md`.

Commands:

- `docker run --rm debian:trixie ... apt-cache policy ...`
- `make container-toolchain-build`
- `make container-index-c-static`

Result:

- Debian Trixie provides ripgrep, Bear, clangd, clang-tidy, clang-tools,
  Universal Ctags, cscope, GNU Global, and jq.
- The workflow now separates fast static navigation from slower compile database
  capture.
- The rebuilt Debian image generated static C indexes for 816 QSOE-owned C/ASM
  files.

Follow-up:

- Capture a small compile database first, then decide whether a clean full-tree
  Bear capture is worth the time for the active refactoring pass.

## 2026-06-23 20:40 EEST - Rust qrvfs Host Inspector Added

Scope:

- Added `rust/crates/qsoe-qrvfs`.
- Added `qrvfs-tree`, a Rust tree-format inspector.
- Added `scripts/check-qrvfs-rust-fixture.sh`.
- Added `make check-qrvfs-rust-fixture`.
- Extended `make container-check` to include the Rust/C qrvfs comparison.

Commands:

- `make rust-check`
- `make check-qrvfs-rust-fixture`
- `make container-check`

Result:

- Rust parser unit tests passed.
- Rust `qrvfs-tree` output matched C `treeqrvfs` output byte-for-byte for the
  generated fixture.
- Debian container check passed with host fixtures, Rust checks, and qrvfs
  Rust/C comparison.

Follow-up:

- Keep `mkfs-qrv` as the image writer until a Rust writer has fixture and
  byte/semantic compatibility gates.

## 2026-06-23 20:40 EEST - C `slogger` Behavior Specified

Scope:

- Reviewed `quser/sbin/slogger/main.c`.
- Reviewed libc `slogf`/`slogb` event construction.
- Reviewed `sloginfo` and existing suite slog smoke.
- Added `SLOGGER.md`.

Commands:

- `sed -n '1,260p' quser/sbin/slogger/main.c`
- `sed -n '1,260p' libc/qsoe/slog.c`
- `sed -n '1,260p' libc/include/sys/slog.h`
- `sed -n '220,390p' libc/include/qsoe/tm_msgs.h`

Result:

- Current startup, ring, wire protocol, read/write/fstat/open/dup/close, client
  event format, and consumer behavior are documented.
- The implemented ring size is recorded as `64 KiB`.
- A stale `256 KiB` ring-size comment in `sys/slog.h` is recorded as a
  follow-up.
- The `/dev/slog` readback smoke remains open because the existing suite only
  checks `slogf` return values.

Follow-up:

- Add an automated `/dev/slog` write/readback smoke before implementing
  `slogger-rs`.

## 2026-06-23 20:04 EEST - C Userland ELF Baseline Captured

Scope:

- Added `scripts/capture-elf-baseline.sh`.
- Added `make elf-baseline`.
- Added `make container-elf-baseline`.
- Added `ELF_BASELINE.md`.
- Generated full raw audit output under `build/elf-baseline/`.

Commands:

- `scripts/container-toolchain.sh run scripts/capture-elf-baseline.sh --raw-dir build/elf-baseline`
- `make -n elf-baseline container-elf-baseline`

Result:

- Eight representative C userland artifacts were summarized:
  - `slogger`.
  - `devb-virtio`.
  - `fs-qrv`.
  - `qsh`.
  - `login`.
  - `test_msgpass`.
  - `test_syncspace`.
  - `suite`.
- Raw audit output totals 1,770 lines in ignored build output.
- All selected artifacts use `/lib/ld-qsoe.so.1` and `libc.so`.
- Relocations are within the current QSOE userland baseline.
- No selected C artifact uses TLS.
- All selected C artifacts include unwind-related sections.

Follow-up:

- Keep the first Rust userland gate stricter than the C baseline: no TLS and no
  unwind sections unless loader/runtime support is explicitly reviewed.

## 2026-06-23 19:59 EEST - Decision And Process Tracking Added

Scope:

- Added an explicit decision log.
- Added this chronological development log.
- Linked both from the migration README.

Commands:

- `date '+%Y-%m-%d %H:%M:%S %Z'`

Result:

- Decision tracking is now part of the repository docs.
- Future migration work has a stable place to record reasoning and evidence.

Follow-up:

- Keep adding decisions as `D-###` entries in `DECISIONS.md`.
- Keep adding process entries here whenever toolchain, build, boot, or artifact
  behavior changes.

## 2026-06-23 - Debian Container Toolchain Validated

Scope:

- Added `toolchains/debian/Dockerfile`.
- Added `scripts/container-toolchain.sh`.
- Added Make targets:
  - `container-toolchain-build`.
  - `container-shell`.
  - `container-check`.
  - `container-rust-qsoe-link-smoke`.
  - `container-source-build`.
- Documented the toolchain in `TOOLCHAIN.md`.

Commands:

- `colima start`
- `make container-toolchain-build`
- `scripts/container-toolchain.sh run bash -c 'python3 -c "import yaml, pyfdt.pyfdt, jinja2, ply, jsonschema, elftools"; rustc --version; riscv64-linux-gnu-gcc --version | head -1; qemu-system-riscv64 --version | head -1'`
- `make container-check`
- `make container-source-build`
- `make container-rust-qsoe-link-smoke`
- `scripts/container-toolchain.sh run bash -c 'QSOE_RUST_COMPILE=1 scripts/rust-check.sh'`
- `scripts/container-toolchain.sh run scripts/boot-smoke.sh -k lq -t 120`

Result:

- Container image built successfully.
- Tool versions observed:
  - Rust `1.95.0`.
  - Cargo `1.95.0`.
  - RISC-V GCC `14.2.0`.
  - GNU binutils `2.44`.
  - QEMU `10.0.8`.
  - Kconfiglib `14.1.0`.
  - PyYAML `6.0.2`.
  - Jinja2 `3.1.6`.
- `make container-check` passed.
- `make container-source-build` passed for NQ, quser, LQ, seL4, taskman, and
  the QSOE/L QEMU image.
- Rust link smoke passed and produced `build/rust/qsoe-minimal-rs.elf`.
- LQ boot smoke reached login from the container-built image.

Follow-up:

- Keep QEMU `11.0.1+` available outside this Debian image for NQ AIA boot
  experiments.

## 2026-06-23 - Container Toolchain Failures Resolved

Scope:

- Iterated on missing and incompatible Linux build dependencies.

Observed failures:

- macOS host reported `apt: command not found`.
- Initial local source build could not find `riscv64-linux-gnu-gcc`.
- Debian Bookworm cross tools rejected `-march=..._zicntr`.
- LQ seL4 CMake failed on missing Python modules:
  - `yaml`.
  - `pyfdt.pyfdt`.
  - `jinja2`.

Decisions:

- Use Debian/container source builds from macOS.
- Switch container base from Bookworm to Trixie.
- Add `python3-yaml`.
- Add `pyfdt` `0.3` from PyPI because Debian lacks `pyfdt.pyfdt`.
- Add seL4 Python generator dependencies from Debian packages.

Result:

- The next `make container-source-build` completed successfully.

Follow-up:

- If a future seL4 update adds more Python imports, prefer Debian packages
  first and document any PyPI fallback.

## 2026-06-23 - Rust Link Smoke Completed

Scope:

- Added a minimal Rust staticlib binary crate.
- Linked it through QSOE startup and libc.
- Audited the produced ELF.

Commands:

- `make container-rust-qsoe-link-smoke`

Result:

- Linked `build/rust/qsoe-minimal-rs.elf`.
- ELF shape:
  - `EXEC` RISC-V.
  - Interpreter `/lib/ld-qsoe.so.1`.
  - Needed library `libc.so`.
  - No TLS sections.
  - No unwind sections.
  - Relocations limited to current accepted userland baseline.
- Task backlog updated to mark minimal Rust link and audit gates complete.

Follow-up:

- The artifact is still a spike and is not installed into the default image.

## 2026-06-23 - Rust Workspace And ABI Spike Added

Scope:

- Added `rust/` workspace.
- Added pinned Rust toolchain configuration.
- Added Cargo configuration and QSOE RISC-V target file.
- Added crates:
  - `qsoe-abi`.
  - `qsoe-ffi`.
  - `qsoe-ressrv`.
  - `qsoe-minimal-rs`.

Commands:

- `make rust-check`
- `QSOE_RUST_COMPILE=1 scripts/rust-check.sh`

Result:

- Host Rust tests passed.
- RISC-V compile path passed once the container provided the toolchain.
- Layout assertions for QSOE and resource-server ABI structs passed.

Follow-up:

- Expand wrappers only after specifying the first real service behavior.

## 2026-06-23 - Safety Net Scripts Added

Scope:

- Added host fixture checks.
- Added boot smoke helper.
- Added ELF audit helper.
- Added Make targets for repeatable checks.

Commands:

- `make check-host-tools`
- `bash -n scripts/*.sh`
- `python3 -m py_compile scripts/check-gpt-fixture.py`

Result:

- qrvfs fixture check passed.
- GPT fixture check passed.
- Shell syntax checks passed.
- Python compile check passed.

Follow-up:

- Capture baseline ELF audit output for selected C userland binaries.

## 2026-06-23 - Migration Specs, Plan, And Backlog Written

Scope:

- Added migration documentation:
  - `README.md`.
  - `BASELINE.md`.
  - `HOST_TOOLS.md`.
  - `RUST_SPIKE.md`.
  - `BINDINGS.md`.
  - `SPEC.md`.
  - `PLAN.md`.
  - `TASKS.md`.

Decisions captured:

- No wholesale rewrite.
- Preserve C boot path and rollback.
- Start with baseline, fixtures, artifact audit, and minimal Rust spike.
- Prefer `slogger-rs` as the first in-guest service pilot.
- Defer libc, dynamic loader, task-manager loader paths, and kernels.

Result:

- Migration is now planned as incremental, evidence-driven work with acceptance
  criteria.

Follow-up:

- Start Phase 4 only after `slogger` behavior and `/dev/slog` smoke coverage
  are specified.

## 2026-06-23 - Baseline Boot And Source Context Reviewed

Scope:

- Reviewed cloned QSOE release components under the local umbrella tree.
- Recorded release component versions and commit SHAs.
- Reviewed local run modes and initial boot behavior.

Observed:

- Release components are checked out at detached release tags.
- QSOE/L boot reached user space and login.
- Known boot messages included seL4 untyped allocation warnings and missing RTC
  recognition.

Result:

- Baseline component SHAs and known boot warnings are documented in
  `BASELINE.md`.

Follow-up:

- Keep release tags stable while planning Rust migration.

## 2026-07-02 - tm_vspace_plan and tm_teardown_plan C Seam Evidence

- Added component patches for the `lq` taskman spawn vspace plan and process teardown plan seams.
- Added CI evidence scripts for bounded vspace mapping and teardown cleanup plans.
- Updated the spawn/cap-loader boundary review to move these two seams from roadmap candidates to evidenced C-owned boundaries.
