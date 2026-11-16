// Copyright (C) 2026 Lubos Dolezel
//
// An application's subclass of NSBrowser or NSColorWell, compiled against the
// Mac's layout of the legacy (32-bit) Objective-C ABI, keeps its own instance
// variables in the bytes that follow the class's Apple instance size (160 and
// 108 bytes). AppKit must neither write into those bytes nor read its own
// state back from them. The expected sizes are what Mac OS X 10.14.4 reports.
//
// Two checks per class:
//  - an ordinary subclass with its own instance variables keeps them intact
//    while the AppKit state is used, and AppKit state survives writes to them
//    (all ABIs);
//  - on the legacy ABI, an instance with spare bytes at Apple's size, standing
//    for the object of a subclass compiled against the Mac layout, has that
//    memory left alone and AppKit's state does not depend on it.
#import <AppKit/AppKit.h>
#import <objc/runtime.h>
#include <stdio.h>
#include <string.h>

static int failures;

#define CHECK(cond, ...)                                                       \
    do {                                                                       \
        if (!(cond)) {                                                         \
            printf("FAIL: " __VA_ARGS__);                                      \
            printf("\n");                                                      \
            failures++;                                                        \
        }                                                                      \
    } while (0)

@interface SubBrowser : NSBrowser {
    int ownCounter;
    id ownObject;
    double ownValue;
}
@end
@implementation SubBrowser
- (void) setOwn {
    ownCounter = 0x1234abcd;
    ownObject = (id) 0x5a5a5a5a;
    ownValue = 3.25;
}
- (BOOL) ownIntact {
    return ownCounter == 0x1234abcd && ownObject == (id) 0x5a5a5a5a && ownValue == 3.25;
}
@end

@interface SubColorWell : NSColorWell {
    int ownCounter;
    id ownObject;
    double ownValue;
}
@end
@implementation SubColorWell
- (void) setOwn {
    ownCounter = 0x1234abcd;
    ownObject = (id) 0x5a5a5a5a;
    ownValue = 3.25;
}
- (BOOL) ownIntact {
    return ownCounter == 0x1234abcd && ownObject == (id) 0x5a5a5a5a && ownValue == 3.25;
}
@end

static void flipBrowser(NSBrowser *b, BOOL v) {
    [b setTitled: v];
    [b setHasHorizontalScroller: v];
    [b setSeparatesColumns: v];
    [b setTakesTitleFromPreviousColumn: v];
    [b setAllowsMultipleSelection: v];
    [b setAllowsBranchSelection: v];
    [b setAllowsEmptySelection: v];
    [b setAcceptsArrowKeys: v];
    [b setMaxVisibleColumns: v ? 5 : 2];
}

static int browserState(NSBrowser *b) {
    return [b isTitled] | ([b hasHorizontalScroller] << 1) |
           ([b separatesColumns] << 2) | ([b takesTitleFromPreviousColumn] << 3) |
           ([b allowsMultipleSelection] << 4) | ([b allowsBranchSelection] << 5) |
           ([b allowsEmptySelection] << 6) | ([b acceptsArrowKeys] << 7) |
           ((int) [b maxVisibleColumns] << 8);
}

static int wellState(NSColorWell *w) {
    return [w isBordered] | ([w isEnabled] << 1) | ([w isContinuous] << 2) |
           ([w isActive] << 3);
}

static void checkSubclasses(void) {
    SubBrowser *b = [[SubBrowser alloc] initWithFrame: NSMakeRect(0, 0, 300, 200)];
    [b setOwn];
    flipBrowser(b, YES);
    CHECK([b ownIntact], "SubBrowser lost its own ivars after setters");
    CHECK(browserState(b) == (0xff | (5 << 8)), "NSBrowser state %x after setting all flags", browserState(b));
    flipBrowser(b, NO);
    CHECK([b ownIntact], "SubBrowser lost its own ivars after the second set");
    CHECK(browserState(b) == (2 << 8), "NSBrowser state %x after clearing all flags", browserState(b));
    [b release];

    SubColorWell *w = [[SubColorWell alloc] initWithFrame: NSMakeRect(0, 0, 40, 24)];
    [w setOwn];
    [w setColor: [NSColor redColor]];
    [w setBordered: NO];
    [w setEnabled: NO];
    [w setContinuous: NO];
    CHECK([w ownIntact], "SubColorWell lost its own ivars after setters");
    CHECK(wellState(w) == 0, "NSColorWell state %x after clearing the flags", wellState(w));
    [w setBordered: YES];
    [w setEnabled: YES];
    [w setContinuous: YES];
    CHECK([w ownIntact], "SubColorWell lost its own ivars after the second set");
    CHECK(wellState(w) == 7, "NSColorWell state %x after setting the flags", wellState(w));
    CHECK([[w color] isEqual: [NSColor redColor]], "NSColorWell lost its color");
    [w release];
}

#if !__LP64__
static const unsigned char pattern = 0xa5;
enum { spare = 32 };

// An object of `cls` with spare bytes right after Apple's instance size, standing
// for the instance variables of a subclass compiled against the Mac layout.
static id spareInstance(const char *name, size_t appleSize, unsigned char **spareBytes) {
    Class cls = objc_getClass(name);
    id object = class_createInstance(cls, spare);
    *spareBytes = (unsigned char *) object + appleSize;
    return object;
}

static int spareIntact(const unsigned char *bytes) {
    for (int i = 0; i < spare; i++)
        if (bytes[i] != pattern)
            return 0;
    return 1;
}

static void checkAppleLayoutBrowser(void) {
    unsigned char *own;
    NSBrowser *b = spareInstance("NSBrowser", 160, &own);
    b = [b initWithFrame: NSMakeRect(0, 0, 300, 200)];
    flipBrowser(b, YES);
    int expected = browserState(b);
    memset(own, pattern, spare);
    CHECK(browserState(b) == expected, "NSBrowser state depends on the bytes after Apple's 160");
    flipBrowser(b, NO);
    CHECK(spareIntact(own), "NSBrowser wrote past Apple's 160 byte instance");
    CHECK(browserState(b) == (2 << 8), "NSBrowser state %x with a subclass's ivars set", browserState(b));
    CHECK(spareIntact(own), "NSBrowser wrote past Apple's 160 byte instance (reading)");
    [b release];
}

static void checkAppleLayoutColorWell(void) {
    unsigned char *own;
    NSColorWell *w = spareInstance("NSColorWell", 108, &own);
    w = [w initWithFrame: NSMakeRect(0, 0, 40, 24)];
    [w setBordered: YES];
    [w setEnabled: YES];
    [w setContinuous: YES];
    [w setColor: [NSColor blueColor]];
    int expected = wellState(w);
    memset(own, pattern, spare);
    CHECK(wellState(w) == expected, "NSColorWell state depends on the bytes after Apple's 108");
    [w setBordered: NO];
    [w setColor: [NSColor greenColor]];
    CHECK(spareIntact(own), "NSColorWell wrote past Apple's 108 byte instance");
    CHECK(![w isBordered] && [[w color] isEqual: [NSColor greenColor]],
          "NSColorWell state wrong with a subclass's ivars set");
    [w release];
}
#endif

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        checkSubclasses();
#if !__LP64__
        CHECK(class_getInstanceSize([SubBrowser class]) >= 160 + 16, "SubBrowser size %zu",
              class_getInstanceSize([SubBrowser class]));
        CHECK(ivar_getOffset(class_getInstanceVariable([SubBrowser class], "ownCounter")) == 160,
              "SubBrowser's first ivar is not at Apple's 160");
        CHECK(ivar_getOffset(class_getInstanceVariable([SubColorWell class], "ownCounter")) == 108,
              "SubColorWell's first ivar is not at Apple's 108");
        checkAppleLayoutBrowser();
        checkAppleLayoutColorWell();
#endif
    }
    if (failures != 0)
        return 1;
    printf("OK\n");
    return 0;
}
