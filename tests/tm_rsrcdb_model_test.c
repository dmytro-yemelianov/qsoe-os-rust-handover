/*
 * Host tests for LQ taskman's rsrcdb accounting model.
 *
 * The test includes the existing C implementation directly and supplies
 * host-side IPC/syscfg shims, so the Rust provider can be checked against the
 * behavior taskman currently ships.
 */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <sys/rsrcdbmgr.h>
#include <qsoe/syscfg.h>

#define QSOE_SEL4_TYPES_H
#define QSOE_SEL4_SYSCALLS_H
#define QSOE_INVOKE_H

typedef struct {
    unsigned long tag;
    unsigned long msg[QSOE_MSG_MAX_LENGTH];
    unsigned long userData;
    unsigned long caps_or_badges[QSOE_MSG_MAX_EXTRA_CAPS];
    unsigned long receiveCNode;
    unsigned long receiveIndex;
    unsigned long receiveDepth;
} qsoe_ipcbuf_t;

static qsoe_ipcbuf_t g_ipcbuf;
#define qsoe_ipcbuf (&g_ipcbuf)

static unsigned char g_syscfg[128];
static unsigned g_syscfg_len;
static int g_syscfg_ready = -1;

int tm_syscfg_get(const void **out_blob, unsigned *out_len)
{
    if (g_syscfg_ready != 0) return -1;
    if (out_blob) *out_blob = g_syscfg;
    if (out_len) *out_len = g_syscfg_len;
    return 0;
}

#include "../lq/taskman/sys/rsrcdb.c"

#define CHECK(expr) do { \
    if (!(expr)) { \
        fprintf(stderr, "%s:%d: check failed: %s\n", __FILE__, __LINE__, #expr); \
        exit(1); \
    } \
} while (0)

static rsrc_alloc_t *alloc_payload(void)
{
    return (rsrc_alloc_t *)&qsoe_ipcbuf->msg[4];
}

static rsrc_request_t *request_payload(void)
{
    return (rsrc_request_t *)&qsoe_ipcbuf->msg[4];
}

static void clear_payload(void)
{
    memset(&qsoe_ipcbuf->msg[4], 0, 116 * sizeof(unsigned long));
}

static void write_le16(unsigned off, uint16_t v)
{
    g_syscfg[off + 0] = (unsigned char)(v & 0xff);
    g_syscfg[off + 1] = (unsigned char)((v >> 8) & 0xff);
}

static void write_le64(unsigned off, uint64_t v)
{
    for (unsigned i = 0; i < 8; ++i) {
        g_syscfg[off + i] = (unsigned char)((v >> (i * 8)) & 0xff);
    }
}

static void set_syscfg_memory_pair(void)
{
    memset(g_syscfg, 0, sizeof g_syscfg);
    write_le16(0, TM_SYSCFG_TAG_MEMORY);
    write_le16(2, 16);
    write_le64(4, 0x1000);
    write_le64(12, 0x100);
    write_le16(20, TM_SYSCFG_TAG_MEMORY);
    write_le16(22, 16);
    write_le64(24, 0x1100);
    write_le64(32, 0x80);
    write_le16(40, TM_SYSCFG_TAG_END);
    write_le16(42, 0);
    g_syscfg_len = 44;
    g_syscfg_ready = 0;
}

static void test_layouts(void)
{
    CHECK(sizeof(unsigned long) == 8);
    CHECK(sizeof(rsrc_alloc_t) == 32);
    CHECK(sizeof(rsrc_request_t) == 56);
    CHECK(__builtin_offsetof(rsrc_request_t, length) == 0);
    CHECK(__builtin_offsetof(rsrc_request_t, align) == 8);
    CHECK(__builtin_offsetof(rsrc_request_t, start) == 16);
    CHECK(__builtin_offsetof(rsrc_request_t, end) == 24);
    CHECK(__builtin_offsetof(rsrc_request_t, flags) == 32);
    CHECK(__builtin_offsetof(rsrc_request_t, zero) == 36);
    CHECK(__builtin_offsetof(rsrc_request_t, name) == 48);
}

static void test_create_attach_detach_merge(void)
{
    unsigned written = 0;

    clear_payload();
    tm_rsrc_init();
    alloc_payload()[0] = (rsrc_alloc_t){
        .start = 100,
        .end = 199,
        .flags = RSRCDBMGR_MEMORY,
        .name = 0,
    };
    CHECK(tm_rsrc_create(7, 1) == 0);

    CHECK(tm_rsrc_query(0, 4, 0, RSRCDBMGR_MEMORY, &written) == 0);
    CHECK(written == 1);
    CHECK(alloc_payload()[0].start == 100);
    CHECK(alloc_payload()[0].end == 199);
    CHECK(alloc_payload()[0].flags == RSRCDBMGR_MEMORY);

    request_payload()[0] = (rsrc_request_t){
        .length = 16,
        .align = 16,
        .start = 120,
        .end = 180,
        .flags = RSRCDBMGR_MEMORY | RSRCDBMGR_FLAG_RANGE | RSRCDBMGR_FLAG_ALIGN,
    };
    CHECK(tm_rsrc_attach(42, 1) == 0);
    CHECK(request_payload()[0].start == 128);
    CHECK(request_payload()[0].end == 143);
    CHECK(request_payload()[0].length == 16);

    CHECK(tm_rsrc_query(0, 4, 0, RSRCDBMGR_MEMORY, &written) == 0);
    CHECK(written == 3);
    CHECK(alloc_payload()[0].start == 100 && alloc_payload()[0].end == 127);
    CHECK(alloc_payload()[1].start == 128 && alloc_payload()[1].end == 143);
    CHECK(alloc_payload()[1].flags == (RSRCDBMGR_MEMORY | RSRCDBMGR_FLAG_USED));
    CHECK(alloc_payload()[2].start == 144 && alloc_payload()[2].end == 199);

    request_payload()[0] = (rsrc_request_t){
        .start = 128,
        .end = 143,
        .flags = RSRCDBMGR_MEMORY,
    };
    CHECK(tm_rsrc_detach(42, 1) == 0);
    CHECK(tm_rsrc_query(0, 4, 0, RSRCDBMGR_MEMORY, &written) == 0);
    CHECK(written == 1);
    CHECK(alloc_payload()[0].start == 100);
    CHECK(alloc_payload()[0].end == 199);
}

static void test_attach_rollback(void)
{
    unsigned written = 0;

    clear_payload();
    tm_rsrc_init();
    alloc_payload()[0] = (rsrc_alloc_t){
        .start = 0,
        .end = 9,
        .flags = RSRCDBMGR_MEMORY,
    };
    CHECK(tm_rsrc_create(1, 1) == 0);

    request_payload()[0] = (rsrc_request_t){
        .length = 4,
        .align = 1,
        .flags = RSRCDBMGR_MEMORY,
    };
    request_payload()[1] = (rsrc_request_t){
        .length = 100,
        .align = 1,
        .flags = RSRCDBMGR_MEMORY,
    };
    CHECK(tm_rsrc_attach(22, 2) == -ENOSPC);
    CHECK(request_payload()[0].start == 0);
    CHECK(request_payload()[0].end == 3);

    CHECK(tm_rsrc_query(0, 4, 0, RSRCDBMGR_MEMORY, &written) == 0);
    CHECK(written == 1);
    CHECK(alloc_payload()[0].start == 0);
    CHECK(alloc_payload()[0].end == 9);
    CHECK(alloc_payload()[0].flags == RSRCDBMGR_MEMORY);
}

static void test_query_count_release_and_seed(void)
{
    unsigned written = 0;

    clear_payload();
    tm_rsrc_init();
    alloc_payload()[0] = (rsrc_alloc_t){
        .start = 0,
        .end = 31,
        .flags = RSRCDBMGR_MEMORY,
    };
    alloc_payload()[1] = (rsrc_alloc_t){
        .start = 100,
        .end = 199,
        .flags = RSRCDBMGR_MEMORY,
    };
    CHECK(tm_rsrc_create(1, 2) == 0);

    request_payload()[0] = (rsrc_request_t){
        .length = 8,
        .align = 1,
        .flags = RSRCDBMGR_MEMORY,
    };
    request_payload()[1] = (rsrc_request_t){
        .length = 8,
        .align = 1,
        .flags = RSRCDBMGR_MEMORY,
    };
    CHECK(tm_rsrc_attach(5, 2) == 0);

    request_payload()[0] = (rsrc_request_t){
        .length = 8,
        .align = 1,
        .flags = RSRCDBMGR_MEMORY,
    };
    CHECK(tm_rsrc_attach(6, 1) == 0);
    tm_rsrc_release_pid(5);

    CHECK(tm_rsrc_query(0, 0, 0, RSRCDBMGR_MEMORY, &written) == 0);
    CHECK(written == 4);
    CHECK(tm_rsrc_query(0, 8, 0, RSRCDBMGR_MEMORY, &written) == 0);
    CHECK(written == 4);
    CHECK(alloc_payload()[0].start == 0 && alloc_payload()[0].end == 15);
    CHECK(alloc_payload()[1].start == 16 && alloc_payload()[1].end == 23);
    CHECK(alloc_payload()[1].flags == (RSRCDBMGR_MEMORY | RSRCDBMGR_FLAG_USED));
    CHECK(alloc_payload()[2].start == 24 && alloc_payload()[2].end == 31);
    CHECK(alloc_payload()[3].start == 100 && alloc_payload()[3].end == 199);

    clear_payload();
    tm_rsrc_init();
    set_syscfg_memory_pair();
    tm_rsrc_seed_from_syscfg();
    CHECK(tm_rsrc_query(0, 8, 0, RSRCDBMGR_MEMORY, &written) == 0);
    CHECK(written == 2);
    CHECK(alloc_payload()[0].start == 0x1000);
    CHECK(alloc_payload()[0].end == 0x10ff);
    CHECK(alloc_payload()[1].start == 0x1100);
    CHECK(alloc_payload()[1].end == 0x117f);
}

static void test_error_paths(void)
{
    unsigned written = 0;

    clear_payload();
    tm_rsrc_init();
    alloc_payload()[0] = (rsrc_alloc_t){ .start = 0, .end = 1, .flags = 99 };
    CHECK(tm_rsrc_create(1, 1) == -EINVAL);
    CHECK(tm_rsrc_destroy(1, 1) == -EINVAL);

    request_payload()[0] = (rsrc_request_t){ .length = 1, .flags = 99 };
    CHECK(tm_rsrc_attach(1, 1) == -ENOSPC);
    CHECK(tm_rsrc_attach(1, 17) == -EINVAL);
    CHECK(tm_rsrc_detach(1, 1) == -EINVAL);
    CHECK(tm_rsrc_query(0, 1, 0, 99, &written) == -EINVAL);
}

int main(void)
{
    test_layouts();
    test_create_attach_detach_merge();
    test_attach_rollback();
    test_query_count_release_and_seed();
    test_error_paths();
    puts("tm_rsrcdb_model_test: ok");
    return 0;
}
