// Copyright (C) 2026 Lubos Dolezel
//
// Loads a nib that ibtool compiled (NIBArchive format) from tests/fixtures/Fixture.xib,
// and checks what instantiating it gives: three top-level objects (window, menu,
// application placeholder), outlets and action connected to the file's owner, a
// custom view, and the state and tag of a menu item.
//
// Usage: appkit-nibarchive-ibtool-fixture <path to Fixture.nib>
// Build: clang -fobjc-arc -framework AppKit appkit-nibarchive-ibtool-fixture.m
#import <AppKit/AppKit.h>
#include <stdio.h>

@interface FixtureOwner : NSObject {
    NSWindow *_window;
    NSTextField *_label;
}
@property (strong) IBOutlet NSWindow *window;
@property (strong) IBOutlet NSTextField *label;
- (IBAction)press:(id)sender;
@end
@implementation FixtureOwner
@synthesize window = _window, label = _label;
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
        // -[NSNib initWithContentsOfURL:] is deprecated and raises on current macOS, so load
        // the nib by name from a directory bundle holding it.
        NSString *nibDir = [[NSString stringWithUTF8String:argv[1]] stringByDeletingLastPathComponent];
        NSString *nibName = [[[NSString stringWithUTF8String:argv[1]] lastPathComponent] stringByDeletingPathExtension];
        NSNib *nib = [[NSNib alloc] initWithNibNamed:nibName bundle:[NSBundle bundleWithPath:nibDir]];
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
        // The class an unknown custom view falls back to is covered with the
        // nib decoding fallbacks, not by the reader.
        CHECK(custom != nil);
        CHECK(menu != nil && [menu numberOfItems] == 3);
        CHECK([[menu itemAtIndex:2] state] == NSControlStateValueOn && [[menu itemAtIndex:2] tag] == 7);
        if (!failures) puts("PASS");
    }
    return failures ? 1 : 0;
}
