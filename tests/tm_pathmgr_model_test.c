/*
 * Host tests for the portable tm_pathmgr namespace model.
 *
 * These tests link the existing C implementation directly and capture the C
 * ABI/behavior before the Rust provider is wired into task-manager paths.
 */
#include <errno.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <tm_cpio.h>
#include <tm_pathmgr.h>

#define CHECK(expr) do { \
    if (!(expr)) { \
        fprintf(stderr, "%s:%d: check failed: %s\n", __FILE__, __LINE__, #expr); \
        exit(1); \
    } \
} while (0)

#define CHECK_STREQ(actual, expected) do { \
    if (strcmp((actual), (expected)) != 0) { \
        fprintf(stderr, "%s:%d: string mismatch\nexpected: <%s>\nactual:   <%s>\n", \
                __FILE__, __LINE__, (expected), (actual)); \
        exit(1); \
    } \
} while (0)

static tm_pathmgr_obj_t obj(pid_t pid, int chid, unsigned kind)
{
    tm_pathmgr_obj_t o;
    o.server_pid = pid;
    o.server_chid = chid;
    o.flags = 0xabc;
    o.handler_kind = kind;
    return o;
}

static void expect_resolve(const char *path, const tm_pathmgr_obj_t *expected,
                           unsigned expected_consumed)
{
    tm_pathmgr_obj_t out;
    unsigned consumed = 999;

    memset(&out, 0, sizeof out);
    CHECK(tm_pathmgr_resolve(path, &out, &consumed) == 0);
    CHECK(out.server_pid == expected->server_pid);
    CHECK(out.server_chid == expected->server_chid);
    CHECK(out.flags == expected->flags);
    CHECK(out.handler_kind == expected->handler_kind);
    CHECK(consumed == expected_consumed);
}

int tm_cpio_find_file(const uint8_t *data, uint64_t size,
                      const char *filename, tm_cpio_file_info_t *info)
{
    static const uint8_t etc_target[] = "/usr/conf";
    static const uint8_t bin_data[] = "x";

    (void)data;
    (void)size;
    if (!filename || !info) return 0;

    memset(info, 0, sizeof *info);
    if (strcmp(filename, "etc") == 0) {
        snprintf(info->filename, sizeof info->filename, "%s", filename);
        info->filesize = sizeof etc_target - 1U;
        info->mode = TM_CPIO_S_IFLNK;
        info->data = etc_target;
        return 1;
    }
    if (strcmp(filename, "bin") == 0) {
        snprintf(info->filename, sizeof info->filename, "%s", filename);
        info->filesize = sizeof bin_data - 1U;
        info->mode = 0100644U;
        info->data = bin_data;
        return 1;
    }
    return 0;
}

static void test_register_and_longest_prefix(void)
{
    tm_pathmgr_obj_t root = obj(1, 10, PATHMGR_HANDLER_TASKMAN_CPIOFS);
    tm_pathmgr_obj_t console = obj(2, 20, PATHMGR_HANDLER_EXTERNAL);

    tm_pathmgr_init();
    CHECK(tm_pathmgr_register("/", &root) == 0);
    CHECK(tm_pathmgr_register("/dev/console", &console) == 0);
    CHECK(tm_pathmgr_register("/dev/console", &console) == -EINVAL);

    expect_resolve("/bin/qsh", &root, 1);
    expect_resolve("/dev/console/extra", &console, 12);
    CHECK(tm_pathmgr_resolve("relative", &console, NULL) == -EINVAL);
}

static void test_pmdir_missing_child_remainder(void)
{
    tm_pathmgr_obj_t dev = obj(1, 30, PATHMGR_HANDLER_TASKMAN_PMDIR);

    tm_pathmgr_init();
    CHECK(tm_pathmgr_register("/dev", &dev) == 0);
    expect_resolve("/dev", &dev, 4);
    CHECK(tm_pathmgr_resolve("/dev/missing", &dev, NULL) == -ENOENT);
}

static void test_repath_and_unregister_external_only(void)
{
    tm_pathmgr_obj_t external = obj(42, 7, PATHMGR_HANDLER_EXTERNAL);
    tm_pathmgr_obj_t internal = obj(42, 8, PATHMGR_HANDLER_TASKMAN_CPIOFS);
    tm_pathmgr_obj_t replacement = obj(43, 9, PATHMGR_HANDLER_EXTERNAL);

    tm_pathmgr_init();
    CHECK(tm_pathmgr_register("/srv", &external) == 0);
    CHECK(tm_pathmgr_register("/boot", &internal) == 0);
    CHECK(tm_pathmgr_repath("/srv", &replacement) == 0);
    CHECK(tm_pathmgr_repath("/missing", &replacement) == -ENOENT);
    expect_resolve("/srv/file", &replacement, 4);

    CHECK(tm_pathmgr_unregister_pid(42) == 0);
    CHECK(tm_pathmgr_unregister_pid(43) == 1);
    CHECK(tm_pathmgr_resolve("/srv/file", &external, NULL) == -ENOENT);
    expect_resolve("/boot/init", &internal, 5);
}

static void test_symlink_resolve_and_expand(void)
{
    tm_pathmgr_obj_t console = obj(9, 2, PATHMGR_HANDLER_EXTERNAL);
    char expanded[64];

    tm_pathmgr_init();
    CHECK(tm_pathmgr_register("/dev/console", &console) == 0);
    CHECK(tm_pathmgr_symlink("/dev/tty", "/dev/console") == 0);
    CHECK(tm_pathmgr_symlink("/dev/tty", "/dev/console") == -EEXIST);
    expect_resolve("/dev/tty/session", &console, 8);

    memset(expanded, 0, sizeof expanded);
    CHECK(tm_pathmgr_expand_symlink("/dev/tty/session",
                                    expanded, sizeof expanded) == 1);
    CHECK_STREQ(expanded, "/dev/console/session");
    CHECK(tm_pathmgr_expand_symlink("/dev/tty/session", expanded, 8) == 0);

    CHECK(tm_pathmgr_symlink("/link2", "/dev/tty") == 0);
    CHECK(tm_pathmgr_resolve("/link2", &console, NULL) == -ENOENT);
}

static void test_cpio_symlink_expansion(void)
{
    uint8_t fake_cpio[1] = { 1 };
    char expanded[64];

    tm_pathmgr_init();
    memset(expanded, 0, sizeof expanded);
    CHECK(tm_pathmgr_expand_symlink_cpio(fake_cpio, sizeof fake_cpio,
                                         "/etc/passwd",
                                         expanded, sizeof expanded) == 1);
    CHECK_STREQ(expanded, "/usr/conf/passwd");
    CHECK(tm_pathmgr_expand_symlink_cpio(fake_cpio, sizeof fake_cpio,
                                         "/bin/qsh",
                                         expanded, sizeof expanded) == 0);
    CHECK(tm_pathmgr_expand_symlink_cpio(fake_cpio, sizeof fake_cpio,
                                         "/etc/passwd",
                                         expanded, 8) == 0);
}

static void test_child_order_and_truncation(void)
{
    tm_pathmgr_obj_t dev = obj(1, 1, PATHMGR_HANDLER_TASKMAN_PMDIR);
    char name[16];
    unsigned namelen = 0;

    tm_pathmgr_init();
    CHECK(tm_pathmgr_register("/dev", &dev) == 0);
    CHECK(tm_pathmgr_register("/dev/console", &dev) == 0);
    CHECK(tm_pathmgr_register("/dev/null", &dev) == 0);

    memset(name, 0, sizeof name);
    CHECK(tm_pathmgr_child_at("/dev", 0, name, sizeof name, &namelen) == 0);
    CHECK_STREQ(name, "null");
    CHECK(namelen == 4);

    memset(name, 0, sizeof name);
    CHECK(tm_pathmgr_child_at("/dev", 1, name, 5, &namelen) == 0);
    CHECK_STREQ(name, "cons");
    CHECK(namelen == 4);

    CHECK(tm_pathmgr_child_at("/dev", 2, name, sizeof name, &namelen) == -ENOENT);
    CHECK(tm_pathmgr_child_at("/missing", 0, name, sizeof name, &namelen) == -EINVAL);
}

int main(void)
{
    test_register_and_longest_prefix();
    test_pmdir_missing_child_remainder();
    test_repath_and_unregister_external_only();
    test_symlink_resolve_and_expand();
    test_cpio_symlink_expansion();
    test_child_order_and_truncation();

    puts("tm_pathmgr_model_test: ok");
    return 0;
}
