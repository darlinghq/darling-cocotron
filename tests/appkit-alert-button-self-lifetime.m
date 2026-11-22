// Copyright (C) 2026 Lubos Dolezel
//
// Choosing a button of an alert shown as a sheet ends the sheet, which calls the completion handler. A handler
// (or the code around it) may drop the last reference to the alert, so the alert has to stay alive until its own
// button action has returned: a method that calls out to code that can release its receiver keeps the receiver alive
// for the call (https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/MemoryMgmt/Articles/mmPractical.html,
// "Avoid Causing Deallocation of Objects You're Using"). The button's action is wrapped here through its public
// -action selector, to tell whether the alert was deallocated while that action was still running; the alert must be
// deallocated once the action is over (nothing is leaked). Needs a window server. Build without ARC.
#import <AppKit/AppKit.h>
#import <objc/runtime.h>
#include <stdio.h>

static int failures;
static BOOL inButtonAction;
static BOOL deallocatedInButtonAction;
static BOOL deallocated;

static void expect(BOOL condition, const char *what) {
    printf("%s %s\n", condition ? "PASS" : "FAIL", what);
    if (!condition)
        failures++;
}

@interface SpyAlert : NSAlert
@end

@implementation SpyAlert
- (void) dealloc {
    deallocated = YES;
    if (inButtonAction)
        deallocatedInButtonAction = YES;
    [super dealloc];
}
@end

static void spin(NSTimeInterval seconds) {
    [[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: seconds]];
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSWindow *parent = [[NSWindow alloc] initWithContentRect: NSMakeRect(200, 200, 400, 300)
                                                       styleMask: NSWindowStyleMaskTitled
                                                         backing: NSBackingStoreBuffered
                                                           defer: NO];
        [parent makeKeyAndOrderFront: nil];
        spin(0.3);

        // The only references to the alert are the caller's and the one the sheet holds while it is shown.
        __block SpyAlert *alert = [[SpyAlert alloc] init];
        [alert addButtonWithTitle: @"OK"];
        __block NSModalResponse response = 0;
        __block BOOL handlerRan = NO;
        [alert beginSheetModalForWindow: parent
                      completionHandler: ^(NSModalResponse code) {
                          response = code;
                          handlerRan = YES;
                          [alert release]; // the caller lets go of the alert when the sheet is done
                          alert = nil;
                      }];
        spin(0.5);

        NSButton *button = [[alert buttons] objectAtIndex: 0];
        SEL action = [button action];
        id target = [button target];
        IMP original = class_getMethodImplementation([NSAlert class], action);
        class_addMethod([SpyAlert class], action,
                        imp_implementationWithBlock(^(id self_, id sender) {
                            inButtonAction = YES;
                            ((void (*)(id, SEL, id))original)(self_, action, sender);
                            inButtonAction = NO;
                        }),
                        "v@:@");

        @autoreleasepool {
            [NSApp sendAction: action to: target from: button];
        }

        expect(handlerRan, "the completion handler ran when the button was chosen");
        expect(response == NSAlertFirstButtonReturn, "the handler got the first button's return code");
        expect(!deallocatedInButtonAction, "the alert was not deallocated while its button action was running");
        expect(deallocated, "the alert is deallocated after the button action (nothing is leaked)");
        [parent close];
    }
    printf(failures ? "FAIL (%d)\n" : "PASS\n", failures);
    return failures != 0;
}
