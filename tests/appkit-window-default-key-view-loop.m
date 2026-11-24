// CFLAGS: -framework Foundation -framework AppKit
// A window that has no key view loop gets one when it is first loaded: the
// documentation of -[NSWindow recalculateKeyViewLoop] says the window calls
// it automatically if the window does not have a key view loop already
// established, and that the recalculated loop follows the geometric order of
// the views (top to bottom, then left to right). That holds whether or not
// -autorecalculatesKeyViewLoop is set. A loop somebody has set up is kept.
// So Tab moves between the text fields of a window built without any
// -setNextKeyView: call.
//
// The program passes unchanged on macOS.
// Prints PASS or FAIL lines, then ALL PASSED or FAILED n.
#import <AppKit/AppKit.h>
#include <stdarg.h>
#include <stdio.h>

static int failures;
static void expect(BOOL ok, const char *format, ...) __attribute__((format(printf, 2, 3)));
static void expect(BOOL ok, const char *format, ...)
{
    va_list ap;
    va_start(ap, format);
    printf("%s ", ok ? "PASS" : "FAIL");
    vprintf(format, ap);
    printf("\n");
    va_end(ap);
    if (!ok)
        failures++;
}

static NSTextField *addField(NSWindow *window, CGFloat y)
{
    NSTextField *field = [[[NSTextField alloc] initWithFrame: NSMakeRect(10, y, 100, 22)] autorelease];
    [[window contentView] addSubview: field];
    return field;
}

static NSWindow *makeWindow(void)
{
    return [[NSWindow alloc] initWithContentRect: NSMakeRect(0, 0, 200, 200)
                                       styleMask: NSWindowStyleMaskTitled
                                         backing: NSBackingStoreBuffered
                                           defer: NO];
}

static NSEvent *tabKey(NSWindow *window)
{
    return [NSEvent keyEventWithType: NSEventTypeKeyDown
                            location: NSZeroPoint
                       modifierFlags: 0
                           timestamp: 0
                        windowNumber: [window windowNumber]
                             context: nil
                          characters: @"\t"
         charactersIgnoringModifiers: @"\t"
                           isARepeat: NO
                             keyCode: 48];
}

static void testNoLoopGetsOne(void)
{
    NSWindow *window = makeWindow();
    // The content view is not flipped: a larger y is higher in the window.
    NSTextField *top = addField(window, 150), *middle = addField(window, 100), *bottom = addField(window, 50);
    expect(![window autorecalculatesKeyViewLoop], "autorecalculatesKeyViewLoop is off by default");

    [window makeKeyAndOrderFront: nil];

    expect([top nextValidKeyView] == middle, "top field is followed by the middle one");
    expect([middle nextValidKeyView] == bottom, "middle field is followed by the bottom one");
    expect([bottom nextValidKeyView] == top, "the loop closes: bottom field is followed by the top one");
    expect([top previousValidKeyView] == bottom, "top field is preceded by the bottom one");

    [window makeFirstResponder: top];
    expect([window firstResponder] == [top currentEditor], "top field is being edited");
    [window sendEvent: tabKey(window)];
    expect([window firstResponder] == [middle currentEditor] && [middle currentEditor] != nil,
           "Tab in the top field edits the middle one");
    [window sendEvent: tabKey(window)];
    expect([window firstResponder] == [bottom currentEditor] && [bottom currentEditor] != nil,
           "Tab in the middle field edits the bottom one");
    [window sendEvent: tabKey(window)];
    expect([window firstResponder] == [top currentEditor] && [top currentEditor] != nil,
           "Tab in the bottom field edits the top one");
    [window close];
}

static void testExistingLoopKept(void)
{
    NSWindow *window = makeWindow();
    NSTextField *a = addField(window, 150), *b = addField(window, 100), *c = addField(window, 50);
    // Not the geometric order.
    [a setNextKeyView: c];
    [c setNextKeyView: b];
    [b setNextKeyView: a];

    [window makeKeyAndOrderFront: nil];

    expect([a nextKeyView] == c && [c nextKeyView] == b && [b nextKeyView] == a,
           "a key view loop that was set up is not replaced");
    [window close];
}

int main(void)
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    [NSApplication sharedApplication];

    testNoLoopGetsOne();
    testExistingLoopKept();

    if (failures == 0)
        puts("ALL PASSED");
    else
        printf("FAILED %d\n", failures);
    [pool drain];
    return failures != 0;
}
