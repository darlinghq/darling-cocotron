#import <AppKit/AppKit.h>
#import <objc/runtime.h>
#include <stdio.h>

// +[NSCursor setHiddenUntilMouseMoves:YES] hides the cursor until the pointer moves; a genuine motion (the
// backend calls -[NSDisplay pointerMoved]) brings it back, once. The calls the backend would receive are counted
// by replacing -hideCursor and -unhideCursor on the running display's class, so this needs no window.
// The hide/unhide calls are counted, so an explicit +[NSCursor hide] outlives a pending hide-until-motion.

// NSDisplay is AppKit's private backend class; only what the test calls is declared.
@interface NSDisplay : NSObject
+ (NSDisplay *) currentDisplay;
- (void) pointerMoved;
@end

static int hides, unhides;
static void countHide(id self, SEL _cmd) { hides++; }
static void countUnhide(id self, SEL _cmd) { unhides++; }

static int failures;
#define CHECK(condition, ...)                                                                               \
    do {                                                                                                    \
        if (!(condition)) {                                                                                 \
            failures++;                                                                                     \
            printf("FAIL line %d: ", __LINE__);                                                             \
            printf(__VA_ARGS__);                                                                            \
            printf("\n");                                                                                   \
        }                                                                                                   \
    } while (0)

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSDisplay *display = [NSDisplay currentDisplay];
        Class cls = [display class];
        class_replaceMethod(cls, @selector(hideCursor), (IMP) countHide, "v@:");
        class_replaceMethod(cls, @selector(unhideCursor), (IMP) countUnhide, "v@:");

        [display pointerMoved];
        CHECK(hides == 0 && unhides == 0, "motion with nothing hidden does nothing (%d, %d)", hides, unhides);

        [NSCursor setHiddenUntilMouseMoves: YES];
        CHECK(hides == 1 && unhides == 0, "hidden until mouse moves hides once (%d, %d)", hides, unhides);
        [NSCursor setHiddenUntilMouseMoves: YES];
        CHECK(hides == 1, "asking again does not hide twice (%d)", hides);

        [display pointerMoved];
        CHECK(hides == 1 && unhides == 1, "motion brings the cursor back (%d, %d)", hides, unhides);
        [display pointerMoved];
        CHECK(unhides == 1, "a second motion does not unhide again (%d)", unhides);

        [NSCursor setHiddenUntilMouseMoves: YES];
        [NSCursor setHiddenUntilMouseMoves: NO];
        CHECK(hides == 2 && unhides == 2, "setting NO unhides (%d, %d)", hides, unhides);
        [NSCursor setHiddenUntilMouseMoves: NO];
        CHECK(unhides == 2, "setting NO with nothing pending does nothing (%d)", unhides);
        [display pointerMoved];
        CHECK(unhides == 2, "and motion after NO does not unhide (%d)", unhides);

        // Hide is counted: an explicit hide is not undone by motion, and does not undo a pending hide.
        hides = unhides = 0;
        [NSCursor hide];
        CHECK(hides == 1, "explicit hide hides (%d)", hides);
        [NSCursor setHiddenUntilMouseMoves: YES];
        CHECK(hides == 1, "hidden until mouse moves while already hidden does not hide again (%d)", hides);
        [display pointerMoved];
        CHECK(unhides == 0, "motion does not undo the explicit hide (%d)", unhides);
        [NSCursor unhide];
        CHECK(unhides == 1, "the matching unhide shows the cursor (%d)", unhides);
        [NSCursor unhide];
        CHECK(unhides == 1, "an unhide with nothing hidden does nothing (%d)", unhides);

        // The other order: pending hide-until-motion, then an explicit hide.
        hides = unhides = 0;
        [NSCursor setHiddenUntilMouseMoves: YES];
        [NSCursor hide];
        [display pointerMoved];
        CHECK(hides == 1 && unhides == 0, "motion leaves the explicitly hidden cursor hidden (%d, %d)", hides, unhides);
        [NSCursor unhide];
        CHECK(unhides == 1, "and the explicit unhide shows it (%d)", unhides);
    }
    if (failures) {
        printf("%d check(s) FAILED\n", failures);
        return 1;
    }
    printf("PASS\n");
    return 0;
}
