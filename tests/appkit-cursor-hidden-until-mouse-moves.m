#import <AppKit/AppKit.h>
#import <ApplicationServices/ApplicationServices.h>
#import <objc/runtime.h>
#include <stdio.h>

// +[NSCursor setHiddenUntilMouseMoves:YES] hides the cursor until the pointer moves; a genuine motion (the
// backend calls -[NSDisplay pointerMoved]) brings it back, once. The hide count is CoreGraphics' (CGCursorIsVisible()):
// the changes between a visible and a hidden cursor are counted after each call, so this needs no window.
// The hide/unhide calls are counted, so an explicit +[NSCursor hide] outlives a pending hide-until-motion.

// NSDisplay is AppKit's private backend class; only what the test calls is declared.
@interface NSDisplay : NSObject
+ (NSDisplay *) currentDisplay;
- (void) pointerMoved;
@end

static int hides, unhides;
static BOOL wasVisible = YES;
// Counts the change of the cursor between visible and hidden since the previous call.
static void sample(void) {
    BOOL visible = CGCursorIsVisible();
    if (wasVisible && !visible)
        hides++;
    else if (!wasVisible && visible)
        unhides++;
    wasVisible = visible;
}

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
        // On Wayland the hide count and the hidden-until-motion flag are CoreGraphics' (its connection has the
        // pointer): the display is not asked to hide anything, and appkit-wayland-relative-mouse checks the
        // cursor requests of the same calls.
        if ([NSStringFromClass(cls) isEqualToString: @"WaylandDisplay"]) {
            printf("SKIP: the hide count is CoreGraphics' on Wayland (see appkit-wayland-relative-mouse)\n");
            return 0;
        }

        [display pointerMoved]; sample();
        CHECK(hides == 0 && unhides == 0, "motion with nothing hidden does nothing (%d, %d)", hides, unhides);

        [NSCursor setHiddenUntilMouseMoves: YES]; sample();
        CHECK(hides == 1 && unhides == 0, "hidden until mouse moves hides once (%d, %d)", hides, unhides);
        [NSCursor setHiddenUntilMouseMoves: YES]; sample();
        CHECK(hides == 1, "asking again does not hide twice (%d)", hides);

        [display pointerMoved]; sample();
        CHECK(hides == 1 && unhides == 1, "motion brings the cursor back (%d, %d)", hides, unhides);
        [display pointerMoved]; sample();
        CHECK(unhides == 1, "a second motion does not unhide again (%d)", unhides);

        [NSCursor setHiddenUntilMouseMoves: YES]; sample();
        [NSCursor setHiddenUntilMouseMoves: NO]; sample();
        CHECK(hides == 2 && unhides == 2, "setting NO unhides (%d, %d)", hides, unhides);
        [NSCursor setHiddenUntilMouseMoves: NO]; sample();
        CHECK(unhides == 2, "setting NO with nothing pending does nothing (%d)", unhides);
        [display pointerMoved]; sample();
        CHECK(unhides == 2, "and motion after NO does not unhide (%d)", unhides);

        // Hide is counted: an explicit hide is not undone by motion, and does not undo a pending hide.
        hides = unhides = 0;
        [NSCursor hide]; sample();
        CHECK(hides == 1, "explicit hide hides (%d)", hides);
        [NSCursor setHiddenUntilMouseMoves: YES]; sample();
        CHECK(hides == 1, "hidden until mouse moves while already hidden does not hide again (%d)", hides);
        [display pointerMoved]; sample();
        CHECK(unhides == 0, "motion does not undo the explicit hide (%d)", unhides);
        [NSCursor unhide]; sample();
        CHECK(unhides == 1, "the matching unhide shows the cursor (%d)", unhides);
        [NSCursor unhide]; sample();
        CHECK(unhides == 1, "an unhide with nothing hidden does nothing (%d)", unhides);

        // The other order: pending hide-until-motion, then an explicit hide.
        hides = unhides = 0;
        [NSCursor setHiddenUntilMouseMoves: YES]; sample();
        [NSCursor hide]; sample();
        [display pointerMoved]; sample();
        CHECK(hides == 1 && unhides == 0, "motion leaves the explicitly hidden cursor hidden (%d, %d)", hides, unhides);
        [NSCursor unhide]; sample();
        CHECK(unhides == 1, "and the explicit unhide shows it (%d)", unhides);

        // An explicit hide with no hide-until-motion pending is not undone by motion either.
        hides = unhides = 0;
        [NSCursor hide]; sample();
        [display pointerMoved]; sample();
        CHECK(hides == 1 && unhides == 0, "motion does not undo a lone explicit hide (%d, %d)", hides, unhides);
        [NSCursor unhide]; sample();
        CHECK(unhides == 1, "and the explicit unhide restores it (%d)", unhides);
    }
    if (failures) {
        printf("%d check(s) FAILED\n", failures);
        return 1;
    }
    printf("PASS\n");
    return 0;
}
