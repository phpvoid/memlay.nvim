#include "memlay.h"
#include <string.h>
#include <stdlib.h>
#include <stdio.h>
#include <clang-c/Index.h>

typedef struct {
    FieldInfo fields[MAX_FIELDS];
    int count;
} FieldCollector;

static enum CXChildVisitResult field_visitor(CXCursor cursor, CXCursor parent,
                                              CXClientData client_data) {
    (void)parent;
    FieldCollector *fc = (FieldCollector*)client_data;

    if (clang_getCursorKind(cursor) != CXCursor_FieldDecl)
        return CXChildVisit_Continue;

    if (clang_Cursor_isBitField(cursor))
        return CXChildVisit_Continue;

    CXType ty = clang_getCursorType(cursor);
    long long sz = clang_Type_getSizeOf(ty);
    long long al = clang_Type_getAlignOf(ty);

    if (sz < 0) return CXChildVisit_Continue;

    CXString spelling = clang_getCursorSpelling(cursor);
    const char *name = clang_getCString(spelling);

    CXString type_spelling = clang_getTypeSpelling(ty);
    const char *tname = clang_getCString(type_spelling);

    int i = fc->count;
    if (i < MAX_FIELDS) {
        strncpy(fc->fields[i].name, name ? name : "", MAX_NAME - 1);
        fc->fields[i].name[MAX_NAME - 1] = '\0';
        strncpy(fc->fields[i].type_name, tname ? tname : "", 63);
        fc->fields[i].type_name[63] = '\0';
        fc->fields[i].size = (size_t)sz;
        fc->fields[i].align = al > 0 ? (size_t)al : 1;
        fc->count++;
    }

    clang_disposeString(type_spelling);
    clang_disposeString(spelling);
    return CXChildVisit_Continue;
}

LayoutResult analyze_struct(const char *filepath, int line, int col) {
    LayoutResult result;
    memset(&result, 0, sizeof(result));

    FILE *f = fopen(filepath, "r");
    if (!f) return result;
    fclose(f);

    CXIndex index = clang_createIndex(0, 0);
    CXTranslationUnit tu = clang_parseTranslationUnit(
        index, filepath, NULL, 0, NULL, 0, CXTranslationUnit_None);

    if (!tu) {
        clang_disposeIndex(index);
        return result;
    }

    CXFile file = clang_getFile(tu, filepath);
    if (!file) {
        clang_disposeTranslationUnit(tu);
        clang_disposeIndex(index);
        return result;
    }

    CXSourceLocation loc = clang_getLocation(tu, file, (unsigned)line, (unsigned)col);
    CXCursor cursor = clang_getCursor(tu, loc);

    while (clang_getCursorKind(cursor) != CXCursor_StructDecl) {
        CXCursor parent = clang_getCursorSemanticParent(cursor);
        if (clang_equalCursors(cursor, parent) ||
            clang_getCursorKind(parent) == CXCursor_TranslationUnit)
            break;
        cursor = parent;
    }

    if (clang_getCursorKind(cursor) != CXCursor_StructDecl) {
        clang_disposeTranslationUnit(tu);
        clang_disposeIndex(index);
        return result;
    }

    CXCursor struct_cursor = cursor;

    FieldCollector fc;
    memset(&fc, 0, sizeof(fc));
    clang_visitChildren(struct_cursor, field_visitor, &fc);

    result.field_count = fc.count;
    if (fc.count > 0) {
        compute_layout(fc.fields, fc.count, &result);
        result.packed_size = compute_packed_size(result.fields, result.field_count);
        compute_suggestion(fc.fields, fc.count, &result);
    }

    CXString struct_name_str = clang_getCursorSpelling(struct_cursor);
    const char *sname = clang_getCString(struct_name_str);
    if (sname) {
        strncpy(result.struct_name, sname, 127);
        result.struct_name[127] = '\0';
    }
    clang_disposeString(struct_name_str);

    CXSourceRange extent = clang_getCursorExtent(struct_cursor);
    unsigned start_line, end_line;
    clang_getSpellingLocation(clang_getRangeStart(extent), NULL, &start_line, NULL, NULL);
    clang_getSpellingLocation(clang_getRangeEnd(extent), NULL, &end_line, NULL, NULL);
    result.struct_start_line = (int)start_line;
    result.struct_end_line   = (int)end_line;

    clang_disposeTranslationUnit(tu);
    clang_disposeIndex(index);
    return result;
}
