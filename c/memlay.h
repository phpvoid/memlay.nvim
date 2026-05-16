#ifndef MEMLAY_H
#define MEMLAY_H

#include <stddef.h>

#define MAX_FIELDS 64
#define MAX_NAME   128

typedef struct {
    char   name[MAX_NAME];
    char   type_name[64];
    size_t size;
    size_t align;
    size_t offset;
    size_t padding;
} FieldInfo;

typedef struct {
    FieldInfo fields[MAX_FIELDS];
    int       field_count;
    size_t    total_size;
    size_t    packed_size;
    char      suggestion[1024];
    char      struct_name[128];
    int       struct_start_line;
    int       struct_end_line;
} LayoutResult;

void compute_layout(FieldInfo *fields, int count, LayoutResult *out);

size_t compute_packed_size(FieldInfo *fields, int count);

void compute_suggestion(FieldInfo *fields, int count, LayoutResult *out);

LayoutResult analyze_struct(const char *filepath, int line, int col);

#endif
