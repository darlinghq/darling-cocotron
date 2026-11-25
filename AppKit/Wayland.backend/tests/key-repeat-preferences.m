/*
 Copyright (C) 2026 Lubos Dolezel

 Licensed under the MIT license, the same as the rest of this project.
*/
#import <AppKit/AppKit.h>
#import <objc/runtime.h>
#include <stdio.h>
#include <stdlib.h>

// Actual-backend fixture, run only with an isolated native compositor that has no keyboard of its own: drives
// the wl_keyboard events of CoreGraphics' keyboard directly (as keymap-unusable.m does) and counts the repeats
// of a held key. They follow the compositor's repeat_info (25 per second after 600 ms here) until the
// InitialKeyRepeat and KeyRepeat defaults of the user are set; those count 15 ms ticks (quirk_tick_is_15_ms).
union Argument { int32_t i; uint32_t u; const char *s; void *o; void *a; int h; };
struct Array { size_t size, alloc; void *data; };
@interface NSObject (RepeatFixture)
+ (id)currentDisplay;
- (id)platformWindow;
- (void *)surface;
- (void)keyboardEvent:(uint32_t)opcode arguments:(union Argument *)args;
@end
extern void _CGSEventStreamSetReadySource(CFRunLoopSourceRef source, CFRunLoopRef runLoop);
extern CGEventRef _CGSEventStreamCopyNextEvent(void);
static void ignoreSource(void *info) {}
static void startReading(void) {
    CFRunLoopSourceContext context = {0};
    context.perform = ignoreSource;
    CFRunLoopSourceRef source = CFRunLoopSourceCreate(NULL, 0, &context);
    CFRunLoopAddSource(CFRunLoopGetMain(), source, kCFRunLoopCommonModes);
    _CGSEventStreamSetReadySource(source, CFRunLoopGetMain());
}
// The number of key-down events that report an autorepeat among those the decoder has posted
static int repeatsPosted(void) {
    int repeats = 0;
    CGEventRef cg;
    while ((cg = _CGSEventStreamCopyNextEvent()) != NULL) {
        if (CGEventGetType(cg) == kCGEventKeyDown && CGEventGetIntegerValueField(cg, kCGKeyboardEventAutorepeat) != 0)
            repeats++;
        CFRelease(cg);
    }
    return repeats;
}
static id keyboardDecoder(void) {
    id connection = _CGSConnectionForID(CGSMainConnectionID());
    Ivar ivar = class_getInstanceVariable(object_getClass(connection), "_keyboardDecoder");
    return ivar ? object_getIvar(connection, ivar) : nil;
}
static id decoder;
static NSWindow *window;
static int failures, checks;
static void repeatCheck(BOOL ok, const char *what) {
    ++checks; if (!ok) ++failures; printf("%s %s\n", ok ? "PASS" : "FAIL", what); fflush(stdout);
}
static void setPreference(NSString *key, id value) {
    CFPreferencesSetValue((CFStringRef)key, (CFPropertyListRef)value, kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    CFPreferencesSynchronize(kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
}
// Holds the key (evdev code 30) for the time and returns how many repeats it produced
static int heldRepeats(double seconds) {
    repeatsPosted();
    union Argument down[4] = {{.u = 1}, {.u = 0}, {.u = 30}, {.u = 1}};
    union Argument up[4] = {{.u = 1}, {.u = 0}, {.u = 30}, {.u = 0}};
    [decoder keyboardEvent:3 arguments:down];
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:seconds]];
    [decoder keyboardEvent:3 arguments:up];
    return repeatsPosted();
}
@interface RepeatApplication : NSApplication
@end
@implementation RepeatApplication
- (void)test:(id)sender {
    decoder = keyboardDecoder();
    repeatCheck(decoder != nil, "the keyboard decoder exists");
    startReading();
    struct Array array = {0, 0, NULL};
    union Argument enter[3] = {{.u = 1}, {.o = [[window platformWindow] surface]}, {.a = &array}};
    [decoder keyboardEvent:1 arguments:enter];
    union Argument info[2] = {{.i = 25}, {.i = 600}};
    [decoder keyboardEvent:5 arguments:info];

    setPreference(@"KeyRepeat", nil);
    setPreference(@"InitialKeyRepeat", nil);
    repeatCheck(heldRepeats(0.45) == 0, "the compositor's delay of 600 ms applies while no preference is set");

    // quirk_tick_is_15_ms: 15 ticks are 225 ms before the first repeat, 2 ticks 30 ms between repeats
    setPreference(@"InitialKeyRepeat", @15);
    setPreference(@"KeyRepeat", @2);
    int repeats = heldRepeats(0.5);
    repeatCheck(repeats >= 5 && repeats <= 11, "InitialKeyRepeat 15 and KeyRepeat 2 repeat quickly");
    printf("repeats %d\n", repeats);

    setPreference(@"InitialKeyRepeat", @120);
    setPreference(@"KeyRepeat", @120);
    repeatCheck(heldRepeats(0.5) == 0, "InitialKeyRepeat 120 waits 1.8 s before the first repeat");

    // `defaults write -g KeyRepeat 2` stores a string
    setPreference(@"InitialKeyRepeat", @"15");
    setPreference(@"KeyRepeat", @"2");
    repeats = heldRepeats(0.5);
    repeatCheck(repeats >= 5 && repeats <= 11, "the preferences are read as strings too");

    // only the interval set: the compositor's delay stays
    setPreference(@"InitialKeyRepeat", nil);
    repeatCheck(heldRepeats(0.45) == 0, "the delay of the compositor stays when only KeyRepeat is set");

    setPreference(@"KeyRepeat", nil);
    setPreference(@"InitialKeyRepeat", nil);
    printf("RESULT checks=%d failures=%d\n", checks, failures); fflush(stdout);
    exit(failures ? 1 : 0);
}
@end
int main(void) {
    [NSAutoreleasePool new]; [RepeatApplication sharedApplication];
    window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 500, 400)
            styleMask:NSTitledWindowMask backing:NSBackingStoreBuffered defer:NO];
    [window setTitle:@"Wayland key repeat test"]; [window makeKeyAndOrderFront:nil];
    [NSTimer scheduledTimerWithTimeInterval:4 target:NSApp selector:@selector(test:)
                                   userInfo:nil repeats:NO];
    puts("READY"); fflush(stdout); [NSApp run]; return 2;
}
