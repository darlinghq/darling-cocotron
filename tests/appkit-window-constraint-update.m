#import <AppKit/AppKit.h>
#include <stdio.h>

@interface ConstraintView : NSView {
@public
    NSInteger updates;
    NSInteger layouts;
}
@end

@implementation ConstraintView
- (void) updateConstraints {
    updates++;
    [super updateConstraints];
}
- (void) layout {
    layouts++;
    [super layout];
}
@end

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSPanel *panel = [[NSPanel alloc] initWithContentRect: NSMakeRect(0, 0, 200, 100)
                                                  styleMask: NSWindowStyleMaskTitled
                                                    backing: NSBackingStoreBuffered defer: NO];
        ConstraintView *parent = [[ConstraintView alloc] initWithFrame: NSMakeRect(0, 0, 200, 100)];
        ConstraintView *child = [[ConstraintView alloc] initWithFrame: NSMakeRect(0, 0, 40, 20)];
        [parent addSubview: child];
        [panel setContentView: parent];
        [parent setNeedsUpdateConstraints: YES];
        [child setNeedsUpdateConstraints: YES];
        [panel updateConstraintsIfNeeded];
        BOOL passed = parent->updates == 1 && child->updates == 1
                   && ![parent needsUpdateConstraints] && ![child needsUpdateConstraints];
        [panel updateConstraintsIfNeeded];
        passed &= parent->updates == 1 && child->updates == 1;
        [child setNeedsUpdateConstraints: YES];
        [parent setNeedsLayout: YES];
        [child setNeedsLayout: YES];
        [panel layoutIfNeeded];
        passed &= child->updates == 2 && parent->updates == 1
               && parent->layouts == 1 && child->layouts == 1;
        [panel release];
        [parent release];
        [child release];
        printf("window constraint update: %s\n", passed ? "PASS" : "FAIL");
        return passed ? 0 : 1;
    }
}
