#import <AppKit/AppKit.h>
#include <stdlib.h>

// NSButtonCell's inset for its bezel, private to AppKit.
@interface NSButtonCell (ControlSizeAdjustment)
- (NSRect) getControlSizeAdjustment: (BOOL) flipped;
@end

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
        expect(NSControlSizeLarge == 3 && NSControlSizeExtraLarge == 4, @"NSControlSize values");

        NSButton *button = [[NSButton alloc] initWithFrame:NSMakeRect(0, 0, 80, 30)];
        [button setControlSize:NSControlSizeExtraLarge];
        expect([button controlSize] == NSControlSizeExtraLarge && [[button cell] controlSize] == NSControlSizeExtraLarge,
               @"controlSize is stored on the control and its cell");

        // Large sizes get the regular font size rather than shrinking below Mini's.
        CGFloat regular = [NSFont systemFontSizeForControlSize:NSControlSizeRegular];
        expect([[[button cell] font] pointSize] == regular, @"extra large cell font size");
        [button setControlSize:NSControlSizeLarge];
        expect([[[button cell] font] pointSize] == regular, @"large cell font size");
        [button setControlSize:NSControlSizeMini];
        expect([[[button cell] font] pointSize] == [NSFont systemFontSizeForControlSize:NSControlSizeMini],
               @"mini cell font size");

        NSButton *push = [[NSButton alloc] initWithFrame:NSMakeRect(0, 0, 80, 30)];
        [push setButtonType:NSButtonTypeMomentaryPushIn];
        [push setBezelStyle:NSBezelStyleRounded];
        NSButtonCell *pushCell = [push cell];
        NSRect regularInset = [pushCell getControlSizeAdjustment:NO];
        NSRect regularFlipped = [pushCell getControlSizeAdjustment:YES];
        expect(regularFlipped.origin.y == -3, @"flipped regular bezel inset is signed");
        for (NSControlSize size = NSControlSizeLarge; size <= NSControlSizeExtraLarge; size++)
        {
            [pushCell setControlSize:size];
            expect(NSEqualRects([pushCell getControlSizeAdjustment:NO], regularInset) &&
                       NSEqualRects([pushCell getControlSizeAdjustment:YES], regularFlipped),
                   [NSString stringWithFormat:@"bezel inset for size %lu", (unsigned long)size]);
        }

        NSTextFieldCell *cell = [[NSTextFieldCell alloc] initTextCell:@"x"];
        [cell setControlSize:NSControlSizeExtraLarge];
        NSData *data = [NSKeyedArchiver archivedDataWithRootObject:cell];
        NSTextFieldCell *decoded = [NSKeyedUnarchiver unarchiveObjectWithData:data];
        expect([decoded controlSize] == NSControlSizeExtraLarge, @"controlSize survives keyed archiving");

        NSLog(@"PASS appkit-control-size-extra-large");
    }
    return 0;
}
