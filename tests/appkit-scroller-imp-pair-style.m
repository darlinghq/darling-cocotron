#import <AppKit/AppKit.h>
#include <stdio.h>

@interface NSScrollerImpPair : NSObject
@property NSScrollerStyle scrollerStyle;
@end

int main(void) {
    @autoreleasepool {
        NSScrollerImpPair *pair = [[NSClassFromString(@"NSScrollerImpPair") alloc] init];
        BOOL passed = pair != nil && [pair scrollerStyle] ==
                [NSScroller preferredScrollerStyle];
        [pair setScrollerStyle: NSScrollerStyleOverlay];
        passed &= [pair scrollerStyle] == NSScrollerStyleOverlay;
        [pair setScrollerStyle: NSScrollerStyleLegacy];
        passed &= [pair scrollerStyle] == NSScrollerStyleLegacy;
        [pair release];
        printf("scroller imp pair style: %s\n", passed ? "PASS" : "FAIL");
        return passed ? 0 : 1;
    }
}
