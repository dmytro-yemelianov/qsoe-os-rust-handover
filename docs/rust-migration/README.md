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
18. `SLOGGER_RC.md`: Rust-default `slogger` release-candidate note and C
   rollback drill.
19. `VIRTIO_BLOCK.md`: current C `devb-virtio` behavior and Rust pilot
   acceptance contract.
20. `VIRTIO_RC.md`: Rust-default `devb-virtio` release-candidate note and C
   rollback drill.
21. `SERVICE_RANKING.md`: remaining userland service scores for Phase 8
   selection.
22. `PIPE.md`: selected second Rust service mini-spec and C registration smoke.
23. `PIPE_RC.md`: Rust-default `pipe` release-candidate note and C rollback
   drill.
24. `TEST_HELPER.md`: selected first Rust in-guest test helper and safety
   constraints.
25. `TEST_MSGPASS_RC.md`: Rust-default `test_msgpass` test-image
   release-candidate note and C rollback drill.
26. `RETIREMENT.md`: C removal gate, current retirement status, and future
   removal checklist.
27. `STATUS.md`: current C default, Rust opt-in, Rust default, and retired
   status for tracked migration components.
28. `RELEASE_NOTE_TEMPLATE.md`: release-note template for implementation
   language changes, rollback flags, evidence, and known limitations.
29. `TASK_MANAGER.md`: task-manager module inventory for Phase 9 candidate
   selection.
30. `TASK_MANAGER_PROCFS.md`: selected non-critical task-manager pilot module
   and scope exclusions.
31. `TASK_MANAGER_PROCFS_BOUNDARY.md`: C/Rust ABI, failure behavior, and
   rollback plan for the selected pilot.
32. `TASK_MANAGER_PROCFS_RC.md`: Rust-default `tm_procfs` release-candidate
   note and C rollback drill.
33. `TASK_MANAGER_CPIO.md`: Rust opt-in task-manager CPIO archive provider
   and evidence gate.
34. `TASK_MANAGER_SCRIPT.md`: Rust opt-in task-manager shebang parser provider
   and evidence gate.
35. `TASK_MANAGER_SYSCFG.md`: Rust opt-in task-manager syscfg TLV provider
   and evidence gate.
36. `TASK_MANAGER_CRED.md`: Rust opt-in task-manager credential policy
   provider and evidence gate.
37. `TASK_MANAGER_PSEUDODEV.md`: Rust opt-in LQ task-manager `/dev/null` and
   `/dev/zero` provider and evidence gate.
38. `TASK_MANAGER_SYSFS.md`: Rust opt-in task-manager `/sys` provider and
   evidence gate.
39. `KERNEL_CANDIDATES.md`: Phase 10 kernel candidate inventory, explicit
   exclusions, and fixture-only ranking.
40. `KERNEL_ARTIFACT_AUDIT.md`: Phase 10 kernel Rust artifact audit needs.
41. `SPEC.md`: technical constraints, allowed boundaries, runtime/linking rules,
   and acceptance standards.
42. `PLAN.md`: phased migration plan from baseline validation through possible
   kernel reassessment.
43. `TASKS.md`: executable backlog with acceptance criteria.

The first implementation milestone should not be a subsystem rewrite. It should
be a reproducible baseline plus artifact audit, followed by a minimal Rust
toolchain spike and an opt-in `slogger-rs` pilot.
