# QSOE Rust Migration Docs

This directory collects the planning material for introducing Rust into QSOE
incrementally, without changing the current boot contract by surprise.

Read in this order:

1. `BASELINE.md`: release SHAs, run modes, smoke-test contract, and known
   boot warnings.
2. `DECISIONS.md`: accepted decisions, rationale, consequences, and
   verification.
3. `DEVLOG.md`: chronological development process, commands, outcomes, and
   follow-up.
4. `HANDOVER.md`: Linux migration handover, restore commands, validation state,
   and next work.
5. `HOST_TOOLS.md`: host-tool behavior and generated fixture checks.
6. `TREEQRVFS_RC.md`: Rust-default host `treeqrvfs` inspector
   release-candidate note and C rollback drill.
7. `MKFS_QRV_RC.md`: Rust-default host `mkfs-qrv-rs` writer
   release-candidate note and C rollback drill.
8. `TOOLCHAIN.md`: Debian container toolchain for source builds and Rust link
   smokes.
9. `INDEXING.md`: C source indexing, compile database, and clangd workflow.
10. `INVENTORY.md`: OS-wide C inventory, issue-backed migration ledger, and
   remaining translation buckets.
11. `ELF_BASELINE.md`: representative C userland ELF baseline for Rust
   comparison.
12. `RUST_SPIKE.md`: Rust toolchain scaffold and minimal link-smoke contract.
13. `BINDINGS.md`: current Rust ABI, FFI, and resource-server binding scope.
14. `WORKFLOW.md`: Rust edit-loop, quality, ABI, and deep-check workflow.
15. `UNSAFE_REVIEW.md`: unsafe-code review checklist for Rust migration PRs.
16. `SLOGGER.md`: current C `slogger` behavior and Rust pilot acceptance.
17. `SLOGGER_BOOT_COMPARE.md`: C vs Rust `slogger` boot-log comparison.
18. `SLOGGER_RC.md`: historical Rust-default `slogger` release-candidate note
   and C rollback drill.
19. `SLOGGER_RETIREMENT.md`: C service retirement note for `slogger`,
   including the Rust-only image path and removed rollback.
20. `VIRTIO_BLOCK.md`: current C `devb-virtio` behavior and Rust pilot
   acceptance contract.
21. `VIRTIO_RC.md`: Rust-default `devb-virtio` release-candidate note and C
   rollback drill.
22. `SERVICE_RANKING.md`: remaining userland service scores for Phase 8
   selection.
23. `PIPE.md`: selected second Rust service mini-spec, RC history, and
   retirement status.
24. `PIPE_RC.md`: historical Rust-default `pipe` release-candidate note and C
   rollback drill.
25. `PIPE_RETIREMENT.md`: C service retirement note for `pipe`, including the
   Rust-only image path and removed rollback.
26. `TEST_HELPER.md`: selected first Rust in-guest test helper and safety
   constraints.
27. `TEST_MSGPASS_RC.md`: historical Rust-default `test_msgpass` test-image
   release-candidate note and C rollback drill.
28. `TEST_MSGPASS_RETIREMENT.md`: first C helper retirement note for
   `test_msgpass`, including the Rust-only image path and removed rollback.
29. `RETIREMENT.md`: C removal gate, current retirement status, and future
   removal checklist.
30. `STATUS.md`: current C default, Rust opt-in, Rust default, and retired
   status for tracked migration components.
31. `RELEASE_NOTE_TEMPLATE.md`: release-note template for implementation
   language changes, rollback flags, evidence, and known limitations.
32. `TASK_MANAGER.md`: task-manager module inventory for Phase 9 candidate
   selection.
33. `TASK_MANAGER_PROCFS.md`: selected non-critical task-manager pilot module
   and scope exclusions.
34. `TASK_MANAGER_PROCFS_BOUNDARY.md`: C/Rust ABI, failure behavior, and
   rollback plan for the selected pilot.
35. `TASK_MANAGER_PROCFS_RC.md`: Rust-default `tm_procfs` release-candidate
   note and C rollback drill.
36. `TASK_MANAGER_CPIO.md`: Rust opt-in task-manager CPIO archive provider
   and evidence gate.
37. `TASK_MANAGER_SCRIPT.md`: Rust opt-in task-manager shebang parser provider
   and evidence gate.
38. `TASK_MANAGER_SYSCFG.md`: Rust opt-in task-manager syscfg TLV provider
   and evidence gate.
39. `TASK_MANAGER_CRED.md`: Rust opt-in task-manager credential policy
   provider and evidence gate.
40. `TASK_MANAGER_PSEUDODEV.md`: Rust opt-in LQ task-manager `/dev/null` and
   `/dev/zero` provider and evidence gate.
41. `TASK_MANAGER_RSRCDB.md`: Rust opt-in LQ task-manager resource DB
   provider and evidence gate.
42. `TASK_MANAGER_SYSFS.md`: Rust opt-in task-manager `/sys` provider and
   evidence gate.
43. `TASK_MANAGER_ELF.md`: Rust opt-in task-manager ELF view parser provider
   and evidence gate.
44. `TASK_MANAGER_FDT.md`: Rust opt-in LQ task-manager FDT parser provider and
   evidence gate.
45. `TASK_MANAGER_SYSMAP.md`: Rust opt-in LQ task-manager sysmap page builder
   and evidence gate.
46. `TASK_MANAGER_PATHMGR.md`: Rust opt-in task-manager path registry provider
   and evidence gate.
47. `KERNEL_CANDIDATES.md`: Phase 10 kernel candidate inventory, explicit
   exclusions, and fixture-only ranking.
47. `KERNEL_ARTIFACT_AUDIT.md`: Phase 10 kernel Rust artifact audit needs.
48. `SPEC.md`: technical constraints, allowed boundaries, runtime/linking rules,
   and acceptance standards.
49. `PLAN.md`: phased migration plan from baseline validation through possible
   kernel reassessment.
50. `TASKS.md`: executable backlog with acceptance criteria.

The first implementation milestone should not be a subsystem rewrite. It should
be a reproducible baseline plus artifact audit, followed by a minimal Rust
toolchain spike and an opt-in `slogger-rs` pilot.
