#import <AppKit/AppKit.h>
#include <stdio.h>

@interface NSScrollerImpPair : NSObject
@property NSScrollerStyle scrollerStyle;
@property (retain) id verticalScrollerImp;
@property (retain) id horizontalScrollerImp;
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
        NSScroller *vertical = [[NSScroller alloc]
                initWithFrame: NSMakeRect(0, 0, 15, 100)];
        NSScroller *horizontal = [[NSScroller alloc]
                initWithFrame: NSMakeRect(0, 0, 100, 15)];
        [pair setVerticalScrollerImp: vertical];
        [pair setHorizontalScrollerImp: horizontal];
        passed &= [pair verticalScrollerImp] == vertical
               && [pair horizontalScrollerImp] == horizontal;
        [vertical release];
        [horizontal release];
        [pair release];
        printf("scroller imp pair style: %s\n", passed ? "PASS" : "FAIL");
        return passed ? 0 : 1;
    }
}
