#include "memlay.h"
#include <stdio.h>
#include <string.h>
#include <stdlib.h>

static int tests_run = 0;
static int tests_passed = 0;
static int tests_failed = 0;

#define TEST(name) do { \
    tests_run++; \
    printf("  %-50s", name); \
} while(0)

#define PASS() do { \
    tests_passed++; \
    printf("PASS\n"); \
} while(0)

#define FAIL(fmt, ...) do { \
    tests_failed++; \
    printf("FAIL: " fmt "\n", ##__VA_ARGS__); \
} while(0)

#define ASSERT_EQ_INT(expect, actual) do { \
    if ((expect) != (actual)) { FAIL("expected %d, got %d", (int)(expect), (int)(actual)); return; } \
} while(0)

#define ASSERT_EQ_STR(expect, actual) do { \
    if (strcmp((expect), (actual)) != 0) { FAIL("expected '%s', got '%s'", expect, actual); return; } \
} while(0)

/* ── Test helpers ── */

static FieldInfo fi(const char *name, size_t size, size_t align) {
    FieldInfo f;
    strncpy(f.name, name, MAX_NAME - 1);
    f.name[MAX_NAME - 1] = '\0';
    f.size = size;
    f.align = align;
    f.offset = 0;
    f.padding = 0;
    return f;
}

static void run_test(const char *desc, FieldInfo *fields, int count,
                     size_t expected_total, size_t expected_fields,
                     size_t *expected_offsets, size_t *expected_paddings) {
    TEST(desc);
    LayoutResult out;
    compute_layout(fields, count, &out);
    ASSERT_EQ_INT((int)expected_fields, out.field_count);
    ASSERT_EQ_INT((int)expected_total, (int)out.total_size);
    for (int i = 0; i < count; i++) {
        if (out.fields[i].offset != expected_offsets[i]) {
            FAIL("field[%d] offset: expected %zu, got %zu",
                 i, expected_offsets[i], out.fields[i].offset);
            return;
        }
        if (out.fields[i].padding != expected_paddings[i]) {
            FAIL("field[%d] padding: expected %zu, got %zu",
                 i, expected_paddings[i], out.fields[i].padding);
            return;
        }
    }
    PASS();
}

/* ── Tests ── */

static void test_char_int_char(void) {
    FieldInfo f[] = { fi("a", 1, 1), fi("b", 4, 4), fi("c", 1, 1) };
    size_t off[] = { 0, 4, 8 };
    size_t pad[] = { 3, 0, 3 };
    run_test("{char,int,char} → 12B", f, 3, 12, 3, off, pad);
}

static void test_int_char_char(void) {
    FieldInfo f[] = { fi("a", 4, 4), fi("b", 1, 1), fi("c", 1, 1) };
    size_t off[] = { 0, 4, 5 };
    size_t pad[] = { 0, 0, 2 };
    run_test("{int,char,char} → 8B", f, 3, 8, 3, off, pad);
}

static void test_double_char_int(void) {
    FieldInfo f[] = { fi("d", 8, 8), fi("c", 1, 1), fi("i", 4, 4) };
    size_t off[] = { 0, 8, 12 };
    size_t pad[] = { 0, 3, 0 };
    run_test("{double,char,int} → 16B", f, 3, 16, 3, off, pad);
}

static void test_double_char_int_packed(void) {
    TEST("packed size {double,char,int} → 13B");
    FieldInfo f[] = { fi("d", 8, 8), fi("c", 1, 1), fi("i", 4, 4) };
    size_t ps = compute_packed_size(f, 3);
    ASSERT_EQ_INT(13, (int)ps);
    PASS();
}

static void test_single_char(void) {
    FieldInfo f[] = { fi("a", 1, 1) };
    size_t off[] = { 0 };
    size_t pad[] = { 0 };
    run_test("{char} → 1B", f, 1, 1, 1, off, pad);
}

static void test_single_char_packed(void) {
    TEST("packed size {char} → 1B");
    FieldInfo f[] = { fi("a", 1, 1) };
    size_t ps = compute_packed_size(f, 1);
    ASSERT_EQ_INT(1, (int)ps);
    PASS();
}

static void test_empty_struct(void) {
    TEST("empty struct → 0B");
    LayoutResult out;
    compute_layout(NULL, 0, &out);
    ASSERT_EQ_INT(0, out.field_count);
    ASSERT_EQ_INT(0, (int)out.total_size);
    PASS();
}

static void test_all_u64(void) {
    FieldInfo f[] = { fi("x", 8, 8), fi("y", 8, 8), fi("z", 8, 8) };
    size_t off[] = { 0, 8, 16 };
    size_t pad[] = { 0, 0, 0 };
    run_test("{u64,u64,u64} → 24B", f, 3, 24, 3, off, pad);
}

static void test_nested_like(void) {
    FieldInfo f[] = { fi("inner", 8, 4), fi("x", 1, 1) };
    size_t off[] = { 0, 8 };
    size_t pad[] = { 0, 3 };
    run_test("nested-like: inner{4B align,8B size}+char", f, 2, 12, 2, off, pad);
}

static void test_packed_size(void) {
    TEST("packed size {char,int,char} → 6B");
    FieldInfo f[] = { fi("a", 1, 1), fi("b", 4, 4), fi("c", 1, 1) };
    size_t ps = compute_packed_size(f, 3);
    ASSERT_EQ_INT(6, (int)ps);
    PASS();
}

static void test_suggestion_beneficial(void) {
    TEST("suggestion: {char,int,char} saves 4B (33% smaller)");
    FieldInfo f[] = { fi("a", 1, 1), fi("b", 4, 4), fi("c", 1, 1) };
    LayoutResult out;
    memset(&out, 0, sizeof(out));
    compute_suggestion(f, 3, &out);
    if (out.suggestion[0] == '\0') { FAIL("expected non-empty suggestion"); return; }
    if (!strstr(out.suggestion, "reorder to:")) { FAIL("missing 'reorder to:' prefix"); return; }
    if (!strstr(out.suggestion, "33% smaller")) { FAIL("missing '33% smaller'"); return; }
    PASS();
}

static void test_suggestion_none(void) {
    TEST("suggestion: {int,int,int} no benefit");
    FieldInfo f[] = { fi("a", 4, 4), fi("b", 4, 4), fi("c", 4, 4) };
    LayoutResult out;
    memset(&out, 0, sizeof(out));
    compute_suggestion(f, 3, &out);
    ASSERT_EQ_STR("", out.suggestion);
    PASS();
}

static void test_suggestion_single(void) {
    TEST("suggestion: single field → empty");
    FieldInfo f[] = { fi("a", 1, 1) };
    LayoutResult out;
    memset(&out, 0, sizeof(out));
    compute_suggestion(f, 1, &out);
    ASSERT_EQ_STR("", out.suggestion);
    PASS();
}

int main(void) {
    printf("memlay — standalone layout tests\n\n");

    test_char_int_char();
    test_int_char_char();
    test_double_char_int();
    test_double_char_int_packed();
    test_single_char();
    test_single_char_packed();
    test_empty_struct();
    test_all_u64();
    test_nested_like();
    test_packed_size();
    test_suggestion_beneficial();
    test_suggestion_none();
    test_suggestion_single();

    printf("\n%d run, %d passed, %d failed\n", tests_run, tests_passed, tests_failed);
    return tests_failed > 0 ? 1 : 0;
}
