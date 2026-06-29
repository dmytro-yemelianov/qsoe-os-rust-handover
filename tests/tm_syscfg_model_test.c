/*
 * Host tests for libtaskman's portable syscfg TLV builder/walker.
 *
 * These tests link the existing C implementation directly and capture the C
 * ABI/behavior before the Rust provider is wired into task-manager paths.
 */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <tm_syscfg.h>

#define CHECK(expr) do { \
    if (!(expr)) { \
        fprintf(stderr, "%s:%d: check failed: %s\n", __FILE__, __LINE__, #expr); \
        exit(1); \
    } \
} while (0)

#define CHECK_MEMEQ(actual, expected, n) do { \
    if (memcmp((actual), (expected), (n)) != 0) { \
        fprintf(stderr, "%s:%d: memory mismatch\n", __FILE__, __LINE__); \
        exit(1); \
    } \
} while (0)

static void test_emit_find_get(void)
{
    unsigned char buf[64];
    tm_syscfg_state_t state;
    const void *blob = 0;
    unsigned blob_len = 0;
    const void *model = 0;
    unsigned model_len = 0;
    uint32_t version = 0;
    uint64_t timebase = 0;

    memset(buf, 0, sizeof buf);
    tm_syscfg_init(&state, buf, sizeof buf);
    CHECK(tm_syscfg_emit_u32(&state, TM_SYSCFG_TAG_VERSION, 1) == 0);
    CHECK(tm_syscfg_emit_asciz(&state, TM_SYSCFG_TAG_MODEL, "qemu-virt") == 0);
    CHECK(tm_syscfg_emit_u64(&state, TM_SYSCFG_TAG_TIMEBASE_HZ, 10000000ULL) == 0);
    CHECK(tm_syscfg_finalize(&state) == 0);
    CHECK(state.ready == 1);

    CHECK(tm_syscfg_get(&state, &blob, &blob_len) == 0);
    CHECK(blob == buf);
    CHECK(blob_len == state.len);
    CHECK(tm_syscfg_find_u32(&state, TM_SYSCFG_TAG_VERSION, &version) == 0);
    CHECK(tm_syscfg_find_u64(&state, TM_SYSCFG_TAG_TIMEBASE_HZ, &timebase) == 0);
    CHECK(version == 1);
    CHECK(timebase == 10000000ULL);

    CHECK(tm_syscfg_find(&state, TM_SYSCFG_TAG_MODEL, &model, &model_len) == 0);
    CHECK(model_len == 10);
    CHECK_MEMEQ(model, "qemu-virt", 10);
}

static void test_empty_asciz_skipped(void)
{
    unsigned char buf[16];
    tm_syscfg_state_t state;

    memset(buf, 0, sizeof buf);
    tm_syscfg_init(&state, buf, sizeof buf);
    CHECK(tm_syscfg_emit_asciz(&state, TM_SYSCFG_TAG_MODEL, 0) == 0);
    CHECK(tm_syscfg_emit_asciz(&state, TM_SYSCFG_TAG_MODEL, "") == 0);
    CHECK(state.len == 0);
}

static void test_bounds_ready_and_finalize(void)
{
    unsigned char small[7];
    unsigned char exact[8];
    unsigned char enough[12];
    tm_syscfg_state_t state;

    tm_syscfg_init(&state, small, sizeof small);
    CHECK(tm_syscfg_emit_u32(&state, TM_SYSCFG_TAG_VERSION, 1) == -1);
    CHECK(state.len == 0);

    tm_syscfg_init(&state, exact, sizeof exact);
    CHECK(tm_syscfg_emit_u32(&state, TM_SYSCFG_TAG_VERSION, 1) == 0);
    CHECK(tm_syscfg_finalize(&state) == -1);
    CHECK(state.ready == 0);

    tm_syscfg_init(&state, enough, sizeof enough);
    CHECK(tm_syscfg_emit_u32(&state, TM_SYSCFG_TAG_VERSION, 1) == 0);
    CHECK(tm_syscfg_finalize(&state) == 0);
    CHECK(tm_syscfg_emit_u32(&state, TM_SYSCFG_TAG_VERSION, 2) == -1);
    CHECK(tm_syscfg_finalize(&state) == 0);
}

static void test_raw_null_payload(void)
{
    unsigned char buf[16];
    unsigned char expected_header[4] = { 9, 0, 3, 0 };
    tm_syscfg_state_t state;

    memset(buf, 0x5a, sizeof buf);
    tm_syscfg_init(&state, buf, sizeof buf);
    CHECK(tm_syscfg_emit(&state, 9, 0, 3) == 0);
    CHECK_MEMEQ(buf, expected_header, sizeof expected_header);
    CHECK(buf[4] == 0x5a);
    CHECK(buf[5] == 0x5a);
    CHECK(buf[6] == 0x5a);
    CHECK(state.len == 7);
}

static void test_malformed_matching_payload_len(void)
{
    unsigned char buf[4] = { 10, 0, 20, 0 };
    tm_syscfg_state_t state;
    const void *ptr = 0;
    unsigned len = 0;

    state.buf = buf;
    state.cap = sizeof buf;
    state.len = sizeof buf;
    state.ready = 1;

    CHECK(tm_syscfg_find(&state, 10, &ptr, &len) == 0);
    CHECK(ptr == buf + 4);
    CHECK(len == 20);
}

static void test_typed_find_rejects_wrong_lengths(void)
{
    unsigned char buf[32];
    unsigned char raw[3] = { 1, 2, 3 };
    tm_syscfg_state_t state;
    uint32_t out32 = 0xfeedbeefU;
    uint64_t out64 = 0xfeedbeefdeadbeefULL;

    tm_syscfg_init(&state, buf, sizeof buf);
    CHECK(tm_syscfg_emit(&state, TM_SYSCFG_TAG_VERSION, raw, sizeof raw) == 0);
    CHECK(tm_syscfg_finalize(&state) == 0);

    CHECK(tm_syscfg_find_u32(&state, TM_SYSCFG_TAG_VERSION, &out32) == -1);
    CHECK(tm_syscfg_find_u64(&state, TM_SYSCFG_TAG_TIMEBASE_HZ, &out64) == -1);
    CHECK(out32 == 0xfeedbeefU);
    CHECK(out64 == 0xfeedbeefdeadbeefULL);
}

int main(void)
{
    test_emit_find_get();
    test_empty_asciz_skipped();
    test_bounds_ready_and_finalize();
    test_raw_null_payload();
    test_malformed_matching_payload_len();
    test_typed_find_rejects_wrong_lengths();
    puts("tm_syscfg_model_test: ok");
    return 0;
}
