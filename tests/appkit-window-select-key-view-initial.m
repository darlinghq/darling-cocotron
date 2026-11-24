// CFLAGS: -framework Foundation -framework AppKit
//
// -[NSWindow selectNextKeyView:] and -selectPreviousKeyView:. With a view as the first responder the next
// (previous) valid key view of that view takes the focus; with none the first responder stays (no fallback
// to the initial first responder, a view at the end of a chain stays focused). With the window itself as
// the first responder (as after -makeFirstResponder:nil) the initial first responder is chosen when it
// accepts first responder status, otherwise its next (previous) valid key view, and without an initial first
// responder the first (last) valid key view of the loop through the content view. While a text field is
// edited the first responder is its field editor, which is outside the loop: the calls change nothing then.
// Evidence: black-box observation on macOS 26.7.3 and 10.14.4 (tier 2, mac-probes p794b and p794d).
//
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

@interface KeyView : NSView {
  @public
    BOOL accepts;
}
@end
@implementation KeyView
- (BOOL) acceptsFirstResponder {
    return accepts;
}
@end

static KeyView *makeView(NSWindow *window, BOOL accepts)
{
    KeyView *view = [[[KeyView alloc] initWithFrame: NSMakeRect(0, 0, 10, 10)] autorelease];
    view->accepts = accepts;
    [[window contentView] addSubview: view];
    return view;
}

// The key view with the focus: the control that a field editor is editing, or the first responder.
static id focusedView(NSWindow *window)
{
    id responder = [window firstResponder];
    if ([responder isKindOfClass: [NSText class]] && [responder isFieldEditor])
        return [responder delegate];
    return responder;
}

static NSWindow *makeWindow(void)
{
    NSWindow *window = [[NSWindow alloc] initWithContentRect: NSMakeRect(0, 0, 200, 200)
                                                   styleMask: NSWindowStyleMaskTitled
                                                     backing: NSBackingStoreBuffered
                                                       defer: YES];
    [window setAutorecalculatesKeyViewLoop: NO];
    return window;
}

int main(void)
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    [NSApplication sharedApplication];

    // A loop a -> b -> c -> a, initial first responder b.
    NSWindow *window = makeWindow();
    KeyView *a = makeView(window, YES), *b = makeView(window, YES), *c = makeView(window, YES);
    [a setNextKeyView: b];
    [b setNextKeyView: c];
    [c setNextKeyView: a];
    [window setInitialFirstResponder: b];

    [window makeFirstResponder: nil];
    expect([window firstResponder] == window, "the window is its own first responder");
    [window selectNextKeyView: nil];
    expect([window firstResponder] == b, "next from the window: the initial first responder");

    [window makeFirstResponder: nil];
    [window selectPreviousKeyView: nil];
    expect([window firstResponder] == b, "previous from the window: the initial first responder");

    // The initial first responder is only the fallback: the view's own next one wins.
    [window setInitialFirstResponder: c];
    [window makeFirstResponder: a];
    [window selectNextKeyView: nil];
    expect([window firstResponder] == b, "next from a view: its next valid key view");
    [window selectPreviousKeyView: nil];
    expect([window firstResponder] == a, "previous from a view: its previous valid key view");

    // The chain a -> b -> c is not a loop: nothing follows c, and the focus stays on c.
    [c setNextKeyView: nil];
    [window setInitialFirstResponder: a];
    [window makeFirstResponder: c];
    [window selectNextKeyView: nil];
    expect([window firstResponder] == c, "next after the end of a chain: the first responder stays (no fallback)");
    [window makeFirstResponder: a];
    [a setNextKeyView: nil];
    [window selectNextKeyView: nil];
    expect([window firstResponder] == a, "a view with no valid next key view keeps focus");

    // No initial first responder: nothing to start from.
    window = makeWindow();
    a = makeView(window, YES);
    b = makeView(window, YES);
    [a setNextKeyView: b];
    [b setNextKeyView: a];
    [window makeFirstResponder: nil];
    [window selectNextKeyView: nil];
    expect([window firstResponder] == window, "next from the window without an initial first responder: unchanged");
    [window selectPreviousKeyView: nil];
    expect([window firstResponder] == window, "previous from the window without an initial first responder: unchanged");
    [window makeFirstResponder: b];
    [b setNextKeyView: nil];
    [window selectNextKeyView: nil];
    expect([window firstResponder] == b, "no candidate at all: the first responder is kept");

    // An initial first responder that refuses first responder status is only
    // the place to start from: n -> a -> b -> n with initial first responder n.
    window = makeWindow();
    KeyView *n = makeView(window, NO);
    a = makeView(window, YES);
    b = makeView(window, YES);
    [n setNextKeyView: a];
    [a setNextKeyView: b];
    [b setNextKeyView: n];
    [window setInitialFirstResponder: n];
    [window makeFirstResponder: nil];
    [window selectNextKeyView: nil];
    expect([window firstResponder] == a, "next from the window: the next valid key view of a refusing initial first responder");
    [window makeFirstResponder: nil];
    [window selectPreviousKeyView: nil];
    expect([window firstResponder] == b, "previous from the window: the previous valid key view of a refusing initial first responder");

    // Fields f1 -> f2 -> f3 -> f1 with the initial first responder f3. While a field is edited the first
    // responder is the field editor, which has no next key view: nothing changes.
    window = makeWindow();
    NSTextField *f1 = [[[NSTextField alloc] initWithFrame: NSMakeRect(10, 150, 80, 22)] autorelease];
    NSTextField *f2 = [[[NSTextField alloc] initWithFrame: NSMakeRect(10, 100, 80, 22)] autorelease];
    NSTextField *f3 = [[[NSTextField alloc] initWithFrame: NSMakeRect(10, 50, 80, 22)] autorelease];
    for (NSTextField *field in [NSArray arrayWithObjects: f1, f2, f3, nil])
        [[window contentView] addSubview: field];
    [f1 setNextKeyView: f2];
    [f2 setNextKeyView: f3];
    [f3 setNextKeyView: f1];
    [window setInitialFirstResponder: f3];

    [window makeFirstResponder: f1];
    expect([[window firstResponder] isKindOfClass: [NSText class]], "editing f1: the first responder is the field editor");
    [window selectNextKeyView: nil];
    expect(focusedView(window) == f1, "next while f1 is edited: unchanged");
    [window selectPreviousKeyView: nil];
    expect(focusedView(window) == f1, "previous while f1 is edited: unchanged");
    expect([[window firstResponder] isKindOfClass: [NSText class]], "the field editor is still the first responder");

    if (failures == 0)
        puts("ALL PASSED");
    else
        printf("FAILED %d\n", failures);
    [pool drain];
    return failures != 0;
}
