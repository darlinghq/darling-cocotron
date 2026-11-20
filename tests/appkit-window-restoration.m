// Copyright (C) 2026 Lubos Dolezel
//
// User interface restoration API of NSWindow, NSResponder and NSApplication
// (NSWindowRestoration). Expected values are from black-box runs of this test on
// macOS 26.7.3 (x86_64) and Mac OS X 10.14.4 (i386).
//  - test_window_defaults: a titled window (and a titled panel) is restorable, a
//    borderless one is not; identifier nil, restorationClass Nil; the setters
//    round-trip.
//  - test_key_paths: NSResponder, NSWindow and NSApplication declare no
//    restorable key paths; -invalidateRestorableState, -extendStateRestoration
//    and -completeStateRestoration exist and return.
//  - test_window_state: -encodeRestorableStateWithCoder: tells the window
//    delegate (window:willEncodeRestorableState:), -restoreStateWithCoder: on
//    another resizable window applies the saved frame and tells its delegate
//    (window:didDecodeRestorableState:).
//  - test_quirk_fixed_size_window_keeps_size: a window that is not resizable
//    keeps its size on restore and moves horizontally to the saved frame.
//    Vertically 10.14 keeps the saved bottom edge and 26 the saved top edge, so
//    that is not checked.
//  - test_app_restore_window: -[NSApplication restoreWindowWithIdentifier:
//    state:completionHandler:] calls +restoreWindowWithIdentifier:... of the
//    restoration class recorded in the window state and returns YES; for state
//    without one it returns NO and does not call the handler.
//  - test_app_delegate: NSApplication's encode/restore call the delegate's
//    application:willEncodeRestorableState: / didDecodeRestorableState:.
//  - test_responder_state: NSResponder's own encode writes nothing, also for a
//    subclass with restorable key paths, and setting such a key path does not
//    invalidate the state by itself.
//  - test_nib (for each nib path given: fixtures/restoration/Restoration.nib, a
//    keyed archive, and Restoration-nibarchive.nib, the NIBArchive form; ibtool
//    compiled both from Restoration.xib, for deployment targets 10.9 and 10.13):
//    the window identifier and the Restorable flag come from the nib. (A nib window without an identifier gets a
//    generated one on macOS; that is not checked.)
// Usage: appkit-window-restoration [Restoration.nib Restoration-nibarchive.nib]
// Build: clang -framework AppKit appkit-window-restoration.m (no ARC)
#import <AppKit/AppKit.h>
#include <math.h>
#include <stdio.h>

static int failures;
#define CHECK(c) do { if (!(c)) { fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #c); failures++; } } while (0)

static int restorerCalls, windowEncodes, windowDecodes, appEncodes, appDecodes, invalidations;
static NSString *restorerIdentifier;

@interface Restorer : NSObject <NSWindowRestoration>
@end
@implementation Restorer
+ (void) restoreWindowWithIdentifier: (NSString *) identifier state: (NSCoder *) state
                   completionHandler: (void (^)(NSWindow *, NSError *)) handler {
    restorerCalls++;
    restorerIdentifier = [identifier copy];
    handler(nil, nil);
}
@end

@interface WindowDelegate : NSObject <NSWindowDelegate>
@end
@implementation WindowDelegate
- (void) window: (NSWindow *) window willEncodeRestorableState: (NSCoder *) state { windowEncodes++; }
- (void) window: (NSWindow *) window didDecodeRestorableState: (NSCoder *) state { windowDecodes++; }
@end

@interface AppDelegate : NSObject <NSApplicationDelegate>
@end
@implementation AppDelegate
- (void) application: (NSApplication *) app willEncodeRestorableState: (NSCoder *) state { appEncodes++; }
- (void) application: (NSApplication *) app didDecodeRestorableState: (NSCoder *) state { appDecodes++; }
@end

@interface Thing : NSResponder {
    NSString *_foo;
}
@property (copy) NSString *foo;
@end
@implementation Thing
@synthesize foo = _foo;
+ (NSArray *) restorableStateKeyPaths { return [NSArray arrayWithObject: @"foo"]; }
- (void) invalidateRestorableState { invalidations++; [super invalidateRestorableState]; }
@end

static NSWindow *window(NSRect rect, NSWindowStyleMask mask) {
    return [[NSWindow alloc] initWithContentRect: rect styleMask: mask backing: NSBackingStoreBuffered defer: YES];
}

// macOS raises from the window's encode when a plain archiver meets the first
// responder, after the parts checked here are written, so exceptions are ignored.
static NSData *encodeState(NSResponder *responder) {
    NSKeyedArchiver *archiver = [[NSKeyedArchiver alloc] initRequiringSecureCoding: YES];
    @try {
        [responder encodeRestorableStateWithCoder: archiver];
    } @catch (id e) {
    }
    [archiver finishEncoding];
    NSData *data = [[archiver encodedData] retain];
    [archiver release];
    return [data autorelease];
}

static NSKeyedUnarchiver *decoder(NSData *data) {
    return [[[NSKeyedUnarchiver alloc] initForReadingFromData: data error: NULL] autorelease];
}

static NSUInteger topKeyCount(NSData *data) {
    NSDictionary *plist = [NSPropertyListSerialization propertyListWithData: data options: 0 format: NULL error: NULL];
    return [[plist objectForKey: @"$top"] count];
}

static BOOL sameRect(NSRect a, NSRect b) {
    return fabs(a.origin.x - b.origin.x) < 0.5 && fabs(a.origin.y - b.origin.y) < 0.5 &&
           fabs(a.size.width - b.size.width) < 0.5 && fabs(a.size.height - b.size.height) < 0.5;
}

static void test_window_defaults(void) {
    NSWindow *titled = window(NSMakeRect(100, 100, 300, 200), NSWindowStyleMaskTitled | NSWindowStyleMaskClosable);
    NSWindow *borderless = window(NSMakeRect(0, 0, 50, 50), NSWindowStyleMaskBorderless);
    NSPanel *panel = [[NSPanel alloc] initWithContentRect: NSMakeRect(0, 0, 50, 50) styleMask: NSWindowStyleMaskTitled
                                                  backing: NSBackingStoreBuffered defer: YES];
    CHECK([titled isRestorable]);
    CHECK(![borderless isRestorable]);
    CHECK([panel isRestorable]);
    CHECK([titled identifier] == nil);
    CHECK([titled restorationClass] == Nil);
    [borderless setRestorable: YES];
    CHECK([borderless isRestorable]);
    [titled setRestorable: NO];
    CHECK(![titled isRestorable]);
    [titled setRestorationClass: [Restorer class]];
    CHECK([titled restorationClass] == [Restorer class]);
    [titled setRestorationClass: Nil];
    CHECK([titled restorationClass] == Nil);
    [titled setIdentifier: @"win1"];
    CHECK([[titled identifier] isEqualToString: @"win1"]);
}

static void test_key_paths(void) {
    CHECK([[NSResponder restorableStateKeyPaths] count] == 0);
    CHECK([[NSWindow restorableStateKeyPaths] count] == 0);
    CHECK([[NSApplication restorableStateKeyPaths] count] == 0);
    NSWindow *w = window(NSMakeRect(0, 0, 100, 100), NSWindowStyleMaskTitled);
    CHECK([w respondsToSelector: @selector(invalidateRestorableState)]);
    CHECK([NSApp respondsToSelector: @selector(extendStateRestoration)]);
    CHECK([NSApp respondsToSelector: @selector(completeStateRestoration)]);
    CHECK([NSApp respondsToSelector: @selector(restoreWindowWithIdentifier:state:completionHandler:)]);
    [w invalidateRestorableState];
    [NSApp invalidateRestorableState];
    [NSApp extendStateRestoration];
    [NSApp completeStateRestoration];
}

static void test_window_state(void) {
    WindowDelegate *delegate = [WindowDelegate new];
    NSWindowStyleMask mask = NSWindowStyleMaskTitled | NSWindowStyleMaskResizable;
    NSWindow *source = window(NSMakeRect(100, 100, 300, 200), mask);
    [source setDelegate: delegate];
    windowEncodes = windowDecodes = 0;
    NSData *state = encodeState(source);
    CHECK(windowEncodes == 1);
    NSWindow *target = window(NSMakeRect(10, 10, 100, 100), mask);
    [target setDelegate: delegate];
    [target restoreStateWithCoder: decoder(state)];
    CHECK(windowDecodes == 1);
    CHECK(sameRect([target frame], [source frame]));
    [source setDelegate: nil];
    [target setDelegate: nil];
}

static void test_quirk_fixed_size_window_keeps_size(void) {
    NSWindow *source = window(NSMakeRect(100, 100, 300, 200), NSWindowStyleMaskTitled);
    NSData *state = encodeState(source);
    NSWindow *target = window(NSMakeRect(10, 10, 100, 100), NSWindowStyleMaskTitled);
    NSRect before = [target frame];
    [target restoreStateWithCoder: decoder(state)];
    NSRect after = [target frame];
    CHECK(fabs(after.size.width - before.size.width) < 0.5);
    CHECK(fabs(after.size.height - before.size.height) < 0.5);
    CHECK(fabs(NSMinX(after) - NSMinX([source frame])) < 0.5);
}

static void test_app_restore_window(void) {
    NSWindow *source = window(NSMakeRect(100, 100, 300, 200), NSWindowStyleMaskTitled);
    [source setIdentifier: @"win1"];
    [source setRestorationClass: [Restorer class]];
    NSData *state = encodeState(source);
    __block int handlerCalls = 0;
    restorerCalls = 0;
    BOOL result = [NSApp restoreWindowWithIdentifier: @"win1" state: decoder(state)
                                   completionHandler: ^(NSWindow *w, NSError *e) { handlerCalls++; }];
    CHECK(result);
    CHECK(restorerCalls == 1);
    CHECK([restorerIdentifier isEqualToString: @"win1"]);
    CHECK(handlerCalls == 1);

    NSKeyedArchiver *archiver = [[NSKeyedArchiver alloc] initRequiringSecureCoding: YES];
    [archiver encodeObject: @"v" forKey: @"k"];
    [archiver finishEncoding];
    handlerCalls = 0;
    restorerCalls = 0;
    result = [NSApp restoreWindowWithIdentifier: @"win1" state: decoder([archiver encodedData])
                              completionHandler: ^(NSWindow *w, NSError *e) { handlerCalls++; }];
    CHECK(!result);
    CHECK(restorerCalls == 0);
    CHECK(handlerCalls == 0);
}

static void test_app_delegate(void) {
    AppDelegate *delegate = [AppDelegate new];
    id old = [NSApp delegate];
    [NSApp setDelegate: delegate];
    NSData *state = encodeState(NSApp);
    CHECK(appEncodes == 1);
    @try {
        [NSApp restoreStateWithCoder: decoder(state)];
    } @catch (id e) {
        fprintf(stderr, "FAIL: application restore raised %s\n", [[e description] UTF8String]);
        failures++;
    }
    CHECK(appDecodes == 1);
    [NSApp setDelegate: old];
}

static void test_responder_state(void) {
    Thing *thing = [Thing new];
    invalidations = 0;
    [thing setFoo: @"bar"];
    CHECK(invalidations == 0);
    NSData *state = encodeState(thing);
    CHECK(topKeyCount(state) == 0);
    Thing *other = [Thing new];
    [other restoreStateWithCoder: decoder(state)];
    CHECK([other foo] == nil);
}

static void test_nib(const char *path) {
    NSNib *nib = [[NSNib alloc] initWithNibData: [NSData dataWithContentsOfFile: [NSString stringWithUTF8String: path]]
                                         bundle: nil];
    NSArray *objects = nil;
    CHECK([nib instantiateWithOwner: nil topLevelObjects: &objects]);
    if (objects == nil) fprintf(stderr, "  (%s)\n", path);
    NSWindow *restorable = nil, *notRestorable = nil;
    for (id object in objects) {
        if (![object isKindOfClass: [NSWindow class]])
            continue;
        if ([[object title] isEqualToString: @"Restorable"]) restorable = object;
        if ([[object title] isEqualToString: @"Not Restorable"]) notRestorable = object;
    }
    CHECK(restorable != nil && notRestorable != nil);
    CHECK([[restorable identifier] isEqualToString: @"RestorableWindow"]);
    CHECK([restorable isRestorable]);
    CHECK(![notRestorable isRestorable]);
}

#define RUN(t) do { @try { t; } @catch (id e) { fprintf(stderr, "FAIL: %s raised %s\n", #t, [[e description] UTF8String]); failures++; } } while (0)

int main(int argc, char **argv) {
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    [NSApplication sharedApplication];
    RUN(test_window_defaults());
    RUN(test_key_paths());
    RUN(test_window_state());
    RUN(test_quirk_fixed_size_window_keeps_size());
    RUN(test_app_restore_window());
    RUN(test_app_delegate());
    RUN(test_responder_state());
    for (int i = 1; i < argc; i++)
        RUN(test_nib(argv[i]));
    if (failures == 0)
        printf("PASS appkit-window-restoration\n");
    [pool release];
    return failures != 0;
}
