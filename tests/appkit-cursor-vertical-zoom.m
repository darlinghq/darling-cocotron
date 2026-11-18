/*
 Copyright (C) 2026 Lubos Dolezel

 Licensed under the MIT license, the same as the rest of this project.
*/
// NSCursor: IBeamCursorForVerticalLayout, zoomInCursor and zoomOutCursor exist, are shared instances
// distinct from each other and from the other cursors, and can be made current and restored with the
// display backend that is selected (X11 or Wayland, through DARLING_APPKIT_BACKEND). Prints PASS on success.
#import <AppKit/AppKit.h>
#include <stdio.h>

static int failures;

static void expect(BOOL condition, const char *what) {
    if (!condition) {
        fprintf(stderr, "FAIL: %s\n", what);
        failures++;
    }
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSCursor *vertical = [NSCursor IBeamCursorForVerticalLayout];
        NSCursor *zoomIn = [NSCursor zoomInCursor];
        NSCursor *zoomOut = [NSCursor zoomOutCursor];

        expect(vertical != nil && zoomIn != nil && zoomOut != nil, "the cursors exist");
        expect(vertical == [NSCursor IBeamCursorForVerticalLayout] && zoomIn == [NSCursor zoomInCursor] &&
                       zoomOut == [NSCursor zoomOutCursor],
               "the cursors are shared instances");
        expect(vertical != zoomIn && zoomIn != zoomOut && vertical != zoomOut, "the cursors are distinct");
        expect(vertical != [NSCursor IBeamCursor] && zoomIn != [NSCursor arrowCursor],
               "they are not the horizontal I-beam or the arrow");

        NSCursor *before = [NSCursor arrowCursor];
        [before push];
        for (NSCursor *cursor in @[ vertical, zoomIn, zoomOut ]) {
            [cursor push];
            expect([NSCursor currentCursor] == cursor, "a pushed cursor becomes current");
            [NSCursor pop];
        }
        expect([NSCursor currentCursor] == before, "popping restores the previous cursor");
        [zoomIn set];
        expect([NSCursor currentCursor] == zoomIn, "-set makes the cursor current");
        [NSCursor pop];
    }
    if (failures == 0)
        printf("PASS\n");
    return failures == 0 ? 0 : 1;
}
