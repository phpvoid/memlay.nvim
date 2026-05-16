#include "memlay.h"
#include <string.h>
#include <stdlib.h>
#include <stdio.h>

void compute_layout(FieldInfo *fields, int count, LayoutResult *out) {
    memset(out, 0, sizeof(*out));
    if (count == 0) return;
    if (count > MAX_FIELDS) count = MAX_FIELDS;

    size_t max_align = 0;
    for (int i = 0; i < count; i++) {
        if (fields[i].align > max_align) max_align = fields[i].align;
    }

    size_t offset = 0;
    for (int i = 0; i < count; i++) {
        size_t a = fields[i].align > 0 ? fields[i].align : 1;
        if (offset % a != 0) offset += a - (offset % a);
        fields[i].offset = offset;
        offset += fields[i].size;
    }

    if (max_align > 0 && offset % max_align != 0)
        offset += max_align - (offset % max_align);

    for (int i = 0; i < count; i++) {
        if (i + 1 < count)
            fields[i].padding = fields[i + 1].offset - (fields[i].offset + fields[i].size);
        else
            fields[i].padding = offset - (fields[i].offset + fields[i].size);
    }

    out->field_count = count;
    out->total_size = offset;
    memcpy(out->fields, fields, (size_t)count * sizeof(FieldInfo));
}

size_t compute_packed_size(FieldInfo *fields, int count) {
    size_t total = 0;
    for (int i = 0; i < count; i++) total += fields[i].size;
    return total;
}

static int cmp_align_desc(const void *a, const void *b) {
    size_t sa = ((const FieldInfo *)a)->align;
    size_t sb = ((const FieldInfo *)b)->align;
    if (sa > sb) return -1;
    if (sa < sb) return 1;
    return 0;
}

void compute_suggestion(FieldInfo *fields, int count, LayoutResult *out) {
    out->suggestion[0] = '\0';
    if (count <= 1) {
        snprintf(out->suggestion, sizeof(out->suggestion),
            "OPTIMAL: no reordering can reduce this struct");
        return;
    }

    LayoutResult orig;
    compute_layout(fields, count, &orig);

    FieldInfo sorted[MAX_FIELDS];
    memcpy(sorted, fields, (size_t)count * sizeof(FieldInfo));
    qsort(sorted, (size_t)count, sizeof(FieldInfo), cmp_align_desc);

    LayoutResult opt;
    compute_layout(sorted, count, &opt);

    if (opt.total_size >= orig.total_size) {
        snprintf(out->suggestion, sizeof(out->suggestion),
            "OPTIMAL: no reordering can reduce this struct");
        return;
    }

    int savings = (int)(orig.total_size - opt.total_size);
    int pos = snprintf(out->suggestion, 512, "reorder to: ");
    for (int i = 0; i < count && pos < 500; i++) {
        if (i > 0) { pos += snprintf(out->suggestion + pos, 512 - (size_t)pos, ", "); }
        pos += snprintf(out->suggestion + pos, 512 - (size_t)pos, "%s", sorted[i].name);
    }
    snprintf(out->suggestion + pos, 512 - (size_t)pos, " — saves %dB", savings);
}
