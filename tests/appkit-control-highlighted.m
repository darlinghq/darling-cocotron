/*
 * Copyright (C) 2026 Lubos Dolezel
 *
 * NSControl's highlighted property (macOS 10.10): it reads and sets the
 * highlighted state of the control's cell, for any control, including
 * subclasses that do not override it. The program builds and runs on macOS
 * too, where the same expectations hold (macOS 26.7.3).
 */
#import <AppKit/AppKit.h>
#include <stdio.h>

static int failures;

static void expect(BOOL ok, const char *what)
{
    printf("%s %s\n", ok ? "PASS" : "FAIL", what);
    if (!ok)
        failures++;
}

@interface MyPopUpButton : NSPopUpButton
@end
@implementation MyPopUpButton
@end

static void checkControl(NSControl *control, const char *name)
{
    char what[160];
    snprintf(what, sizeof what, "%s responds to -isHighlighted and -setHighlighted:", name);
    expect([control respondsToSelector:@selector(isHighlighted)] &&
               [control respondsToSelector:@selector(setHighlighted:)],
           what);
    snprintf(what, sizeof what, "%s is not highlighted at first", name);
    expect(![control isHighlighted], what);
    [control setHighlighted:YES];
    snprintf(what, sizeof what, "%s: -setHighlighted:YES highlights the cell", name);
    expect([control isHighlighted] && [[control cell] isHighlighted], what);
    [[control cell] setHighlighted:NO];
    snprintf(what, sizeof what, "%s: -isHighlighted follows the cell", name);
    expect(![control isHighlighted], what);
}

int main(void)
{
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSRect frame = NSMakeRect(0, 0, 100, 24);
        checkControl([[NSButton alloc] initWithFrame:frame], "NSButton");
        checkControl([[NSTextField alloc] initWithFrame:frame], "NSTextField");
        checkControl([[MyPopUpButton alloc] initWithFrame:frame pullsDown:NO], "an NSPopUpButton subclass");
        checkControl([[NSSlider alloc] initWithFrame:frame], "NSSlider");
    }
    printf("%s\n", failures ? "FAIL" : "PASS");
    return failures ? 1 : 0;
}
