/*
 Copyright (C) 2026 Lubos Dolezel

 Licensed under the MIT license, the same as the rest of this project.
*/
// Key-value coding of NSApplication's running state through the private
// "_running" key (quirk test: the key resolves without accessor methods), plus
// the small application, window, cell and appearance interfaces added for
// private callers. No window is shown.
#import <AppKit/AppKit.h>
#include <objc/message.h>
#include <objc/runtime.h>
#include <stdio.h>

extern BOOL NSSolariumEnabled(void);

static int failures;

static void expect(BOOL condition, const char *what) {
    if (!condition) {
        fprintf(stderr, "FAIL: %s\n", what);
        failures++;
    }
}

@interface NSObject (FindIndicatorProbe)
- (void) setCompletionHandler: (void (^)(void)) handler;
- (void) pulseAndFade: (BOOL) fade;
@end

@interface SearchHandler : NSObject <NSUserInterfaceItemSearching>
@end
@implementation SearchHandler
@end

int main(void) {
    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];

        // QUIRK test: the _running key works without accessor methods.
        expect(![app respondsToSelector: NSSelectorFromString(@"_running")],
               "NSApplication has no _running accessor method");
        id before = nil;
        @try {
            before = [app valueForKey: @"_running"];
        } @catch (NSException *exception) {
            expect(NO, "valueForKey:@\"_running\" does not raise");
        }
        expect([before isKindOfClass: [NSNumber class]] && ![before boolValue],
               "_running is NO before -run");
        expect(![app isRunning], "isRunning is NO before -run");
        @try {
            [app setValue: @YES forKey: @"_running"];
            expect([app isRunning], "setting _running to YES changes isRunning");
            expect([[app valueForKey: @"_running"] boolValue], "_running reads back YES");
            [app setValue: @NO forKey: @"_running"];
            expect(![app isRunning], "setting _running to NO changes isRunning");
        } @catch (NSException *exception) {
            expect(NO, "setValue:forKey:@\"_running\" does not raise");
        }
        BOOL unknownRejected = NO;
        @try {
            [app setValue: @YES forKey: @"darling_unknown_running_key"];
        } @catch (NSException *exception) {
            unknownRejected = [[exception name] isEqualToString: NSUndefinedKeyException];
        }
        expect(unknownRejected, "an unrelated unknown key is still rejected");

        // contextID is an unsigned 32-bit value (the type encoding starts with I; the offsets differ per architecture).
        Method contextID = class_getInstanceMethod([NSApplication class], @selector(contextID));
        expect(contextID != NULL && method_getTypeEncoding(contextID)[0] == 'I',
               "-[NSApplication contextID] returns an unsigned int");

        // The search handler registration is accepted.
        SearchHandler *handler = [[SearchHandler alloc] init];
        [app registerUserInterfaceItemSearchHandler: handler];
        [app unregisterUserInterfaceItemSearchHandler: handler];
        [handler release];

        expect(!NSSolariumEnabled(), "NSSolariumEnabled is NO");
        expect(NSApplicationDidFinishRestoringWindowsNotification != nil,
               "NSApplicationDidFinishRestoringWindowsNotification is defined");
        expect(NSImageNameTouchBarAddTabTemplate != nil, "NSImageNameTouchBarAddTabTemplate is defined");

        // NSAccessibility helpers.
        BOOL raised = NO;
        @try {
            NSAccessibilityRaiseBadArgumentException(app, NSAccessibilityTitleAttribute, @1);
        } @catch (NSException *exception) {
            raised = [[exception name] isEqualToString: @"NSAccessibilityException"];
        }
        expect(raised, "NSAccessibilityRaiseBadArgumentException raises NSAccessibilityException");

        // NSWindow private corner style and tab.
        NSWindow *window = [[NSWindow alloc] initWithContentRect: NSMakeRect(0, 0, 100, 100)
                                                       styleMask: NSWindowStyleMaskTitled
                                                         backing: NSBackingStoreBuffered
                                                           defer: YES];
        expect([window bottomCornerRounded], "bottom corners are rounded by default");
        [window setBottomCornerRounded: NO];
        expect(![window bottomCornerRounded], "bottom corner setting is stored");
        expect([window performSelector: @selector(tab)] == nil, "an untabbed window has no tab");
        [window release];

        // NSCell interiorBackgroundStyle is read-only.
        NSCell *cell = [[NSCell alloc] init];
        expect([cell interiorBackgroundStyle] == [cell backgroundStyle], "interiorBackgroundStyle follows backgroundStyle");
        expect(![cell respondsToSelector: @selector(setInteriorBackgroundStyle:)],
               "there is no setInteriorBackgroundStyle:");
        [cell release];

        // Private classes exist.
        expect(NSClassFromString(@"NSFindIndicator") != Nil, "NSFindIndicator exists");
        expect(NSClassFromString(@"NSFunctionRow") != Nil, "NSFunctionRow exists");
        expect(NSClassFromString(@"NSImmediateActionGestureRecognizer") != Nil,
               "NSImmediateActionGestureRecognizer exists");
        Class functionRow = NSClassFromString(@"NSFunctionRow");
        BOOL available = ((BOOL (*)(id, SEL)) objc_msgSend)(functionRow, @selector(isDynamicFunctionRowAvailable));
        expect(!available, "no dynamic function row");
        id indicator = [[NSClassFromString(@"NSFindIndicator") alloc] init];
        __block BOOL completed = NO;
        [indicator setCompletionHandler: ^{ completed = YES; }];
        [indicator pulseAndFade: YES];
        expect(completed, "NSFindIndicator runs its completion handler");
        [indicator release];
    }
    if (failures == 0)
        printf("OK\n");
    return failures != 0;
}
