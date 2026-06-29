/*
 * Host tests for the portable tm_cred model.
 *
 * These tests link the existing C implementation directly and exercise the
 * documented C ABI before a Rust provider is wired into task-manager paths.
 */
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <qsoe/tm_msgs.h>
#include <tm_cred.h>

#define CHECK(expr) do { \
    if (!(expr)) { \
        fprintf(stderr, "%s:%d: check failed: %s\n", __FILE__, __LINE__, #expr); \
        exit(1); \
    } \
} while (0)

static void test_layout(void)
{
    CHECK(sizeof(struct _cred_info) == 28);
    CHECK(offsetof(struct _cred_info, ruid) == 0);
    CHECK(offsetof(struct _cred_info, euid) == 4);
    CHECK(offsetof(struct _cred_info, suid) == 8);
    CHECK(offsetof(struct _cred_info, rgid) == 12);
    CHECK(offsetof(struct _cred_info, egid) == 16);
    CHECK(offsetof(struct _cred_info, sgid) == 20);
    CHECK(offsetof(struct _cred_info, ngroups) == 24);

    CHECK(sizeof(tm_cred_state_t) == 288);
    CHECK(offsetof(tm_cred_state_t, cwd) == 0);
    CHECK(offsetof(tm_cred_state_t, umask) == 256);
    CHECK(offsetof(tm_cred_state_t, cred) == 260);
}

static void test_init(void)
{
    tm_cred_state_t s;
    memset(&s, 0x55, sizeof(s));
    tm_cred_init(&s);

    CHECK(s.cwd[0] == '/');
    CHECK(s.cwd[1] == 0);
    CHECK((unsigned char)s.cwd[2] == 0x55);
    CHECK(s.umask == 0022u);
    CHECK(s.cred.ruid == 0 && s.cred.euid == 0 && s.cred.suid == 0);
    CHECK(s.cred.rgid == 0 && s.cred.egid == 0 && s.cred.sgid == 0);
    CHECK(s.cred.ngroups == 0);

    tm_cred_init(NULL);
}

static void test_chdir_getcwd(void)
{
    tm_cred_state_t s;
    char out[TM_CWD_MAX];
    unsigned len = 0;

    tm_cred_init(&s);
    CHECK(tm_cred_chdir(&s, "/usr/bin", 8) == 0);
    CHECK(memcmp(s.cwd, "/usr/bin", 8) == 0);
    CHECK(s.cwd[8] == 0);

    memset(out, 0x66, sizeof(out));
    CHECK(tm_cred_getcwd(&s, out, 8, &len) == 0);
    CHECK(len == 8);
    CHECK(memcmp(out, "/usr/bin", 8) == 0);
    CHECK((unsigned char)out[8] == 0x66);

    len = 123;
    CHECK(tm_cred_getcwd(&s, out, 7, &len) == -ERANGE);
    CHECK(len == 123);

    CHECK(tm_cred_chdir(&s, "relative", 8) == -EINVAL);
    CHECK(tm_cred_chdir(&s, "/x", 0) == -ENAMETOOLONG);
    CHECK(tm_cred_chdir(&s, "/x", TM_CWD_MAX) == -ENAMETOOLONG);
    CHECK(tm_cred_chdir(NULL, "/x", 2) == -EINVAL);
    CHECK(tm_cred_chdir(&s, NULL, 2) == -EINVAL);

    CHECK(tm_cred_getcwd(NULL, out, 1, &len) == -EINVAL);
    CHECK(tm_cred_getcwd(&s, NULL, 1, &len) == -EINVAL);
    CHECK(tm_cred_getcwd(&s, out, 0, &len) == -EINVAL);
    CHECK(tm_cred_getcwd(&s, out, 1, NULL) == -EINVAL);
}

static void test_umask(void)
{
    tm_cred_state_t s;
    unsigned old = 0;

    tm_cred_init(&s);
    CHECK(tm_cred_umask(&s, -1, &old) == 0);
    CHECK(old == 0022u);
    CHECK(s.umask == 0022u);

    CHECK(tm_cred_umask(&s, 01777, &old) == 0);
    CHECK(old == 0022u);
    CHECK(s.umask == 0777u);

    CHECK(tm_cred_umask(NULL, 0, &old) == -EINVAL);
    CHECK(tm_cred_umask(&s, 0, NULL) == -EINVAL);
}

static void test_set_and_self_info(void)
{
    tm_cred_state_t s;
    struct _cred_info out;

    tm_cred_init(&s);
    CHECK(tm_cred_set(&s, 100, TM_CRED_KEEP, 101,
                      200, TM_CRED_KEEP, 201) == 0);
    CHECK(s.cred.ruid == 100);
    CHECK(s.cred.euid == 0);
    CHECK(s.cred.suid == 101);
    CHECK(s.cred.rgid == 200);
    CHECK(s.cred.egid == 0);
    CHECK(s.cred.sgid == 201);
    CHECK(s.cred.ngroups == 0);

    memset(&out, 0, sizeof(out));
    tm_cred_self_info(&s, &out);
    CHECK(memcmp(&out, &s.cred, sizeof(out)) == 0);
    tm_cred_self_info(NULL, &out);
    tm_cred_self_info(&s, NULL);

    CHECK(tm_cred_set(NULL, 1, 2, 3, 4, 5, 6) == -EINVAL);
}

static void test_change_policy(void)
{
    struct _cred_info root = {
        .ruid = 10, .euid = 0, .suid = 11,
        .rgid = 20, .egid = 21, .sgid = 22,
        .ngroups = 0,
    };
    struct _cred_info user = {
        .ruid = 1000, .euid = 1001, .suid = 1002,
        .rgid = 2000, .egid = 2001, .sgid = 2002,
        .ngroups = 0,
    };

    CHECK(tm_cred_change_permitted(&root, 999, 998, 997, 996, 995, 994) == 1);
    CHECK(tm_cred_change_permitted(&user, 1002, 1000, TM_CRED_KEEP,
                                   2001, 2002, TM_CRED_KEEP) == 1);
    CHECK(tm_cred_change_permitted(&user, 0, 1000, 1001, 2000, 2001, 2002) == 0);
    CHECK(tm_cred_change_permitted(&user, 1000, 1001, 1002, 0, 2000, 2001) == 0);
    CHECK(tm_cred_change_permitted(NULL, TM_CRED_KEEP, TM_CRED_KEEP, TM_CRED_KEEP,
                                   TM_CRED_KEEP, TM_CRED_KEEP, TM_CRED_KEEP) == 0);
}

int main(void)
{
    test_layout();
    test_init();
    test_chdir_getcwd();
    test_umask();
    test_set_and_self_info();
    test_change_policy();

    puts("tm_cred_model_test: ok");
    return 0;
}
