#import <AppKit/AppKit.h>
#include <objc/runtime.h>
#include <stdlib.h>

// Private AppKit API that Mac Catalyst frameworks require. Windows are fakes
// that model what -orderedWindows does (front to back, activating a window moves
// it to the front), so no window server is needed.
static int failures;

static void expect(BOOL condition, NSString *message)
{
    if (!condition)
    {
        NSLog(@"FAIL: %@", message);
        failures++;
    }
}

@interface NSApplication (CatalystPrivate)
- (NSWindow *)_findWindowUsingContextID:(uint32_t)contextID;
@end




int main(void)
{
    @autoreleasepool
    {
        NSApplication *app = [NSApplication sharedApplication];

        // -_findWindowUsingContextID: Cocotron has no context ids, so no window is ever found.
        expect([app respondsToSelector:@selector(_findWindowUsingContextID:)],
               @"NSApplication answers -_findWindowUsingContextID:");
        NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 200, 100)
                                                       styleMask:NSWindowStyleMaskTitled
                                                         backing:NSBackingStoreBuffered
                                                           defer:YES];
        expect([app _findWindowUsingContextID:(uint32_t)[window windowNumber]] == nil,
               @"a window number is not a context id");
        expect([app _findWindowUsingContextID:(uint32_t)[app contextID]] == nil,
               @"the application's context id finds no window");
        [window release];









        if (failures == 0)
            NSLog(@"PASS: NSApplication catalyst methods");
    }
    return failures == 0 ? 0 : 1;
}
