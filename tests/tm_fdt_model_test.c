/*
 * Host tests for LQ taskman's minimal FDT parser.
 *
 * These tests link the existing C implementation directly and capture the
 * tm_fdt_* ABI/behavior before the Rust provider is wired into taskman.
 */
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <sys/fdt.h>

#define FDT_BEGIN_NODE  1
#define FDT_END_NODE    2
#define FDT_PROP        3
#define FDT_NOP         4
#define FDT_END         9

#define CHECK(expr) do { \
    if (!(expr)) { \
        fprintf(stderr, "%s:%d: check failed: %s\n", __FILE__, __LINE__, #expr); \
        exit(1); \
    } \
} while (0)

typedef struct {
    unsigned char *data;
    size_t len;
    size_t cap;
} bytebuf_t;

static void reserve(bytebuf_t *b, size_t extra)
{
    if (b->len + extra <= b->cap) return;
    size_t cap = b->cap ? b->cap : 128;
    while (cap < b->len + extra) cap *= 2;
    unsigned char *p = realloc(b->data, cap);
    CHECK(p != NULL);
    b->data = p;
    b->cap = cap;
}

static void push_byte(bytebuf_t *b, unsigned char value)
{
    reserve(b, 1);
    b->data[b->len++] = value;
}

static void push_bytes(bytebuf_t *b, const void *data, size_t len)
{
    reserve(b, len);
    memcpy(b->data + b->len, data, len);
    b->len += len;
}

static void push_be32(bytebuf_t *b, uint32_t value)
{
    unsigned char data[4] = {
        (unsigned char)(value >> 24),
        (unsigned char)(value >> 16),
        (unsigned char)(value >> 8),
        (unsigned char)value,
    };
    push_bytes(b, data, sizeof data);
}

static void align4(bytebuf_t *b)
{
    while ((b->len % 4) != 0) push_byte(b, 0);
}

static uint32_t string_off(bytebuf_t *strings, const char *name)
{
    uint32_t off = (uint32_t)strings->len;
    push_bytes(strings, name, strlen(name) + 1);
    return off;
}

static void begin_node(bytebuf_t *struc, const char *name)
{
    push_be32(struc, FDT_BEGIN_NODE);
    push_bytes(struc, name, strlen(name) + 1);
    align4(struc);
}

static void end_node(bytebuf_t *struc)
{
    push_be32(struc, FDT_END_NODE);
}

static void prop(bytebuf_t *struc, bytebuf_t *strings,
                 const char *name, const void *value, size_t len)
{
    uint32_t nameoff = string_off(strings, name);
    push_be32(struc, FDT_PROP);
    push_be32(struc, (uint32_t)len);
    push_be32(struc, nameoff);
    push_bytes(struc, value, len);
    align4(struc);
}

static void append_be32(bytebuf_t *b, uint32_t value)
{
    push_be32(b, value);
}

static unsigned char *synthetic_fdt(uint32_t last_comp_version, size_t *out_len)
{
    bytebuf_t struc = {0};
    bytebuf_t strings = {0};
    bytebuf_t blob = {0};

    push_be32(&struc, FDT_NOP);
    begin_node(&struc, "");
    prop(&struc, &strings, "model", "qsoe-model", sizeof("qsoe-model"));
    prop(&struc, &strings, "compatible",
         "qsoe,virt\0riscv-virtio", sizeof("qsoe,virt\0riscv-virtio"));
    prop(&struc, &strings, "badstr", "abc", 3);

    begin_node(&struc, "chosen");
    prop(&struc, &strings, "bootargs", "root=/dev/vda", sizeof("root=/dev/vda"));
    uint32_t boot_hart = 2;
    unsigned char boot_hart_be[4] = {
        (unsigned char)(boot_hart >> 24),
        (unsigned char)(boot_hart >> 16),
        (unsigned char)(boot_hart >> 8),
        (unsigned char)boot_hart,
    };
    prop(&struc, &strings, "boot-hartid", boot_hart_be, sizeof boot_hart_be);
    end_node(&struc);

    begin_node(&struc, "cpus");
    uint32_t timebase = 10000000;
    unsigned char timebase_be[4] = {
        (unsigned char)(timebase >> 24),
        (unsigned char)(timebase >> 16),
        (unsigned char)(timebase >> 8),
        (unsigned char)timebase,
    };
    prop(&struc, &strings, "timebase-frequency",
         timebase_be, sizeof timebase_be);
    begin_node(&struc, "cpu@0");
    prop(&struc, &strings, "device_type", "cpu", sizeof("cpu"));
    end_node(&struc);
    begin_node(&struc, "cpu@1");
    prop(&struc, &strings, "device_type", "cpu", sizeof("cpu"));
    end_node(&struc);
    end_node(&struc);

    begin_node(&struc, "memory@80000000");
    bytebuf_t reg = {0};
    append_be32(&reg, 0);
    append_be32(&reg, 0x80000000u);
    append_be32(&reg, 0);
    append_be32(&reg, 0x08000000u);
    prop(&struc, &strings, "reg", reg.data, reg.len);
    free(reg.data);
    end_node(&struc);

    begin_node(&struc, "soc");
    begin_node(&struc, "pci@30000000");
    prop(&struc, &strings, "compatible",
         "pci-host-ecam-generic\0other",
         sizeof("pci-host-ecam-generic\0other"));
    end_node(&struc);
    end_node(&struc);

    end_node(&struc);
    push_be32(&struc, FDT_END);

    uint32_t off_dt_struct = 40;
    uint32_t off_dt_strings = off_dt_struct + (uint32_t)struc.len;
    uint32_t totalsize = off_dt_strings + (uint32_t)strings.len;

    push_be32(&blob, TM_FDT_MAGIC);
    push_be32(&blob, totalsize);
    push_be32(&blob, off_dt_struct);
    push_be32(&blob, off_dt_strings);
    push_be32(&blob, 0);
    push_be32(&blob, 17);
    push_be32(&blob, last_comp_version);
    push_be32(&blob, 0);
    push_be32(&blob, (uint32_t)strings.len);
    push_be32(&blob, (uint32_t)struc.len);
    push_bytes(&blob, struc.data, struc.len);
    push_bytes(&blob, strings.data, strings.len);

    free(struc.data);
    free(strings.data);

    *out_len = blob.len;
    return blob.data;
}

static void test_check_size_and_header_rejection(void)
{
    size_t len = 0;
    unsigned char *blob = synthetic_fdt(16, &len);

    CHECK(tm_fdt_check(blob) == 0);
    CHECK(tm_fdt_size(blob) == len);
    CHECK(tm_fdt_check(NULL) == -1);
    blob[0] = 0;
    CHECK(tm_fdt_check(blob) == -1);
    CHECK(tm_fdt_size(blob) == 0);
    free(blob);

    blob = synthetic_fdt(18, &len);
    CHECK(tm_fdt_check(blob) == -1);
    free(blob);
}

static void test_paths_and_properties(void)
{
    size_t len = 0;
    unsigned char *blob = synthetic_fdt(16, &len);
    (void)len;

    int root = tm_fdt_path(blob, "/");
    int chosen = tm_fdt_path(blob, "/chosen");
    int cpu1 = tm_fdt_path(blob, "/cpus/cpu@1");
    int memory = tm_fdt_path(blob, "/memory");

    CHECK(root == 4);
    CHECK(chosen > root);
    CHECK(cpu1 > chosen);
    CHECK(memory > cpu1);
    CHECK(tm_fdt_path(blob, "chosen") == -1);
    CHECK(tm_fdt_path(blob, "/missing") == -1);

    const char *model = NULL;
    CHECK(tm_fdt_prop_str(blob, root, "model", &model) == 0);
    CHECK(strcmp(model, "qsoe-model") == 0);

    uint32_t boot_hart = 0;
    CHECK(tm_fdt_prop_u32(blob, chosen, "boot-hartid", &boot_hart) == 0);
    CHECK(boot_hart == 2);

    const void *compat = NULL;
    unsigned compat_len = 0;
    CHECK(tm_fdt_prop(blob, root, "compatible", &compat, &compat_len) == 0);
    CHECK(compat != NULL);
    CHECK(compat_len == sizeof("qsoe,virt\0riscv-virtio"));

    CHECK(tm_fdt_prop_str(blob, root, "badstr", &model) == -1);
    free(blob);
}

static void test_compatible_and_reg_tuple(void)
{
    size_t len = 0;
    unsigned char *blob = synthetic_fdt(16, &len);
    (void)len;

    int pci = tm_fdt_compatible(blob, "pci-host-ecam-generic");
    CHECK(pci > 0);
    CHECK(tm_fdt_compatible(blob, "absent") == -1);
    CHECK(tm_fdt_compatible(blob, NULL) == -1);

    int memory = tm_fdt_path(blob, "/memory@80000000");
    uint64_t base = 0;
    uint64_t size = 0;
    CHECK(tm_fdt_reg(blob, memory, 2, 2, 0, &base, &size) == 0);
    CHECK(base == 0x80000000ull);
    CHECK(size == 0x08000000ull);
    CHECK(tm_fdt_reg(blob, memory, 2, 2, 1, &base, &size) == -1);
    CHECK(tm_fdt_reg(blob, memory, 0, 0, 0, &base, &size) == -1);

    free(blob);
}

int main(void)
{
    test_check_size_and_header_rejection();
    test_paths_and_properties();
    test_compatible_and_reg_tuple();
    return 0;
}
