// Copyright (C) 2026 Lubos Dolezel
//
// NSTabView -tabViewBorderType and -tabPosition. The documentation (macOS 10.12 and later) only
// declares both as read-write properties, of the types NSTabViewBorderType (none, line, bezel) and
// NSTabPosition (none, top, left, bottom, right). Everything else here is black-box behaviour of
// macOS 26.7.3 and Mac OS X 10.14.4 (x86_64 and i386, identical): the tab view type fixes both values
// (QUIRK below), and setting either one can change the type. The test is built from those
// observations and passes on both Macs (on Mojave without a window server).
// Build: clang -fobjc-arc -framework AppKit appkit-tabview-border-type.m
// Not covered: the "Is Currently Unimplemented" log line of -setTabPosition: that master printed (NSLog
// cannot be captured here); on master the border type accessors do not exist (unrecognized selector).
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

static const NSTabViewBorderType borders[] = { NSTabViewBorderTypeNone, NSTabViewBorderTypeLine, NSTabViewBorderTypeBezel };
static const NSTabPosition positions[] = { NSTabPositionNone, NSTabPositionTop, NSTabPositionLeft, NSTabPositionBottom,
                                           NSTabPositionRight };

// QUIRK (macOS 26.7.3 and 10.14.4, probes tabview.m and tabview2.m): the tab view type fixes the tab position
// and the border type: the four types with tabs give their position and a bezel border; the types without
// tabs give position none and a bezel, line or no border.
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
#define NTYPES (sizeof byType / sizeof *byType)

static NSTabView *viewOfType(NSTabViewType type) {
    NSTabView *view = [[NSTabView alloc] initWithFrame:NSMakeRect(0, 0, 100, 100)];
    [view setTabViewType:type];
    return view;
}

static void checkAccessors(NSTabView *view) {
    CHECK([view respondsToSelector:@selector(tabViewBorderType)]);
    CHECK([view respondsToSelector:@selector(setTabViewBorderType:)]);
    CHECK([view respondsToSelector:@selector(tabPosition)]);
    CHECK([view respondsToSelector:@selector(setTabPosition:)]);
}

// Documented: both are read-write properties of the enumerated types. Every value reads back.
static void checkRoundTrips(NSTabView *view) {
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
    [view setTabPosition:NSTabPositionNone];
    CHECK([view tabViewBorderType] == NSTabViewBorderTypeNone);
}

// Sum of the alpha of every pixel of the view rendered at 60x60; negative when it cannot be rendered.
static double alphaSum(NSTabView *view) {
    [view setFrame:NSMakeRect(0, 0, 60, 60)];
    NSBitmapImageRep *rep = [view bitmapImageRepForCachingDisplayInRect:[view bounds]];
    if (rep == nil)
        return -1;
    [view cacheDisplayInRect:[view bounds] toBitmapImageRep:rep];
    double sum = 0;
    for (NSInteger y = 0; y < [rep pixelsHigh]; y++)
        for (NSInteger x = 0; x < [rep pixelsWide]; x++)
            sum += [[rep colorAtX:x y:y] alphaComponent];
    return sum;
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
            // the default type has top tabs and a bezel border
            CHECK([view tabViewType] == NSTopTabsBezelBorder);
            CHECK([view tabViewBorderType] == NSTabViewBorderTypeBezel);
            CHECK([view tabPosition] == NSTabPositionTop);
            checkRoundTrips(view);
        }

        // QUIRK: a view made with, decoded with or given a type has the position and border type of that
        // type, from every starting type
        for (size_t i = 0; i < NTYPES; i++) {
            NSTabView *view = decoded(byType[i].type);
            CHECK([view tabViewType] == byType[i].type);
            CHECK([view tabPosition] == byType[i].position);
            CHECK([view tabViewBorderType] == byType[i].border);
            for (size_t j = 0; j < NTYPES; j++) {
                [view setTabViewType:byType[j].type];
                CHECK([view tabViewType] == byType[j].type);
                CHECK([view tabPosition] == byType[j].position);
                CHECK([view tabViewBorderType] == byType[j].border);
            }
        }

        // QUIRK: setting the position gives the type with that position's tabs, whatever the border type
        // (which stays), and position none gives the type without tabs of the current border type
        for (size_t i = 0; i < NTYPES; i++) {
            for (size_t p = 0; p < sizeof positions / sizeof *positions; p++) {
                NSTabView *view = viewOfType(byType[i].type);
                NSTabViewBorderType border = [view tabViewBorderType];
                [view setTabPosition:positions[p]];
                CHECK([view tabPosition] == positions[p]);
                CHECK([view tabViewBorderType] == border);
                NSTabViewType expected = NSNoTabsBezelBorder;
                switch (positions[p]) {
                case NSTabPositionTop: expected = NSTopTabsBezelBorder; break;
                case NSTabPositionLeft: expected = NSLeftTabsBezelBorder; break;
                case NSTabPositionBottom: expected = NSBottomTabsBezelBorder; break;
                case NSTabPositionRight: expected = NSRightTabsBezelBorder; break;
                default:
                    expected = border == NSTabViewBorderTypeNone ? NSNoTabsNoBorder
                             : border == NSTabViewBorderTypeLine ? NSNoTabsLineBorder : NSNoTabsBezelBorder;
                }
                CHECK([view tabViewType] == expected);
            }
        }

        // QUIRK: setting the border type changes the type only for a view without tabs
        for (size_t i = 0; i < NTYPES; i++) {
            for (size_t b = 0; b < sizeof borders / sizeof *borders; b++) {
                NSTabView *view = viewOfType(byType[i].type);
                [view setTabViewBorderType:borders[b]];
                CHECK([view tabViewBorderType] == borders[b]);
                CHECK([view tabPosition] == byType[i].position);
                NSTabViewType expected = byType[i].type;
                if (byType[i].position == NSTabPositionNone)
                    expected = borders[b] == NSTabViewBorderTypeNone ? NSNoTabsNoBorder
                             : borders[b] == NSTabViewBorderTypeLine ? NSNoTabsLineBorder : NSNoTabsBezelBorder;
                CHECK([view tabViewType] == expected);
            }
        }

        // QUIRK: giving the type back replaces an explicit border type
        NSTabView *borderless = viewOfType(NSTopTabsBezelBorder);
        [borderless setTabViewBorderType:NSTabViewBorderTypeNone];
        [borderless setTabViewType:NSLeftTabsBezelBorder];
        CHECK([borderless tabPosition] == NSTabPositionLeft);
        CHECK([borderless tabViewBorderType] == NSTabViewBorderTypeBezel);

        // QUIRK: what is drawn follows the type: a view without tabs draws nothing for no border, and a line
        // or a bezel for the others (skipped when the view cannot be rendered into a bitmap)
        NSTabView *drawn = viewOfType(NSNoTabsLineBorder);
        double line = alphaSum(drawn);
        if (line >= 0) {
            CHECK(line > 0);
            [drawn setTabViewBorderType:NSTabViewBorderTypeNone];
            CHECK(alphaSum(drawn) == 0);
            [drawn setTabViewBorderType:NSTabViewBorderTypeBezel];
            CHECK(alphaSum(drawn) > 0);
            [drawn setTabViewBorderType:NSTabViewBorderTypeLine];
            CHECK(alphaSum(drawn) == line);
        } else {
            printf("SKIP border drawing: no bitmap rendering of the tab view\n");
        }
    }
    if (failures) return 1;
    printf("PASS\n");
    return 0;
}
