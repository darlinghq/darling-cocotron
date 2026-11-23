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
- (NSWindow *)_findWindowUsingContextID:(NSInteger)contextID;
- (void)_restoreMiniaturizedWindow;
@end

static NSMutableArray *gOrder;

@interface FakeWindow : NSObject
{
@public
    NSString *name;
    BOOL visible, miniaturized, canBeKey, restored;
}
@end

@implementation FakeWindow
- (BOOL)isVisible { return visible; }
- (BOOL)isMiniaturized { return miniaturized; }
- (BOOL)canBecomeKeyWindow { return canBeKey; }
- (void)deminiaturize:(id)sender { restored = YES; miniaturized = NO; }
@end

static FakeWindow *fake(NSString *name)
{
    FakeWindow *w = [[[FakeWindow alloc] init] autorelease];
    w->name = name;
    w->visible = YES;
    w->canBeKey = YES;
    return w;
}

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
        expect([app _findWindowUsingContextID:(NSInteger)[window windowNumber]] == nil,
               @"a window number is not a context id");
        expect([app _findWindowUsingContextID:(NSInteger)[app contextID]] == nil,
               @"the application's context id finds no window");
        [window release];

        // Fake window model from here on.
        method_setImplementation(class_getInstanceMethod([NSApplication class], @selector(orderedWindows)),
                                 imp_implementationWithBlock(^NSArray *(id s) { return [[gOrder copy] autorelease]; }));

        // -_restoreMiniaturizedWindow restores the frontmost miniaturized window only.
        expect([app respondsToSelector:@selector(_restoreMiniaturizedWindow)],
               @"NSApplication answers -_restoreMiniaturizedWindow");
        FakeWindow *front = fake(@"front"), *mid = fake(@"mid"), *back = fake(@"back");
        gOrder = [[NSMutableArray alloc] initWithObjects:front, mid, back, nil];
        [app _restoreMiniaturizedWindow];
        expect(!front->restored && !mid->restored && !back->restored, @"nothing is restored when no window is miniaturized");
        mid->miniaturized = back->miniaturized = YES;
        [app _restoreMiniaturizedWindow];
        expect(mid->restored && !back->restored, @"the frontmost miniaturized window is restored, and only it");
        [app _restoreMiniaturizedWindow];
        expect(back->restored, @"the next call restores the next one");
        [gOrder release];

        if (failures == 0)
            NSLog(@"PASS: NSApplication catalyst methods");
    }
    return failures == 0 ? 0 : 1;
}
