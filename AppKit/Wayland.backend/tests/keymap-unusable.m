/*
 Copyright (C) 2026 Lubos Dolezel

 Licensed under the MIT license, the same as the rest of this project.
*/
#import <AppKit/AppKit.h>
#import <objc/runtime.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

// Actual-backend fixture, run only with an isolated native compositor that has no keyboard of its
// own: drives the wl_keyboard keymap event directly and checks that key events keep being
// delivered after keymaps the client cannot use (format no_keymap, an empty xkb_v1 map, a map
// that does not compile, an unknown format), and that the keymap in force before them stays.
union Argument { int32_t i; uint32_t u; const char *s; void *o; void *a; int h; };
struct Array { size_t size, alloc; void *data; };
@interface NSObject (KeymapFixture)
+ (id)currentDisplay;
- (id)platformWindow;
- (void *)surface;
- (void)keyboardEvent:(uint32_t)opcode arguments:(union Argument *)args;
- (void)processPendingEvents;
@end
static NSMutableArray *events;
static id display;
static NSWindow *window;
static int failures, checks;
static void capture(id self, SEL cmd, NSEvent *event, BOOL atStart) { [events addObject:event]; }
static void keymapCheck(BOOL ok, const char *what) {
    ++checks; if (!ok) ++failures; printf("%s %s\n", ok ? "PASS" : "FAIL", what); fflush(stdout);
}
static void keymap(uint32_t format, int fd, uint32_t size) {
    union Argument a[3] = {{.u = format}, {.h = fd}, {.u = size}};
    [display keyboardEvent:0 arguments:a];
}
static void enter(void) {
    struct Array array = {0, 0, NULL};
    union Argument a[3] = {{.u = 1}, {.o = [[window platformWindow] surface]}, {.a = &array}};
    [display keyboardEvent:1 arguments:a];
}
// Types the key (an evdev code) and returns the characters of the key-down event, nil if none.
static NSString *typed(uint32_t code) {
    [events removeAllObjects];
    union Argument down[4] = {{.u = 1}, {.u = 0}, {.u = code}, {.u = 1}};
    union Argument up[4] = {{.u = 1}, {.u = 0}, {.u = code}, {.u = 0}};
    [display keyboardEvent:3 arguments:down];
    [display keyboardEvent:3 arguments:up];
    for (NSEvent *e in events)
        if ([e type] == NSKeyDown) return [e characters];
    return nil;
}
static int tempFile(const char *content) {
    char path[] = "/tmp/keymap-unusable-XXXXXX";
    int fd = mkstemp(path);
    unlink(path);
    if (fd >= 0 && content != NULL) write(fd, content, strlen(content));
    return fd;
}
// A keymap of its own: key code 30 (evdev) produces "z", where the system default layout has "a".
static const char *zKeymap =
    "xkb_keymap {\n"
    "xkb_keycodes \"k\" { minimum = 8; maximum = 255; <AC01> = 38; };\n"
    "xkb_types \"t\" { type \"ONE_LEVEL\" { modifiers = none; map[none] = Level1; }; };\n"
    "xkb_compat \"c\" { };\n"
    "xkb_symbols \"s\" { key <AC01> { [ z ] }; };\n"
    "};\n";
@interface KeymapApplication : NSApplication
@end
@implementation KeymapApplication
- (void)test:(id)sender {
    display = [NSClassFromString(@"NSDisplay") currentDisplay];
    Class original = object_getClass(display);
    Class recorder = objc_allocateClassPair(original, "KeymapRecordingDisplay", 0);
    Method method = class_getInstanceMethod(original, @selector(postEvent:atStart:));
    keymapCheck(method != NULL, "backend event method exists");
    class_addMethod(recorder, @selector(postEvent:atStart:), (IMP)capture,
                    method_getTypeEncoding(method));
    objc_registerClassPair(recorder); events = [NSMutableArray new];
    object_setClass(display, recorder);
    enter();

    // Protocol behaviour, not a quirk: no_keymap means the client interprets raw key codes.
    keymap(0, tempFile(NULL), 0);
    keymapCheck([typed(30) isEqual:@"a"], "no_keymap with no keymap yet: raw key codes produce characters");
    keymap(1, tempFile(zKeymap), (uint32_t)strlen(zKeymap) + 1);
    keymapCheck([typed(30) isEqual:@"z"], "a compositor keymap replaces the default");
    keymap(0, tempFile(NULL), 0);
    keymapCheck([typed(30) isEqual:@"z"], "no_keymap: the keymap in force stays");
    keymap(1, tempFile(NULL), 0);
    keymapCheck([typed(30) isEqual:@"z"], "empty xkb_v1 keymap: the keymap in force stays");
    keymap(1, tempFile("this is not a keymap"), 20);
    keymapCheck([typed(30) isEqual:@"z"], "uncompilable keymap: the keymap in force stays");
    keymap(7, tempFile("x"), 1);
    keymapCheck([typed(30) isEqual:@"z"], "unknown keymap format: the keymap in force stays");

    object_setClass(display, original); [events release];
    printf("RESULT checks=%d failures=%d\n", checks, failures); fflush(stdout);
    exit(failures ? 1 : 0);
}
@end
int main(void) {
    [NSAutoreleasePool new]; [KeymapApplication sharedApplication];
    window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 500, 400)
            styleMask:NSTitledWindowMask backing:NSBackingStoreBuffered defer:NO];
    [window setTitle:@"Wayland keymap test"]; [window makeKeyAndOrderFront:nil];
    [NSTimer scheduledTimerWithTimeInterval:4 target:NSApp selector:@selector(test:)
                                   userInfo:nil repeats:NO];
    puts("READY"); fflush(stdout); [NSApp run]; return 2;
}
