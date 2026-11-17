// Copyright (C) 2026 Lubos Dolezel
//
// test_quirk_matrix_intrinsic_size: the intrinsic content size of a matrix is that of its cells and
// the spacing between them (width of a column times the columns, plus the spacing between columns;
// the same for rows), and 0x0 for a matrix without cells. A matrix loaded from a nib kept the
// 10000x10000 size of its prototype cell and made a layout hundreds of times too wide.
// Observed on macOS 10.14.4 and 26.7.3.
//
// Build: clang -fobjc-arc -framework AppKit appkit-matrix-intrinsic-size.m
#import <AppKit/AppKit.h>
#include <stdio.h>

static int failures;
#define CHECK(c) do { if (!(c)) { fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #c); failures++; } } while (0)

static void test_quirk_matrix_intrinsic_size(void) {
    NSButtonCell *proto = [[NSButtonCell alloc] init];
    [proto setButtonType:NSButtonTypeRadio];
    NSMatrix *m = [[NSMatrix alloc] initWithFrame:NSMakeRect(0, 0, 300, 58) mode:NSRadioModeMatrix
            prototype:proto numberOfRows:3 numberOfColumns:2];
    [m setCellSize:NSMakeSize(60, 18)];
    [m setIntercellSpacing:NSMakeSize(2, 3)];
    NSSize s = [m intrinsicContentSize];
    CHECK(s.width == 2 * 60 + 2);
    CHECK(s.height == 3 * 18 + 2 * 3);

    NSMatrix *column = [[NSMatrix alloc] initWithFrame:NSMakeRect(0, 0, 300, 58) mode:NSRadioModeMatrix
            prototype:proto numberOfRows:3 numberOfColumns:1];
    [column setCellSize:NSMakeSize(57, 16)];
    [column setIntercellSpacing:NSMakeSize(1, 1)];
    s = [column intrinsicContentSize];
    CHECK(s.width == 57 && s.height == 50);

    NSMatrix *empty = [[NSMatrix alloc] initWithFrame:NSMakeRect(0, 0, 120, 40)];
    s = [empty intrinsicContentSize];
    CHECK(s.width == 0 && s.height == 0);
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        test_quirk_matrix_intrinsic_size();
    }
    if (failures) return 1;
    printf("PASS\n");
    return 0;
}
