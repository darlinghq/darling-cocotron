// Copyright (C) 2026 Lubos Dolezel
//
// Loads ibtool-compiled nibs (fixtures/nibarchive/flat, sources in fixtures/nibarchive/src) whose
// objects have custom classes or settings that the plain AppKit classes must support:
//  - Tint.nib: a slider whose cell has a custom class that reads -controlTint in -initWithCoder:.
//    The nib failed to instantiate when NSCell had no -controlTint.
//  - Swap.nib: an image view whose custom class is a plain NSView subclass (macOS instantiates the
//    custom class anyway), and a scroll view whose custom class does not exist (macOS falls back
//    to NSScrollView).
//  - Scroll.nib: scroll views with usesPredominantAxisScrolling off and at its default (on).
// It also checks the control tint's place in a keyed archive of a cell, as written by macOS
// 10.14.4 and 26.7.3 (black-box): NSCellFlags2 bits 19-21, next to the control size in bits 17-18.
// The same checks pass on macOS 26.7.3.
//
// Usage: appkit-nibarchive-custom-classes <fixtures/nibarchive directory>
// Build: clang -framework AppKit appkit-nibarchive-custom-classes.m
#import <AppKit/AppKit.h>
#include <stdio.h>

static int failures;
#define CHECK(c) do { if (!(c)) { fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #c); failures++; } } while (0)

// NSControlTint is deprecated in newer SDKs; these spell it without the warnings.
@interface NSCell (TintAccess)
- (NSUInteger) controlTint;
- (void) setControlTint: (NSUInteger) tint;
@end

static int tintReads;
static NSUInteger tintRead = 99;

@interface TintReadingSliderCell : NSSliderCell
@end
@implementation TintReadingSliderCell
- (instancetype) initWithCoder: (NSCoder *) coder {
    self = [super initWithCoder: coder];
    tintRead = [self controlTint];
    tintReads++;
    return self;
}
@end

@interface TintOwner : NSObject {
@public
    NSSlider *slider;
}
@end
@implementation TintOwner
- (void) setSlider: (NSSlider *) s { slider = s; }
@end

static int artInits, artAwakes;
@interface PlainArtView : NSView
@end
@implementation PlainArtView
- (instancetype) initWithCoder: (NSCoder *) coder {
    self = [super initWithCoder: coder];
    artInits++;
    return self;
}
- (void) awakeFromNib { artAwakes++; }
@end

@interface SwapOwner : NSObject {
@public
    id art, list;
}
@end
@implementation SwapOwner
- (void) setArt: (id) a { art = a; }
- (void) setList: (id) l { list = l; }
@end

@interface ScrollOwner : NSObject {
@public
    NSScrollView *freeAxes, *predominantAxis;
}
@end
@implementation ScrollOwner
- (void) setFreeAxes: (NSScrollView *) s { freeAxes = s; }
- (void) setPredominantAxis: (NSScrollView *) s { predominantAxis = s; }
@end

// Writes an NSCell archive with the given flag words, standing in for one macOS wrote.
@interface CellFlagsArchive : NSObject <NSCoding> {
@public
    unsigned flags, flags2;
}
@end
@implementation CellFlagsArchive
- (void) encodeWithCoder: (NSCoder *) coder {
    [coder encodeInt: (int) flags forKey: @"NSCellFlags"];
    [coder encodeInt: (int) flags2 forKey: @"NSCellFlags2"];
    [coder encodeObject: @"x" forKey: @"NSContents"];
}
- (instancetype) initWithCoder: (NSCoder *) coder { return [super init]; }
@end

static NSCell *cellFromFlags(unsigned flags, unsigned flags2) {
    CellFlagsArchive *source = [[CellFlagsArchive alloc] init];
    source->flags = flags;
    source->flags2 = flags2;
    NSMutableData *data = [NSMutableData data];
    NSKeyedArchiver *archiver = [[NSKeyedArchiver alloc] initForWritingWithMutableData: data];
    [archiver setClassName: @"NSCell" forClass: [CellFlagsArchive class]];
    [archiver encodeObject: source forKey: @"root"];
    [archiver finishEncoding];
    NSKeyedUnarchiver *unarchiver = [[NSKeyedUnarchiver alloc] initForReadingWithData: data];
    NSCell *cell = [unarchiver decodeObjectForKey: @"root"];
    [unarchiver finishDecoding];
    return cell;
}

static BOOL instantiate(NSString *root, NSString *name, id owner, NSArray **top) {
    NSString *path = [[root stringByAppendingPathComponent: @"flat"]
            stringByAppendingPathComponent: [name stringByAppendingPathExtension: @"nib"]];
    NSData *data = [NSData dataWithContentsOfFile: path];
    if (data == nil) {
        fprintf(stderr, "cannot read %s\n", [path UTF8String]);
        return NO;
    }
    NSNib *nib = [[NSNib alloc] initWithNibData: data bundle: nil];
    return [nib instantiateWithOwner: owner topLevelObjects: top];
}

int main(int argc, char **argv) {
    @autoreleasepool {
        if (argc < 2) {
            fprintf(stderr, "usage: %s <fixtures/nibarchive>\n", argv[0]);
            return 2;
        }
        NSString *root = [NSString stringWithUTF8String: argv[1]];
        [NSApplication sharedApplication];

        // A new cell has the default tint, which the setter changes and a copy keeps.
        NSCell *cell = [[NSCell alloc] initTextCell: @"x"];
        CHECK([cell controlTint] == NSDefaultControlTint);
        CHECK([[[NSSliderCell alloc] init] controlTint] == NSDefaultControlTint);
        CHECK([[[NSButtonCell alloc] init] controlTint] == NSDefaultControlTint);
        [cell setControlTint: NSGraphiteControlTint];
        CHECK([cell controlTint] == NSGraphiteControlTint);
        CHECK([[cell copy] controlTint] == NSGraphiteControlTint);
        [cell setControlTint: NSClearControlTint];
        CHECK([cell controlTint] == NSClearControlTint);

        // Flag words as macOS archives them: control size small (1) with tint 7, and the
        // graphite tint (6) at the regular size.
        NSCell *decoded = cellFromFlags(0x04000000, 0x083a0000);
        CHECK(decoded != nil && [decoded controlTint] == 7 && [decoded controlSize] == NSControlSizeSmall);
        decoded = cellFromFlags(0x04000000, 0x08300000);
        CHECK(decoded != nil && [decoded controlTint] == NSGraphiteControlTint &&
              [decoded controlSize] == NSControlSizeRegular);
        decoded = cellFromFlags(0x04000000, 0x08040000);
        CHECK(decoded != nil && [decoded controlTint] == NSDefaultControlTint &&
              [decoded controlSize] == NSControlSizeMini);

        // An archive of a tinted cell keeps the tint and the control size.
        NSCell *tinted = [[NSCell alloc] initTextCell: @"x"];
        [tinted setControlTint: NSBlueControlTint];
        [tinted setControlSize: NSControlSizeSmall];
        NSCell *back = [NSKeyedUnarchiver unarchiveObjectWithData:
                [NSKeyedArchiver archivedDataWithRootObject: tinted]];
        CHECK([back controlTint] == NSBlueControlTint && [back controlSize] == NSControlSizeSmall);

        NSArray *top = nil;
        TintOwner *tintOwner = [TintOwner new];
        CHECK(instantiate(root, @"Tint", tintOwner, &top));
        CHECK(tintReads == 1 && tintRead == NSDefaultControlTint);
        CHECK([[tintOwner->slider cell] isMemberOfClass: [TintReadingSliderCell class]]);

        SwapOwner *swapOwner = [SwapOwner new];
        top = nil;
        CHECK(instantiate(root, @"Swap", swapOwner, &top));
        CHECK([swapOwner->art isMemberOfClass: [PlainArtView class]]);
        CHECK(artInits == 1 && artAwakes == 1);
        CHECK(NSEqualRects([swapOwner->art frame], NSMakeRect(10, 10, 64, 64)));
        CHECK([swapOwner->list isMemberOfClass: [NSScrollView class]]);

        ScrollOwner *scrollOwner = [ScrollOwner new];
        top = nil;
        CHECK(instantiate(root, @"Scroll", scrollOwner, &top));
        CHECK(scrollOwner->freeAxes != nil && ![scrollOwner->freeAxes usesPredominantAxisScrolling]);
        CHECK(scrollOwner->predominantAxis != nil && [scrollOwner->predominantAxis usesPredominantAxisScrolling]);

        NSScrollView *scrollView = [[NSScrollView alloc] initWithFrame: NSMakeRect(0, 0, 50, 50)];
        CHECK([scrollView usesPredominantAxisScrolling]);
        [scrollView setUsesPredominantAxisScrolling: NO];
        CHECK(![scrollView usesPredominantAxisScrolling]);
    }
    if (failures)
        return 1;
    printf("PASS\n");
    return 0;
}
