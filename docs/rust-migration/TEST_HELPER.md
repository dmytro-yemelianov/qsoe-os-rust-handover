# QSOE First Rust Test Helper Selection

Selected: 2026-06-24 01:53 CEST.
Opt-in helper validated: 2026-06-24 07:54 CEST.

The first Rust test helper candidate is `test_msgpass-rs`, a Rust replacement
for the current C helper:

```text
quser/test/msgpass/main.c -> /usr/bin/test_msgpass
```

The existing C helper remains the default and rollback path.

## Why `test_msgpass`

`test_msgpass` is the safest first Rust helper because it is:

- focused on IPC, not hardware
- spawned only by the conformance suite
- already staged into test images under `/usr/bin`
- one-shot: it receives one request, replies or intentionally exits, and is
  reaped by the suite
- useful on QSOE/L today for the main bulk IPC round trip

`test_syncspace` is a good later helper, but its cross-process sync-key check is
intentionally skipped on QSOE/L because that kernel model stores sync state in
caller memory and cannot use the unmapped numeric key that QSOE/N supports.

## Current C Contract

The suite's `[msgpass]` section:

1. `posix_spawn()`s `/usr/bin/test_msgpass`.
2. Waits for `/dev/msgpass` to appear in the path manager.
3. `ConnectAttach()`s directly to the helper channel.
4. Sends a 4 MiB minus 2 byte payload.
5. Expects a same-size reply where each 16-bit halfword is byte-swapped.
6. Reaps the helper after it exits.
7. Runs a `--no-reply` regression where the server exits with a client parked
   waiting for reply. QSOE/L currently skips the ESRVRFAULT assertion for that
   subcase.

The helper itself:

- allocates one 4 MiB receive buffer
- calls `ChannelCreate(0)`
- registers `/dev/msgpass`
- receives one message
- optionally exits without replying when invoked with `--no-reply`
- byte-swaps every 16-bit halfword in the payload
- replies with the transformed payload and exits

## Rust Helper Requirements

The Rust helper should be a no-std QSOE userland staticlib named
`qsoe-test-msgpass-rs`.

Required behavior:

- preserve `/usr/bin/test_msgpass` as the installed path for opt-in test images
- register exactly `/dev/msgpass`
- support the same normal mode and `--no-reply` mode
- preserve the 4 MiB minus 2 byte canonical payload behavior
- preserve odd-byte passthrough if a future caller sends an odd length
- exit after one receive path so the suite can `waitpid()` it

Implementation constraints:

- keep all IPC calls in the binary boundary through existing `qsoe-ffi`
  wrappers or narrow new wrappers
- keep the byte-swap transform as pure safe Rust over a validated slice
- allocate the 4 MiB receive buffer at runtime through libc `malloc`/`free`;
  keeping it in `.bss` overflows QSOE/L's current spawn frame table
- retry `/dev/msgpass` registration while taskman scrubs stale entries from the
  previous one-shot helper process
- do not change `suite/msgpass_test.c` until the Rust helper can be selected
  without altering the C default

## Opt-In Implementation

The implemented opt-in path keeps C as the default and stages the Rust helper
only when selected:

```sh
QSOE_RUST_TEST_MSGPASS=1 make test-msgpass-artifact
make rust-test-msgpass-link-smoke
make rust-test-msgpass-smoke
```

The smoke builds the helper with the LQ libc, places it at
`/usr/bin/test_msgpass` in a temporary qrvfs image, runs the existing suite, and
checks the `[msgpass]` markers. The wider suite still reports the current
unrelated QSOE/L sync failure; this smoke gates only the Rust-selected
`msgpass` section plus boot-to-login.

## Test-Image Safety

`test_msgpass-rs` is safe to include in test images because:

- it is not part of normal boot
- it is invoked by the suite only
- it owns no persistent global service path after exit
- it touches no hardware
- failure is contained to the suite result
- rollback is a single artifact selection back to the existing C helper

## Acceptance Status

Before any Rust helper is selected into a test image:

- the Rust binary links and passes the strict QSOE user ELF link smoke
- the C helper remains the default installed `/usr/bin/test_msgpass`
- an opt-in artifact selector stages `qsoe-test-msgpass-rs` at
  `/usr/bin/test_msgpass`
- the existing suite `[msgpass]` section passes with the Rust helper selected
- boot still reaches login after the test-image staging change
