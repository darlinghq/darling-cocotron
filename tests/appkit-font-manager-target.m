#import <AppKit/AppKit.h>
#include <stdio.h>

@interface FontTarget : NSObject {
@public
    NSInteger actions;
    id lastSender;
}
- (void) changeFont: (id) sender;
@end

@implementation FontTarget
- (void) changeFont: (id) sender {
    actions++;
    lastSender = sender;
}
@end

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSFontManager *manager = [[NSFontManager alloc] init];
        FontTarget *target = [FontTarget new];
        BOOL passed = [manager target] == nil;
        [manager setTarget: target];
        passed &= [manager target] == target;
        passed &= [manager sendAction] && target->actions == 1
               && target->lastSender == manager;
        [manager setTarget: nil];
        passed &= [manager target] == nil;
        [target release];
        [manager release];
        printf("font manager target: %s\n", passed ? "PASS" : "FAIL");
        return passed ? 0 : 1;
    }
}
