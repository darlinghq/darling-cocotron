// Copyright (C) 2026 Lubos Dolezel
//
// Loads a nib that ibtool compiled (NIBArchive format) from tests/fixtures/Fixture.xib,
// and checks what instantiating it gives: three top-level objects (window, menu,
// application placeholder), outlets and action connected to the file's owner, and a
// custom view of an unknown class loaded as a plain NSView.
//
// Usage: appkit-nibarchive-ibtool-fixture <path to Fixture.nib>
// Build: clang -fobjc-arc -framework AppKit appkit-nibarchive-ibtool-fixture.m
#import <AppKit/AppKit.h>
#include <stdio.h>

@interface FixtureOwner : NSObject
@property (strong) IBOutlet NSWindow *window;
@property (strong) IBOutlet NSTextField *label;
- (IBAction)press:(id)sender;
@end
@implementation FixtureOwner
- (IBAction)press:(id)sender {}
@end

static int failures;
#define CHECK(c) do { if (!(c)) { fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #c); failures++; } } while (0)

int main(int argc, char **argv) {
    @autoreleasepool {
        if (argc < 2) { fprintf(stderr, "usage: %s Fixture.nib\n", argv[0]); return 2; }
        [NSApplication sharedApplication];
        NSData *data = [NSData dataWithContentsOfFile:[NSString stringWithUTF8String:argv[1]]];
        CHECK([data length] > 10 && memcmp([data bytes], "NIBArchive", 10) == 0);
        NSNib *nib = [[NSNib alloc] initWithContentsOfURL:[NSURL fileURLWithPath:[NSString stringWithUTF8String:argv[1]]]];
        CHECK(nib != nil);
        FixtureOwner *owner = [FixtureOwner new];
        NSArray *top = nil;
        BOOL ok = [nib instantiateWithOwner:owner topLevelObjects:&top];
        CHECK(ok);
        NSWindow *window = nil; NSMenu *menu = nil;
        for (id o in top) {
            if ([o isKindOfClass:[NSWindow class]]) window = o;
            if ([o isKindOfClass:[NSMenu class]]) menu = o;
        }
        CHECK([top count] == 3);
        CHECK(window != nil && owner.window == window);
        CHECK([window.title isEqualToString:@"Fixture Window"]);
        CHECK([owner.label.stringValue isEqualToString:@"Hello from a fixture"]);
        NSButton *button = nil; NSView *custom = nil;
        for (NSView *v in [window.contentView subviews]) {
            if ([v isKindOfClass:[NSButton class]]) button = (NSButton *)v;
            if (![v isKindOfClass:[NSButton class]] && ![v isKindOfClass:[NSTextField class]]) custom = v;
        }
        CHECK(button != nil && button.action == @selector(press:) && button.target == owner);
        CHECK(custom != nil && [custom class] == [NSView class]);
        CHECK(menu != nil && [menu numberOfItems] == 3);
        CHECK([[menu itemAtIndex:1] isSeparatorItem]);
        CHECK([[menu itemAtIndex:2] state] == NSControlStateValueOn && [[menu itemAtIndex:2] tag] == 7);
        if (!failures) puts("PASS");
    }
    return failures ? 1 : 0;
}
