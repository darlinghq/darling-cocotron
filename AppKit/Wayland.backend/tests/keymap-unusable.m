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
// own: drives the wl_keyboard keymap event of CoreGraphics' keyboard directly and checks that key events keep being
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
// The keyboard decoder is CoreGraphics': the fixture drives its protocol events directly and reads what it
// posts from the process' event stream (a program with no event tap gets the events there at once).
extern void _CGSEventStreamSetReadySource(CFRunLoopSourceRef source, CFRunLoopRef runLoop);
extern CGEventRef _CGSEventStreamCopyNextEvent(void);
@interface FixtureKeyEvent : NSObject {
@public
    NSEventType type;
    NSUInteger flags;
    unsigned short code;
    NSString *characters;
}
- (NSEventType)type;
- (NSUInteger)modifierFlags;
- (unsigned short)keyCode;
- (NSString *)characters;
@end
@implementation FixtureKeyEvent
- (NSEventType)type { return type; }
- (NSUInteger)modifierFlags { return flags; }
- (unsigned short)keyCode { return code; }
- (NSString *)characters { return characters; }
@end
static void ignoreSource(void *info) {}
static void startReading(void) {
    CFRunLoopSourceContext context = {0};
    context.perform = ignoreSource;
    CFRunLoopSourceRef source = CFRunLoopSourceCreate(NULL, 0, &context);
    CFRunLoopAddSource(CFRunLoopGetMain(), source, kCFRunLoopCommonModes);
    _CGSEventStreamSetReadySource(source, CFRunLoopGetMain());
}
// Moves what the decoder has posted into `events`
static void drain(NSMutableArray *events) {
    CGEventRef cg;
    while ((cg = _CGSEventStreamCopyNextEvent()) != NULL) {
        CGEventType t = CGEventGetType(cg);
        if (t == kCGEventKeyDown || t == kCGEventKeyUp || t == kCGEventFlagsChanged) {
            FixtureKeyEvent *e = [FixtureKeyEvent new];
            e->type = (NSEventType)t;
            e->flags = (NSUInteger)CGEventGetFlags(cg);
            e->code = (unsigned short)CGEventGetIntegerValueField(cg, kCGKeyboardEventKeycode);
            UniChar chars[8]; UniCharCount n = 0;
            if (t != kCGEventFlagsChanged) CGEventKeyboardGetUnicodeString(cg, 8, &n, chars);
            e->characters = [[NSString stringWithCharacters:chars length:n] retain];
            [events addObject:e];
            [e release];
        }
        CFRelease(cg);
    }
}
static id keyboardDecoder(void) {
    id connection = _CGSConnectionForID(CGSMainConnectionID());
    Ivar ivar = class_getInstanceVariable(object_getClass(connection), "_keyboardDecoder");
    return ivar ? object_getIvar(connection, ivar) : nil;
}
static NSMutableArray *events;
static id display, decoder;
static NSWindow *window;
static int failures, checks;
static void keymapCheck(BOOL ok, const char *what) {
    ++checks; if (!ok) ++failures; printf("%s %s\n", ok ? "PASS" : "FAIL", what); fflush(stdout);
}
static void keymap(uint32_t format, int fd, uint32_t size) {
    union Argument a[3] = {{.u = format}, {.h = fd}, {.u = size}};
    [decoder keyboardEvent:0 arguments:a];
}
static void enter(void) {
    struct Array array = {0, 0, NULL};
    union Argument a[3] = {{.u = 1}, {.o = [[window platformWindow] surface]}, {.a = &array}};
    [decoder keyboardEvent:1 arguments:a];
}
// Types the key (an evdev code) and returns the characters of the key-down event, nil if none.
static NSString *typed(uint32_t code) {
    drain(events); [events removeAllObjects];
    union Argument down[4] = {{.u = 1}, {.u = 0}, {.u = code}, {.u = 1}};
    union Argument up[4] = {{.u = 1}, {.u = 0}, {.u = code}, {.u = 0}};
    [decoder keyboardEvent:3 arguments:down];
    [decoder keyboardEvent:3 arguments:up];
    drain(events);
    for (FixtureKeyEvent *e in events)
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
    decoder = keyboardDecoder();
    keymapCheck(decoder != nil, "the keyboard decoder exists");
    events = [NSMutableArray new]; startReading();
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

    [events release];
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
