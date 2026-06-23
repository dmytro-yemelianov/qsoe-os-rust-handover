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
6. `TOOLCHAIN.md`: Debian container toolchain for source builds and Rust link
   smokes.
7. `INDEXING.md`: C source indexing, compile database, and clangd workflow.
8. `ELF_BASELINE.md`: representative C userland ELF baseline for Rust
   comparison.
9. `RUST_SPIKE.md`: Rust toolchain scaffold and minimal link-smoke contract.
10. `BINDINGS.md`: current Rust ABI, FFI, and resource-server binding scope.
11. `WORKFLOW.md`: Rust edit-loop, quality, ABI, and deep-check workflow.
12. `SLOGGER.md`: current C `slogger` behavior and Rust pilot acceptance.
13. `SLOGGER_BOOT_COMPARE.md`: C vs Rust `slogger` boot-log comparison.
14. `VIRTIO_BLOCK.md`: current C `devb-virtio` behavior and Rust pilot
   acceptance contract.
15. `SERVICE_RANKING.md`: remaining userland service scores for Phase 8
   selection.
16. `PIPE.md`: selected second Rust service mini-spec and C registration smoke.
17. `TEST_HELPER.md`: selected first Rust in-guest test helper and safety
   constraints.
18. `RETIREMENT.md`: C removal gate, current retirement status, and future
   removal checklist.
19. `SPEC.md`: technical constraints, allowed boundaries, runtime/linking rules,
   and acceptance standards.
20. `PLAN.md`: phased migration plan from baseline validation through possible
   kernel reassessment.
21. `TASKS.md`: executable backlog with acceptance criteria.

The first implementation milestone should not be a subsystem rewrite. It should
be a reproducible baseline plus artifact audit, followed by a minimal Rust
toolchain spike and an opt-in `slogger-rs` pilot.
