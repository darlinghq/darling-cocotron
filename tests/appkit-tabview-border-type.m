// Copyright (C) 2026 Lubos Dolezel
//
// NSTabView -tabViewBorderType and -tabPosition. The documentation (macOS 10.12 and later) only
// declares both as read-write properties, of the types NSTabViewBorderType (none, line, bezel) and
// NSTabPosition (none, top, left, bottom, right); it states no default and no behaviour. So the
// round trip of every case, the absence of a raise and the presence of the accessors are the
// documented contract. Everything marked GUESS pins this implementation's choice, not a documented
// or measured value: the defaults (inferred from the names of the tab view type constants: top tabs
// with a bezel border for the default type, no tab position and a line or no border for the no-tab
// types), the same defaults on a tab view decoded from a keyed archive of each type, the same
// values taken again by -setTabViewType: (replacing values set before), and
// NSTabViewBorderTypeNone removing the drawn border.
// Build: clang -fobjc-arc -framework AppKit appkit-tabview-border-type.m
// Not covered: the "Is Currently Unimplemented" log line of -setTabPosition: (NSLog cannot be
// captured here); on master the position round trip already passes, the border type accessors do not
// exist (unrecognized selector), and the decoded tab view has position none instead of top.
#import <AppKit/AppKit.h>
#include <stdio.h>

static int failures;
#define CHECK(c) do { if (!(c)) { fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #c); failures++; } } while (0)

// The receiver that failed in a real application was a subclass of NSTabView.
@interface BorderTabView : NSTabView
- (void)setTabViewBorderType:(NSTabViewBorderType)type;
@end
@implementation BorderTabView
// Wraps the setter the way an application's own override does: it reads the value back first.
- (void)setTabViewBorderType:(NSTabViewBorderType)type {
    (void)[self tabViewBorderType];
    [super setTabViewBorderType:type];
}
@end

// Stands in for NSTabView in an archive. Only the keys the existing decoding reads are written.
static int archivedType;
@interface TabViewStandIn : NSObject <NSCoding>
@end
@implementation TabViewStandIn
- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeInt:archivedType forKey:@"NSTvFlags"];
    [coder encodeObject:@[] forKey:@"NSTabViewItems"];
}
- (id)initWithCoder:(NSCoder *)coder { return [super init]; }
@end

static NSTabView *decoded(NSTabViewType type) {
    archivedType = (int)type;
    NSMutableData *data = [NSMutableData data];
    NSKeyedArchiver *archiver = [[NSKeyedArchiver alloc] initForWritingWithMutableData:data];
    [archiver setClassName:@"NSTabView" forClass:[TabViewStandIn class]];
    [archiver encodeObject:[TabViewStandIn new] forKey:@"root"];
    [archiver finishEncoding];
    NSKeyedUnarchiver *unarchiver = [[NSKeyedUnarchiver alloc] initForReadingWithData:data];
    return [unarchiver decodeObjectForKey:@"root"];
}

static void checkAccessors(NSTabView *view) {
    CHECK([view respondsToSelector:@selector(tabViewBorderType)]);
    CHECK([view respondsToSelector:@selector(setTabViewBorderType:)]);
    CHECK([view respondsToSelector:@selector(tabPosition)]);
    CHECK([view respondsToSelector:@selector(setTabPosition:)]);
}

static void checkRoundTrips(NSTabView *view) {
    const NSTabViewBorderType borders[] = { NSTabViewBorderTypeNone, NSTabViewBorderTypeLine, NSTabViewBorderTypeBezel };
    const NSTabPosition positions[] = { NSTabPositionNone, NSTabPositionTop, NSTabPositionLeft, NSTabPositionBottom,
                                        NSTabPositionRight };

    for (size_t i = 0; i < sizeof borders / sizeof *borders; i++) {
        @try {
            [view setTabViewBorderType:borders[i]];
        } @catch (NSException *e) {
            fprintf(stderr, "FAIL setTabViewBorderType: %d raised %s\n", (int)borders[i], [[e reason] UTF8String]);
            failures++;
        }
        CHECK([view tabViewBorderType] == borders[i]);
    }
    for (size_t i = 0; i < sizeof positions / sizeof *positions; i++) {
        @try {
            [view setTabPosition:positions[i]];
        } @catch (NSException *e) {
            fprintf(stderr, "FAIL setTabPosition: %d raised %s\n", (int)positions[i], [[e reason] UTF8String]);
            failures++;
        }
        CHECK([view tabPosition] == positions[i]);
    }

    // the two properties do not overwrite each other
    [view setTabViewBorderType:NSTabViewBorderTypeLine];
    [view setTabPosition:NSTabPositionBottom];
    CHECK([view tabViewBorderType] == NSTabViewBorderTypeLine);
    CHECK([view tabPosition] == NSTabPositionBottom);
    [view setTabViewBorderType:NSTabViewBorderTypeNone];
    CHECK([view tabPosition] == NSTabPositionBottom);
}

// Alpha of the top-left pixel of a view rendered at 40x40; opaque for a no-tabs line border.
static CGFloat cornerAlpha(NSTabView *view, BOOL *rendered) {
    [view setFrame:NSMakeRect(0, 0, 40, 40)];
    NSBitmapImageRep *rep = [view bitmapImageRepForCachingDisplayInRect:[view bounds]];
    if (rep == nil) {
        *rendered = NO;
        return 0;
    }
    [view cacheDisplayInRect:[view bounds] toBitmapImageRep:rep];
    NSColor *pixel = [rep colorAtX:0 y:0];
    *rendered = pixel != nil;
    return [pixel alphaComponent];
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];

        NSTabView *plain = [[NSTabView alloc] initWithFrame:NSMakeRect(0, 0, 100, 100)];
        BorderTabView *sub = [[BorderTabView alloc] initWithFrame:NSMakeRect(0, 0, 100, 100)];
        NSTabView *fromArchive = decoded(NSTopTabsBezelBorder);
        CHECK(fromArchive != nil);

        for (NSTabView *view in @[ plain, sub, fromArchive ]) {
            checkAccessors(view);
            // GUESS: no documented default; inferred from the constant names of the default
            // tab view type (top tabs, bezel border), also for a view decoded from an archive.
            CHECK([view tabViewBorderType] == NSTabViewBorderTypeBezel);
            CHECK([view tabPosition] == NSTabPositionTop);
            checkRoundTrips(view);
        }

        // GUESS: the defaults of a decoded view follow its archived tab view type, by the names of
        // the type constants. Not measured on macOS.
        static const struct {
            NSTabViewType type;
            NSTabPosition position;
            NSTabViewBorderType border;
        } byType[] = {
            { NSTopTabsBezelBorder, NSTabPositionTop, NSTabViewBorderTypeBezel },
            { NSLeftTabsBezelBorder, NSTabPositionLeft, NSTabViewBorderTypeBezel },
            { NSBottomTabsBezelBorder, NSTabPositionBottom, NSTabViewBorderTypeBezel },
            { NSRightTabsBezelBorder, NSTabPositionRight, NSTabViewBorderTypeBezel },
            { NSNoTabsBezelBorder, NSTabPositionNone, NSTabViewBorderTypeBezel },
            { NSNoTabsLineBorder, NSTabPositionNone, NSTabViewBorderTypeLine },
            { NSNoTabsNoBorder, NSTabPositionNone, NSTabViewBorderTypeNone },
        };
        for (size_t i = 0; i < sizeof byType / sizeof *byType; i++) {
            NSTabView *view = decoded(byType[i].type);
            CHECK([view tabViewType] == byType[i].type);
            CHECK([view tabPosition] == byType[i].position);
            CHECK([view tabViewBorderType] == byType[i].border);

            // GUESS: -setTabViewType: derives both values again, from every starting type
            for (size_t j = 0; j < sizeof byType / sizeof *byType; j++) {
                [view setTabViewType:byType[j].type];
                CHECK([view tabViewType] == byType[j].type);
                CHECK([view tabPosition] == byType[j].position);
                CHECK([view tabViewBorderType] == byType[j].border);
            }
        }

        // a tab view saved without a border, given top tabs again, has top tabs and a bezel border
        NSTabView *borderless = decoded(NSNoTabsNoBorder);
        [borderless setTabViewType:NSTopTabsBezelBorder];
        CHECK([borderless tabPosition] == NSTabPositionTop);
        CHECK([borderless tabViewBorderType] == NSTabViewBorderTypeBezel);

        // GUESS: border type none drops the drawn border, any other border type keeps it; skipped
        // when the view cannot be rendered into a bitmap here.
        BOOL rendered = YES;
        NSTabView *drawn = [[NSTabView alloc] initWithFrame:NSMakeRect(0, 0, 40, 40)];
        [drawn setTabViewType:NSNoTabsLineBorder];
        CGFloat withBorder = cornerAlpha(drawn, &rendered);
        if (rendered) {
            CHECK(withBorder > 0.5);
            [drawn setTabViewBorderType:NSTabViewBorderTypeNone];
            CGFloat none = cornerAlpha(drawn, &rendered);
            CHECK(rendered && none < 0.5);
            [drawn setTabViewBorderType:NSTabViewBorderTypeLine];
            CGFloat line = cornerAlpha(drawn, &rendered);
            CHECK(rendered && line > 0.5);

            // GUESS: a view without a border that is given a type with one draws it again
            NSTabView *shown = decoded(NSNoTabsNoBorder);
            CHECK(cornerAlpha(shown, &rendered) < 0.5);
            [shown setTabViewType:NSNoTabsLineBorder];
            CGFloat back = cornerAlpha(shown, &rendered);
            CHECK(rendered && back > 0.5);
        } else {
            printf("SKIP border drawing: no bitmap rendering of the tab view\n");
        }
    }
    if (failures) return 1;
    printf("PASS\n");
    return 0;
}
