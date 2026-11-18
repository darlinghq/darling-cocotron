// Copyright (C) 2026 Lubos Dolezel
//
// A tab view decoded from a keyed archive (a nib) takes the font stored in the archive, at every
// control size, and has no font of its own when the archive carries none. Both as observed with the
// tab views of macOS 10.14.4, whose keyed archives were decoded with and without the font key
// at the regular, small and mini control sizes (black-box). The tab view is not given a bold
// default.
// Build: clang -fobjc-arc -framework AppKit appkit-tabview-archived-font.m
#import <AppKit/AppKit.h>
#include <stdio.h>

static int failures;
#define CHECK(c) do { if (!(c)) { fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #c); failures++; } } while (0)

// Stands in for NSTabView in an archive: the flag word and optionally the font are stored.
@interface TabViewStandIn : NSObject <NSCoding> {
@public
    int flags;
    NSFont *font;
}
@end
@implementation TabViewStandIn
- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeInt:flags forKey:@"NSTvFlags"];
    [coder encodeObject:@[] forKey:@"NSTabViewItems"];
    if (font)
        [coder encodeObject:font forKey:@"NSFont"];
}
- (id)initWithCoder:(NSCoder *)coder { return [super init]; }
@end

static NSTabView *decoded(NSControlSize size, NSFont *font) {
    TabViewStandIn *standIn = [TabViewStandIn new];
    standIn->flags = (int) size << 27;
    standIn->font = font;
    NSMutableData *data = [NSMutableData data];
    NSKeyedArchiver *archiver = [[NSKeyedArchiver alloc] initForWritingWithMutableData:data];
    [archiver setClassName:@"NSTabView" forClass:[TabViewStandIn class]];
    [archiver encodeObject:standIn forKey:@"root"];
    [archiver finishEncoding];
    NSKeyedUnarchiver *unarchiver = [[NSKeyedUnarchiver alloc] initForReadingWithData:data];
    return [unarchiver decodeObjectForKey:@"root"];
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSControlSize sizes[] = { NSRegularControlSize, NSSmallControlSize, NSMiniControlSize };
        for (int i = 0; i < 3; i++) {
            CGFloat pt = [NSFont systemFontSizeForControlSize:sizes[i]];
            NSFont *regular = [NSFont systemFontOfSize:pt];
            NSTabView *tabView = decoded(sizes[i], regular);
            CHECK([tabView controlSize] == sizes[i]);
            CHECK([[tabView font] isEqual:regular]);
            CHECK(!([[NSFontManager sharedFontManager] traitsOfFont:[tabView font]] & NSBoldFontMask));

            // a font from the archive is kept as it is, whatever the control size
            NSFont *other = [NSFont fontWithName:@"Helvetica" size:17];
            if (other)
                CHECK([[decoded(sizes[i], other) font] isEqual:other]);

            // QUIRK: with no font key the font is nil (test of the quirk in NSTabView)
            CHECK([decoded(sizes[i], nil) font] == nil);
        }
    }
    if (failures) return 1;
    printf("PASS\n");
    return 0;
}
