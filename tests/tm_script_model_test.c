/*
 * Host tests for the portable tm_script shebang parser.
 *
 * These tests link the existing C implementation directly and capture the C
 * ABI/behavior before the Rust provider is wired into task-manager paths.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <tm_script.h>

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

static void test_parse_arg(void)
{
    char interp[32];
    char arg[32];
    const uint8_t script[] = "#!   /bin/qsh\t-x -y  \nbody";

    memset(interp, 'I', sizeof interp);
    memset(arg, 'A', sizeof arg);
    CHECK(tm_script_parse_shebang(script, sizeof(script) - 1,
                                  interp, sizeof interp,
                                  arg, sizeof arg) == 0);
    CHECK_STREQ(interp, "/bin/qsh");
    CHECK_STREQ(arg, "-x -y");
}

static void test_no_arg_and_cr(void)
{
    char interp[32];
    char arg[32];
    const uint8_t script[] = "#!/sbin/init\rignored";

    memset(interp, 0, sizeof interp);
    memset(arg, 0, sizeof arg);
    CHECK(tm_script_parse_shebang(script, sizeof(script) - 1,
                                  interp, sizeof interp,
                                  arg, sizeof arg) == 0);
    CHECK_STREQ(interp, "/sbin/init");
    CHECK_STREQ(arg, "");
}

static void test_rejects(void)
{
    char interp[16] = "stale";
    char arg[16] = "stale";
    const uint8_t plain[] = "plain text";
    const uint8_t empty[] = "#!   \n";

    CHECK(tm_script_parse_shebang(plain, sizeof(plain) - 1,
                                  interp, sizeof interp,
                                  arg, sizeof arg) == -1);
    CHECK_STREQ(interp, "");
    CHECK_STREQ(arg, "");

    strcpy(interp, "stale");
    strcpy(arg, "stale");
    CHECK(tm_script_parse_shebang(empty, sizeof(empty) - 1,
                                  interp, sizeof interp,
                                  arg, sizeof arg) == -1);
    CHECK_STREQ(interp, "");
    CHECK_STREQ(arg, "");
}

static void test_current_truncation_behavior(void)
{
    char interp[32];
    char arg[32];
    const uint8_t small_interp[] = "#!/bin/qsh -x\n";
    const uint8_t small_arg[] = "#!/bin/qsh abcdef\n";

    memset(interp, 0, sizeof interp);
    memset(arg, 0, sizeof arg);
    CHECK(tm_script_parse_shebang(small_interp, sizeof(small_interp) - 1,
                                  interp, 5, arg, sizeof arg) == 0);
    CHECK_STREQ(interp, "/bin");
    CHECK_STREQ(arg, "/qsh -x");

    memset(interp, 0, sizeof interp);
    memset(arg, 0, sizeof arg);
    CHECK(tm_script_parse_shebang(small_arg, sizeof(small_arg) - 1,
                                  interp, sizeof interp, arg, 4) == 0);
    CHECK_STREQ(interp, "/bin/qsh");
    CHECK_STREQ(arg, "abc");
}

static void test_zero_cap(void)
{
    char interp[4] = "bad";
    char arg[4] = "bad";
    const uint8_t script[] = "#!/bin/qsh\n";

    CHECK(tm_script_parse_shebang(script, sizeof(script) - 1,
                                  interp, 0, arg, sizeof arg) == -1);
    CHECK_STREQ(interp, "bad");
    CHECK_STREQ(arg, "bad");

    CHECK(tm_script_parse_shebang(script, sizeof(script) - 1,
                                  interp, sizeof interp, arg, 0) == -1);
    CHECK_STREQ(interp, "bad");
    CHECK_STREQ(arg, "bad");
}

int main(void)
{
    test_parse_arg();
    test_no_arg_and_cr();
    test_rejects();
    test_current_truncation_behavior();
    test_zero_cap();
    puts("tm_script_model_test: ok");
    return 0;
}
