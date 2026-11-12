// Copyright (C) 2026 Lubos Dolezel
//
// Documented NSControl, NSCell, NSButton and NSWindow properties that were
// missing, and the private image and appearance helpers AppKit clients call:
//  - -[NSControl controlSize] forwards to the cell
//  - -[NSCell menu] is kept, copied with the cell and returned by menuForEvent:inRect:ofView:
//  - -[NSButton contentTintColor] is stored
//  - NSWindow titlebar accessory view controllers are stored in order
//  - -[NSWindow hasCloseBox] follows the closable style bit
//  - +[NSImage _imageWithSystemSymbolName:], -[NSBundle imageForResource:]
//  - +[NSAppearance colorByAdjustingLightnessOfColor:darker:] moves towards black/white
#import <AppKit/AppKit.h>
#include <stdio.h>

@interface NSImage (Private)
+ (instancetype)_imageWithSystemSymbolName:(NSString *)name;
@end
@interface NSAppearance (Private)
+ (NSColor *)colorByAdjustingLightnessOfColor:(NSColor *)color darker:(BOOL)darker;
@end
@interface NSWindow (Scripting)
- (BOOL)hasCloseBox;
@end

static int failures;
#define CHECK(c) do { if (!(c)) { fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #c); failures++; } } while (0)

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];

        NSButton *button = [[NSButton alloc] initWithFrame:NSMakeRect(0, 0, 80, 24)];
        [button setControlSize:NSSmallControlSize];
        CHECK([button controlSize] == NSSmallControlSize);
        CHECK([[button cell] controlSize] == NSSmallControlSize);

        NSMenu *menu = [[NSMenu alloc] initWithTitle:@"cell menu"];
        NSCell *cell = [[NSCell alloc] initTextCell:@"x"];
        CHECK([cell menu] == nil);
        [cell setMenu:menu];
        CHECK([cell menu] == menu);
        NSCell *copy = [cell copy];
        CHECK([copy menu] == menu);
        CHECK([cell menuForEvent:nil inRect:NSMakeRect(0, 0, 1, 1) ofView:nil] == menu);

        NSColor *tint = [NSColor redColor];
        CHECK([button contentTintColor] == nil);
        [button setContentTintColor:tint];
        CHECK([[button contentTintColor] isEqual:tint]);
        [button setContentTintColor:nil];
        CHECK([button contentTintColor] == nil);

        NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 100, 100)
                styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
                  backing:NSBackingStoreBuffered defer:YES];
        CHECK([[window titlebarAccessoryViewControllers] count] == 0);
        NSTitlebarAccessoryViewController *a = [NSTitlebarAccessoryViewController new];
        NSTitlebarAccessoryViewController *b = [NSTitlebarAccessoryViewController new];
        [window addTitlebarAccessoryViewController:a];
        [window addTitlebarAccessoryViewController:b];
        NSArray *accessories = [window titlebarAccessoryViewControllers];
        CHECK([accessories count] == 2 && accessories[0] == a && accessories[1] == b);
        CHECK([window hasCloseBox]);
        [window setStyleMask:NSWindowStyleMaskTitled];
        CHECK(![window hasCloseBox]);

        CHECK([NSImage _imageWithSystemSymbolName:@"gear"] != nil);
        CHECK([[NSBundle mainBundle] imageForResource:@"no-such-image-resource"] == nil);

        NSColor *gray = [NSColor colorWithCalibratedWhite:0.5 alpha:1];
        NSColor *darker = [NSAppearance colorByAdjustingLightnessOfColor:gray darker:YES];
        NSColor *lighter = [NSAppearance colorByAdjustingLightnessOfColor:gray darker:NO];
        CGFloat dw = 0.5, lw = 0.5;
        [[darker colorUsingColorSpace:[NSColorSpace sRGBColorSpace]] getRed:&dw green:NULL blue:NULL alpha:NULL];
        [[lighter colorUsingColorSpace:[NSColorSpace sRGBColorSpace]] getRed:&lw green:NULL blue:NULL alpha:NULL];
        CHECK(dw < 0.5 && lw > 0.5);

        if (!failures) puts("PASS");
    }
    return failures ? 1 : 0;
}
