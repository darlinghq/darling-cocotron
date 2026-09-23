#import <AppKit/AppKit.h>
#include <stdlib.h>

static void expect(BOOL condition, NSString *message)
{
    if (!condition)
    {
        NSLog(@"FAIL: %@", message);
        exit(1);
    }
}

int main(void)
{
    @autoreleasepool
    {
        expect(NSControlSizeRegular == 0 && NSControlSizeSmall == 1 && NSControlSizeMini == 2 &&
                   NSControlSizeLarge == 3 && NSSmallControlSize == NSControlSizeSmall,
               @"NSControlSize values and legacy names");
        expect(NSProgressIndicatorStyleBar == 0 && NSProgressIndicatorStyleSpinning == 1 &&
                   NSProgressIndicatorSpinningStyle == NSProgressIndicatorStyleSpinning,
               @"NSProgressIndicatorStyle values and legacy names");

        NSProgressIndicator *indicator = [[NSProgressIndicator alloc] initWithFrame:NSMakeRect(0, 0, 20, 20)];
        indicator.style = NSProgressIndicatorStyleSpinning;
        expect(indicator.style == NSProgressIndicatorStyleSpinning, @"progress indicator style is stored");

        id<NSHapticFeedbackPerformer> performer = NSHapticFeedbackManager.defaultPerformer;
        expect(performer != nil && performer == [NSHapticFeedbackManager defaultPerformer],
               @"defaultPerformer class property");
        [performer performFeedbackPattern:NSHapticFeedbackPatternAlignment
                          performanceTime:NSHapticFeedbackPerformanceTimeDefault];

        NSWindowController *controller = [[NSWindowController alloc] initWithWindowNibName:@"Main"];
        expect([controller.windowNibName isEqual:@"Main"], @"windowNibName property");

        NSView *view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 10, 10)];
        expect([view contentHuggingPriorityForOrientation:NSLayoutConstraintOrientationHorizontal] ==
                       NSLayoutPriorityDefaultLow &&
                   [view contentHuggingPriorityForOrientation:NSLayoutConstraintOrientationVertical] ==
                       NSLayoutPriorityDefaultLow,
               @"default hugging priority is 250");
        expect([view contentCompressionResistancePriorityForOrientation:NSLayoutConstraintOrientationHorizontal] ==
                       NSLayoutPriorityDefaultHigh &&
                   [view contentCompressionResistancePriorityForOrientation:NSLayoutConstraintOrientationVertical] ==
                       NSLayoutPriorityDefaultHigh,
               @"default compression resistance is 750");
        [view setContentHuggingPriority:600 forOrientation:NSLayoutConstraintOrientationVertical];
        [view setContentCompressionResistancePriority:NSLayoutPriorityRequired
                                       forOrientation:NSLayoutConstraintOrientationHorizontal];
        expect([view contentHuggingPriorityForOrientation:NSLayoutConstraintOrientationVertical] == 600 &&
                   [view contentHuggingPriorityForOrientation:NSLayoutConstraintOrientationHorizontal] ==
                       NSLayoutPriorityDefaultLow &&
                   [view contentCompressionResistancePriorityForOrientation:NSLayoutConstraintOrientationHorizontal] ==
                       NSLayoutPriorityRequired,
               @"priorities are stored per orientation");

        NSLog(@"PASS: AppKit Swift-nested enums, nib names, haptics and layout priorities");
    }
    return 0;
}
