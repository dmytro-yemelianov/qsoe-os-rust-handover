/*
 * Host tests for the portable tm_procfs model.
 *
 * These tests link the existing C implementation directly and exercise the
 * documented C ABI before a Rust provider is wired into task-manager paths.
 */
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <tm_procfs.h>

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

static const struct tm_procfs_proc fixture_procs[] = {
    { 1, 0, 0, "init" },
    { 7, 1, 1, "worker-z" },
    { 42, 1, 0, "1234567890123456789012345678901" },
};

static int dropped_pid;

static int fixture_get(int pid, struct tm_procfs_proc *out)
{
    size_t i;
    if (pid == dropped_pid)
        return 0;
    for (i = 0; i < sizeof(fixture_procs) / sizeof(fixture_procs[0]); i++) {
        if (fixture_procs[i].pid == pid) {
            *out = fixture_procs[i];
            return 1;
        }
    }
    return 0;
}

static int fixture_next(int from, struct tm_procfs_proc *out)
{
    size_t i;
    for (i = 0; i < sizeof(fixture_procs) / sizeof(fixture_procs[0]); i++) {
        if (fixture_procs[i].pid == dropped_pid)
            continue;
        if (fixture_procs[i].pid >= from) {
            *out = fixture_procs[i];
            return fixture_procs[i].pid;
        }
    }
    return 0;
}

static void reset_callbacks(void)
{
    dropped_pid = 0;
    tm_procfs_init(fixture_get, fixture_next);
}

static void expect_resolve(const char *path, int expected_kind, int expected_pid)
{
    int pid = -99;
    int kind = tm_procfs_resolve(path, &pid);
    CHECK(kind == expected_kind);
    if (expected_kind == 2 || expected_kind == 3)
        CHECK(pid == expected_pid);
}

static void test_path_resolution(void)
{
    reset_callbacks();

    expect_resolve("/proc", 1, 0);
    expect_resolve("/proc/", 1, 0);
    expect_resolve("/proc/1", 2, 1);
    expect_resolve("/proc/1/", 2, 1);
    expect_resolve("/proc/1/info", 3, 1);
    CHECK(tm_procfs_resolve("/proc/42/info", NULL) == 3);
    CHECK(tm_procfs_path_exists("/proc/7/info") != 0);

    expect_resolve("proc", 0, 0);
    expect_resolve("/procx", 0, 0);
    expect_resolve("/proc//1", 0, 0);
    expect_resolve("/proc/-1", 0, 0);
    expect_resolve("/proc/x", 0, 0);
    expect_resolve("/proc/1x", 0, 0);
    expect_resolve("/proc/2147483648", 0, 0);
    expect_resolve("/proc/2", 0, 0);
    expect_resolve("/proc/1/stat", 0, 0);
    expect_resolve("/proc/1/info/", 0, 0);
    CHECK(tm_procfs_path_exists("/proc/2/info") == 0);
}

static void test_info_formatting(void)
{
    char buf[TM_PROCFS_INFO_MAX];
    unsigned n;

    reset_callbacks();

    memset(buf, 0, sizeof(buf));
    n = tm_procfs_info(1, buf, sizeof(buf));
    CHECK(n == strlen("pid: 1\nppid: 0\nstate: alive\nname: init\n"));
    buf[n] = '\0';
    CHECK_STREQ(buf, "pid: 1\nppid: 0\nstate: alive\nname: init\n");

    memset(buf, 0, sizeof(buf));
    n = tm_procfs_info(7, buf, sizeof(buf));
    CHECK(n == strlen("pid: 7\nppid: 1\nstate: zombie\nname: worker-z\n"));
    buf[n] = '\0';
    CHECK_STREQ(buf, "pid: 7\nppid: 1\nstate: zombie\nname: worker-z\n");

    memset(buf, 0, sizeof(buf));
    n = tm_procfs_info(42, buf, sizeof(buf));
    CHECK(n == strlen("pid: 42\nppid: 1\nstate: alive\nname: 1234567890123456789012345678901\n"));
    buf[n] = '\0';
    CHECK_STREQ(buf, "pid: 42\nppid: 1\nstate: alive\nname: 1234567890123456789012345678901\n");

    CHECK(tm_procfs_info(1, buf, TM_PROCFS_INFO_MAX - 1) == 0);
    CHECK(tm_procfs_info(99, buf, sizeof(buf)) == 0);
}

static void expect_root_entry(unsigned long *cursor, const char *name,
                              unsigned long next_cursor)
{
    char entry[32];
    unsigned namelen = 0;
    int d_type = 0;

    memset(entry, 0, sizeof(entry));
    CHECK(tm_procfs_readdir_root(cursor, entry, &namelen, &d_type) == 1);
    CHECK_STREQ(entry, name);
    CHECK(namelen == strlen(name));
    CHECK(d_type == TM_PROCFS_DT_DIR);
    CHECK(*cursor == next_cursor);
}

static void test_readdir_root(void)
{
    unsigned long cursor = 0;
    char entry[32];
    unsigned namelen = 1234;
    int d_type = -1;

    reset_callbacks();

    expect_root_entry(&cursor, "1", 2);
    expect_root_entry(&cursor, "7", 8);
    expect_root_entry(&cursor, "42", 43);
    CHECK(tm_procfs_readdir_root(&cursor, entry, &namelen, &d_type) == 0);
    CHECK(cursor == 43);
}

static void test_readdir_piddir(void)
{
    char entry[8];
    unsigned namelen = 0;
    int d_type = 0;

    memset(entry, 0, sizeof(entry));
    CHECK(tm_procfs_readdir_piddir(0, entry, &namelen, &d_type) == 1);
    CHECK_STREQ(entry, "info");
    CHECK(namelen == 4);
    CHECK(d_type == TM_PROCFS_DT_REG);
    CHECK(tm_procfs_readdir_piddir(1, entry, &namelen, &d_type) == 0);
    CHECK(tm_procfs_readdir_piddir(ULONG_MAX, entry, &namelen, &d_type) == 0);
}

static void test_missing_callbacks(void)
{
    char buf[TM_PROCFS_INFO_MAX];
    unsigned long cursor = 0;
    char entry[32];
    unsigned namelen = 0;
    int d_type = 0;

    tm_procfs_init(NULL, NULL);
    CHECK(tm_procfs_resolve("/proc/1", NULL) == 0);
    CHECK(tm_procfs_path_exists("/proc/1/info") == 0);
    CHECK(tm_procfs_info(1, buf, sizeof(buf)) == 0);
    CHECK(tm_procfs_readdir_root(&cursor, entry, &namelen, &d_type) == 0);

    tm_procfs_init(NULL, fixture_next);
    cursor = 0;
    CHECK(tm_procfs_resolve("/proc/1", NULL) == 0);
    CHECK(tm_procfs_readdir_root(&cursor, entry, &namelen, &d_type) == 1);

    tm_procfs_init(fixture_get, NULL);
    cursor = 0;
    CHECK(tm_procfs_resolve("/proc/1", NULL) == 2);
    CHECK(tm_procfs_readdir_root(&cursor, entry, &namelen, &d_type) == 0);
}

static void test_disappearing_pid(void)
{
    char buf[TM_PROCFS_INFO_MAX];

    reset_callbacks();
    CHECK(tm_procfs_path_exists("/proc/7/info") != 0);

    dropped_pid = 7;
    CHECK(tm_procfs_path_exists("/proc/7/info") == 0);
    CHECK(tm_procfs_info(7, buf, sizeof(buf)) == 0);

    {
        unsigned long cursor = 0;
        expect_root_entry(&cursor, "1", 2);
        expect_root_entry(&cursor, "42", 43);
    }
}

int main(void)
{
    CHECK(sizeof(((struct tm_procfs_proc *)0)->name) == TM_PROCFS_NAME_MAX);

    test_path_resolution();
    test_info_formatting();
    test_readdir_root();
    test_readdir_piddir();
    test_missing_callbacks();
    test_disappearing_pid();

    puts("tm_procfs_model_test: ok");
    return 0;
}
