// Copyright (C) 2026 Lubos Dolezel
//
// Guest test: NSImmediateActionGestureRecognizer, the private NSGestureRecognizer
// subclass that WebKit attaches to its views. Observed on macOS 26.7.3 (x86_64)
// with the same calls: both initializers return a recognizer, and
// -initWithTarget:action: keeps the target and action like the superclass.
// The animationController SPI (declared by WebKit's PAL) starts as nil,
// retains whatever it is given, even an object that isn't an animation
// controller, releases it when reset to nil, and isn't archived;
// animationProgress starts at 0.
#import <Cocoa/Cocoa.h>
#include <stdio.h>

@interface NSGestureRecognizer (ImmediateActionSPI)
@property (retain) id animationController;
@property (readonly) CGFloat animationProgress;
@end

static int controllerDeallocations;

@interface TestAnimationController : NSObject
@end

@implementation TestAnimationController
- (void) dealloc
{
    controllerDeallocations++;
    [super dealloc];
}
@end

static int failures;

static void report(const char *name, BOOL ok)
{
    printf("%s: %s\n", ok ? "PASS" : "FAIL", name);
    if (!ok)
        failures++;
}

int main(void)
{
    @autoreleasepool {
        Class cls = NSClassFromString(@"NSImmediateActionGestureRecognizer");
        report("class exists", cls != Nil);
        report("is a gesture recognizer", [cls isSubclassOfClass: [NSGestureRecognizer class]]);

        NSObject *target = [[NSObject new] autorelease];
        NSGestureRecognizer *recognizer = [[[cls alloc] initWithTarget: target action: @selector(description)] autorelease];
        report("initWithTarget:action:", recognizer != nil);
        report("keeps the target", [recognizer target] == target);
        report("keeps the action", [recognizer action] == @selector(description));
        report("enabled", [recognizer isEnabled]);

        NSGestureRecognizer *plain = [[[cls alloc] init] autorelease];
        report("init", plain != nil);
        report("init has no target", [plain target] == nil && [plain action] == NULL);

        report("no animation controller by default", [plain animationController] == nil);
        report("animation progress starts at 0", [plain animationProgress] == 0);
        @autoreleasepool {
            TestAnimationController *controller = [TestAnimationController new];
            [plain setAnimationController: controller];
            [controller release];
            report("keeps the animation controller", [plain animationController] == controller && controllerDeallocations == 0);
            [plain setAnimationController: nil];
        }
        report("releases it when reset", [plain animationController] == nil && controllerDeallocations == 1);
        [plain setAnimationController: @"not a controller"];
        report("keeps any object", [[plain animationController] isEqual: @"not a controller"]);
        NSData *archive = [NSKeyedArchiver archivedDataWithRootObject: plain];
        NSGestureRecognizer *copy = [NSKeyedUnarchiver unarchiveObjectWithData: archive];
        report("animation controller isn't archived", copy != nil && [copy animationController] == nil);
    }
    return failures != 0;
}
