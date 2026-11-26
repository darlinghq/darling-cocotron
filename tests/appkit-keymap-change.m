/*
 * Copyright (C) 2026 Lubos Dolezel
 * SPDX-License-Identifier: GPL-3.0-or-later
 */
// A change of the window system's keymap reaches both CoreGraphics and AppKit: after the keymap changes,
// the physical key that is Y on a US keyboard is typed (by the driver script), and
//   - AppKit's key-down event carries the character of the new keymap,
//   - the keyboard layout CoreGraphics describes (TISCopyCurrentKeyboardLayoutInputSource with
//     kTISPropertyUnicodeKeyLayoutData, and the layout of _CGSCopyCurrentKeyboardLayoutInfo) translates
//     the virtual key kVK_ANSI_Y to the same character.
//
// Usage: appkit-keymap-change <character>...
//   For each argument the test prints READYn, waits for one key-down in its window and compares: the
//   driver changes the keymap and types the key after each READYn (appkit-keymap-change.sh).
// Link with -framework AppKit -framework Carbon -framework CoreGraphics.
#import <AppKit/AppKit.h>
#import <Carbon/Carbon.h>
#include <stdio.h>
#include <string.h>

extern CFDictionaryRef _CGSCopyCurrentKeyboardLayoutInfo(void);

@interface KeyView : NSView {
@public
    NSMutableArray *received;
}
@end
@implementation KeyView
- (BOOL) acceptsFirstResponder { return YES; }
- (void) keyDown: (NSEvent *) event {
    [received addObject: [event characters] ?: @""];
}
@end

// Runs the application's event loop for a while: key events are dequeued and sent to the window.
static void spinFor(double seconds) {
    NSDate *end = [NSDate dateWithTimeIntervalSinceNow: seconds];
    while ([end timeIntervalSinceNow] > 0) {
        NSEvent *event = [NSApp nextEventMatchingMask: NSAnyEventMask
                                            untilDate: [NSDate dateWithTimeIntervalSinceNow: 0.05]
                                               inMode: NSDefaultRunLoopMode
                                              dequeue: YES];
        if (event != nil)
            [NSApp sendEvent: event];
    }
}

// The character the layout data gives the virtual key Y without modifiers, as UTF-8.
static NSString *translateY(const UCKeyboardLayout *layout) {
    UInt32 deadKeyState = 0;
    UniCharCount length = 0;
    UniChar chars[4] = {0};
    OSStatus status = UCKeyTranslate(layout, kVK_ANSI_Y, kUCKeyActionDown, 0, 40,
                                     kUCKeyTranslateNoDeadKeysMask, &deadKeyState, 4, &length, chars);
    if (status != noErr || length != 1)
        return [NSString stringWithFormat: @"(status %d, %lu characters)", (int) status, (unsigned long) length];
    return [NSString stringWithCharacters: chars length: 1];
}

static NSString *tisY(void) {
    TISInputSourceRef source = TISCopyCurrentKeyboardLayoutInputSource();
    if (source == NULL)
        return @"(no input source)";
    CFDataRef data = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData);
    NSString *result = data != NULL ? translateY((const UCKeyboardLayout *) CFDataGetBytePtr(data)) : @"(no layout data)";
    CFRelease(source);
    return result;
}

static NSString *cgsY(void) {
    CFDictionaryRef info = _CGSCopyCurrentKeyboardLayoutInfo();
    if (info == NULL)
        return @"(no layout info)";
    CFDataRef data = CFDictionaryGetValue(info, CFSTR("data"));
    NSString *result = data != NULL ? translateY((const UCKeyboardLayout *) CFDataGetBytePtr(data)) : @"(no layout data)";
    CFRelease(info);
    return result;
}

int main(int argc, char **argv) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy: NSApplicationActivationPolicyRegular];
        NSWindow *window = [[NSWindow alloc] initWithContentRect: NSMakeRect(100, 100, 300, 200)
                                                       styleMask: NSTitledWindowMask
                                                         backing: NSBackingStoreBuffered
                                                           defer: NO];
        KeyView *view = [[KeyView alloc] initWithFrame: NSMakeRect(0, 0, 300, 200)];
        view->received = [NSMutableArray array];
        [window setContentView: view];
        [window makeKeyAndOrderFront: nil];
        [window makeFirstResponder: view];
        [NSApp activateIgnoringOtherApps: YES];
        spinFor(1.0);

        int failures = 0;
        for (int i = 1; i < argc; i++) {
            NSString *expected = [NSString stringWithUTF8String: argv[i]];
            printf("READY%d\n", i);
            fflush(stdout);
            NSDate *end = [NSDate dateWithTimeIntervalSinceNow: 20];
            while ([view->received count] < (NSUInteger) i && [end timeIntervalSinceNow] > 0)
                spinFor(0.05);
            if ([view->received count] < (NSUInteger) i) {
                printf("FAIL round %d: no key event\n", i);
                return 1;
            }
            NSString *typed = view->received[i - 1];
            NSString *tis = tisY(), *cgs = cgsY();
            printf("round %d: expected %s, AppKit typed %s, TIS layout %s, CoreGraphics layout %s\n", i, argv[i],
                   [typed UTF8String], [tis UTF8String], [cgs UTF8String]);
            if (![typed isEqualToString: expected]) { printf("FAIL round %d: AppKit's character\n", i); failures++; }
            if (![tis isEqualToString: expected]) { printf("FAIL round %d: the TIS layout\n", i); failures++; }
            if (![cgs isEqualToString: expected]) { printf("FAIL round %d: the CoreGraphics layout\n", i); failures++; }
        }
        printf(failures ? "FAIL\n" : "PASS\n");
        return failures ? 1 : 0;
    }
}
