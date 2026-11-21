// Copyright (C) 2026 Lubos Dolezel
// A slider subclass that replaces its cell with a custom NSSliderCell subclass, copying the old
// cell's settings through the public properties (the orientation with -setVertical:, available
// since macOS 10.12), keeps a working cell and draws its track and knob. A new slider reports the
// orientation of its frame before it is drawn; the orientation set on a cell or slider stays when
// the frame changes.
// -init does not go through -initImageCell: or -initTextCell: for NSCell, NSActionCell,
// NSSliderCell, NSImageCell, NSSegmentedCell, NSLevelIndicatorCell and NSStepperCell, so a subclass
// that refuses those initializers still gets a cell from -init; text cells such as NSTextFieldCell
// are created with -initTextCell:@"".
#import <Cocoa/Cocoa.h>
#import <objc/runtime.h>
#include <stdio.h>
#include <string.h>

static int failures;
#define CHECK(condition) do { if (!(condition)) { \
    fprintf(stderr, "failed line %d: %s\n", __LINE__, #condition); failures++; \
} } while (0)

@interface SmallSliderCell : NSSliderCell
@end
@implementation SmallSliderCell
// Only -init is meant to be used for this cell.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wobjc-designated-initializers"
- (instancetype)initImageCell:(NSImage *)image { [self release]; return nil; }
- (instancetype)initTextCell:(NSString *)string { [self release]; return nil; }
#pragma clang diagnostic pop
- (NSControlSize)controlSize { return NSControlSizeSmall; }
- (NSInteger)numberOfTickMarks { return 0; }
@end

@interface ReplacingSlider : NSSlider
@end
@implementation ReplacingSlider
- (instancetype)initWithFrame:(NSRect)frame
{
    if ((self = [super initWithFrame:frame]) == nil)
        return nil;
    NSSliderCell *old = [self cell];
    SmallSliderCell *cell = [[SmallSliderCell alloc] init];
    @try {
        [cell setSliderType:[old sliderType]];
        [cell setMinValue:[old minValue]];
        [cell setMaxValue:[old maxValue]];
        [cell setAltIncrementValue:[old altIncrementValue]];
        [cell setVertical:[old isVertical] == 1];
        [cell setTickMarkPosition:[old tickMarkPosition]];
        [cell setNumberOfTickMarks:[old numberOfTickMarks]];
        [cell setAllowsTickMarkValuesOnly:[old allowsTickMarkValuesOnly]];
        [cell setTarget:[old target]];
        [cell setAction:[old action]];
        [cell setEnabled:[old isEnabled]];
        [cell setContinuous:[old isContinuous]];
        [cell setDoubleValue:[old doubleValue]];
        [self setCell:cell];
    } @catch (NSException *exception) {
        fprintf(stderr, "replacing the cell raised %s\n", [[exception reason] UTF8String]);
        failures++;
    }
    return self;
}
@end

static int textInits, imageInits;
static NSString *lastTextInit;
static id refuseTextCell(id self, SEL _cmd, NSString *string)
{
    textInits++;
    [lastTextInit release];
    lastTextInit = [string copy];
    return nil;
}
static id refuseImageCell(id self, SEL _cmd, NSImage *image) { imageInits++; return nil; }

// Creates a subclass of base whose -initTextCell: and -initImageCell: return nil, then sends it -init.
static id initRefusingSubclass(Class base)
{
    char name[128];
    snprintf(name, sizeof name, "Refusing%s", class_getName(base));
    Class subclass = objc_getClass(name);
    if (subclass == Nil) {
        subclass = objc_allocateClassPair(base, name, 0);
        class_addMethod(subclass, @selector(initTextCell:), (IMP) refuseTextCell, "@@:@");
        class_addMethod(subclass, @selector(initImageCell:), (IMP) refuseImageCell, "@@:@");
        objc_registerClassPair(subclass);
    }
    textInits = imageInits = 0;
    return [[subclass alloc] init];
}

static long paintedPixels(NSView *view)
{
    NSBitmapImageRep *rep = [view bitmapImageRepForCachingDisplayInRect:[view bounds]];
    [view cacheDisplayInRect:[view bounds] toBitmapImageRep:rep];
    long painted = 0;
    for (NSInteger y = 0; y < [rep pixelsHigh]; y++) {
        for (NSInteger x = 0; x < [rep pixelsWide]; x++) {
            NSUInteger pixel[4] = {0};
            [rep getPixel:pixel atX:x y:y];
            if ([rep samplesPerPixel] < 4 || pixel[3] > 0)
                painted++;
        }
    }
    return painted;
}

int main(void)
{
    @autoreleasepool {
        [NSApplication sharedApplication];

        // 0. -init does not go through the other initializers.
        Class imageLike[] = {[NSCell class], [NSActionCell class], [NSSliderCell class], [NSImageCell class],
                             [NSSegmentedCell class], [NSLevelIndicatorCell class], [NSStepperCell class]};
        for (size_t i = 0; i < sizeof imageLike / sizeof *imageLike; i++) {
            id cell = initRefusingSubclass(imageLike[i]);
            if (cell == nil || textInits != 0 || imageInits != 0)
                fprintf(stderr, "%s: init %s, initTextCell: %d, initImageCell: %d\n", class_getName(imageLike[i]),
                        cell ? "object" : "nil", textInits, imageInits);
            CHECK(cell != nil);
            CHECK(textInits == 0 && imageInits == 0);
            CHECK([cell isEnabled]);
        }
        id sliderCell = initRefusingSubclass([NSSliderCell class]);
        CHECK([sliderCell minValue] == 0 && [sliderCell maxValue] == 1);
        CHECK([sliderCell isContinuous]);
        NSSegmentedCell *segmentedCell = [[NSSegmentedCell alloc] init];
        [segmentedCell setSegmentCount:3];
        [segmentedCell setLabel:@"Two" forSegment:1];
        CHECK([segmentedCell segmentCount] == 3);
        CHECK([[segmentedCell labelForSegment:1] isEqualToString:@"Two"]);
        id textCell = initRefusingSubclass([NSTextFieldCell class]);
        CHECK(textCell == nil);
        CHECK(textInits == 1 && imageInits == 0);
        CHECK([lastTextInit isEqualToString:@""]);

        // 1. The replaced cell is in place with the old cell's settings.
        ReplacingSlider *slider = [[ReplacingSlider alloc] initWithFrame:NSMakeRect(0, 0, 80, 21)];
        CHECK([[slider cell] isKindOfClass:[SmallSliderCell class]]);
        CHECK([slider minValue] == 0 && [slider maxValue] == 1);
        CHECK([slider isEnabled]);
        CHECK([[slider cell] isVertical] == 0);
        [slider setDoubleValue:0.5];
        CHECK([slider doubleValue] == 0.5);

        // 2. It draws its track and knob.
        NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 120, 60) styleMask:NSWindowStyleMaskTitled
                                                        backing:NSBackingStoreBuffered defer:YES];
        [[window contentView] addSubview:slider];
        long painted = paintedPixels(slider);
        fprintf(stderr, "painted %ld of %d pixels\n", painted, 80 * 21);
        CHECK(painted > 80 * 21 / 10);

        // 3. A new slider knows its orientation from its frame before it is drawn, and a set
        // orientation stays when the frame changes.
        NSSlider *tall = [[NSSlider alloc] initWithFrame:NSMakeRect(0, 0, 20, 100)];
        CHECK([tall isVertical] == 1);
        CHECK([[[NSSlider alloc] initWithFrame:NSMakeRect(0, 0, 100, 20)] isVertical] == 0);
        NSSliderCell *cell = [[NSSliderCell alloc] init];
        [cell setVertical:YES];
        CHECK([cell isVertical] == 1);
        [cell setVertical:NO];
        CHECK([cell isVertical] == 0);
        NSSlider *wide = [[NSSlider alloc] initWithFrame:NSMakeRect(0, 0, 100, 20)];
        [wide setVertical:YES];
        CHECK([wide isVertical] == 1);
        CHECK([[wide cell] isVertical] == 1);
        [wide setFrameSize:NSMakeSize(120, 20)];
        [[window contentView] addSubview:wide];
        paintedPixels(wide);
        CHECK([wide isVertical] == 1);
    }
    if (failures == 0)
        printf("PASS\n");
    return failures ? 1 : 0;
}
