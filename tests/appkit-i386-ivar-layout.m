// Copyright (C) 2026 Lubos Dolezel
//
// On the legacy (32-bit) Objective-C ABI an application's subclass of an
// AppKit class is compiled against Apple's instance layout: its instance
// variables sit at offsets fixed at compile time, directly after the AppKit
// class's instance size. So each public AppKit class must report that size,
// keep the instance variables that public headers declare at their offsets,
// and the runtime must see the class and its subclasses as laid out one after
// the other (OBJC_DEBUG_FRAGILE_SUPERCLASSES=YES warns when a subclass's first
// instance variable is not past the last instance variable of its superclass).
//
// The expected values are what Mac OS X 10.14.4 reports for the same classes
// through the public runtime API (class_getInstanceSize, class_copyIvarList,
// ivar_getOffset; black-box observation, i386). The layout checks only run on
// the legacy ABI; the extra-state accessors at the end run everywhere.
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

#if !__LP64__
static const struct {
    const char *cls;
    size_t size;
} sizes[] = {
    {"NSResponder", 8},   {"NSView", 80},   {"NSWindow", 132},
    {"NSPanel", 132},     {"NSApplication", 76}, {"NSControl", 92},
    {"NSButton", 92},     {"NSCell", 20},
};

static const struct {
    const char *cls;
    const char *ivar;
    ptrdiff_t offset;
} offsets[] = {
    {"NSResponder", "_nextResponder", 4},
    {"NSView", "_frame", 8},       {"NSView", "_bounds", 24},
    {"NSView", "_superview", 40},  {"NSView", "_subviews", 44},
    {"NSView", "_window", 48},     {"NSView", "_layer", 60},
    {"NSWindow", "_frame", 8},     {"NSWindow", "_contentView", 24},
    {"NSWindow", "_delegate", 28}, {"NSWindow", "_firstResponder", 32},
    {"NSWindow", "_level", 60},    {"NSWindow", "_backgroundColor", 64},
    {"NSApplication", "_currentEvent", 8}, {"NSApplication", "_keyWindow", 16},
    {"NSApplication", "_mainWindow", 20},  {"NSApplication", "_delegate", 24},
    {"NSApplication", "_running", 50},     {"NSApplication", "_mainMenu", 56},
    {"NSControl", "_aux", 80},     {"NSControl", "_cell", 84},
};

// classes whose subclass chains an application can extend
static const char *chained[] = {
    "NSResponder", "NSView", "NSWindow", "NSPanel", "NSSavePanel", "NSOpenPanel",
    "NSApplication", "NSControl", "NSButton", "NSPopUpButton", "NSTextField",
    "NSViewController", "NSWindowController", "NSOpenGLView", "NSClipView",
    "NSScrollView", "NSMatrix", "NSTableView", "NSOutlineView",
};

static ptrdiff_t ivarOffset(Class cls, const char *name) {
    unsigned count = 0;
    Ivar *list = class_copyIvarList(cls, &count);
    ptrdiff_t result = -1;
    for (unsigned i = 0; i < count; i++)
        if (strcmp(ivar_getName(list[i]), name) == 0)
            result = ivar_getOffset(list[i]);
    free(list);
    return result;
}

static void checkLayout(void) {
    for (size_t i = 0; i < sizeof(sizes) / sizeof(sizes[0]); i++) {
        Class cls = objc_getClass(sizes[i].cls);
        CHECK(cls != Nil, "%s is missing", sizes[i].cls);
        if (cls != Nil)
            CHECK(class_getInstanceSize(cls) == sizes[i].size,
                  "%s instance size %zu, expected %zu", sizes[i].cls,
                  class_getInstanceSize(cls), sizes[i].size);
    }
    for (size_t i = 0; i < sizeof(offsets) / sizeof(offsets[0]); i++) {
        Class cls = objc_getClass(offsets[i].cls);
        if (cls == Nil)
            continue;
        ptrdiff_t offset = ivarOffset(cls, offsets[i].ivar);
        CHECK(offset == offsets[i].offset, "%s.%s at %td, expected %td",
              offsets[i].cls, offsets[i].ivar, offset, offsets[i].offset);
    }
    for (size_t i = 0; i < sizeof(chained) / sizeof(chained[0]); i++) {
        Class cls = objc_getClass(chained[i]);
        if (cls == Nil)
            continue;
        unsigned count = 0;
        Ivar *list = class_copyIvarList(cls, &count);
        for (unsigned j = 0; j < count; j++)
            // an instance variable at or past the end of the instance (such as
            // a zero-sized trailing one) overlaps the first one of any subclass
            CHECK((size_t) ivar_getOffset(list[j]) < class_getInstanceSize(cls),
                  "%s.%s at %td is not inside the %zu byte instance",
                  chained[i], ivar_getName(list[j]), ivar_getOffset(list[j]),
                  class_getInstanceSize(cls));
        // the runtime's own check: this class's first instance variable is
        // past the last one of the closest superclass that has any
        if (count > 0) {
            Class super_ = class_getSuperclass(cls);
            unsigned superCount = 0;
            Ivar *superList = NULL;
            while (super_ != Nil) {
                superList = class_copyIvarList(super_, &superCount);
                if (superCount > 0)
                    break;
                free(superList);
                superList = NULL;
                super_ = class_getSuperclass(super_);
            }
            if (superCount > 0) {
                ptrdiff_t last = ivar_getOffset(superList[superCount - 1]);
                CHECK(ivar_getOffset(list[0]) > last,
                      "ivars of %s and %s overlap (%td <= %td)",
                      class_getName(super_), chained[i],
                      ivar_getOffset(list[0]), last);
                CHECK((size_t) ivar_getOffset(list[0]) >= class_getInstanceSize(super_),
                      "first ivar of %s at %td is inside %s (%zu bytes)",
                      chained[i], ivar_getOffset(list[0]),
                      class_getName(super_), class_getInstanceSize(super_));
            }
            free(superList);
        }
        free(list);
    }
}
#endif

// Classes that keep state beyond Apple's footprint in side storage must still
// hold it per object.
static void checkExtraState(void) {
    NSButton *first = [[NSButton alloc] initWithFrame: NSMakeRect(0, 0, 80, 20)];
    NSButton *second = [[NSButton alloc] initWithFrame: NSMakeRect(0, 0, 80, 20)];
    [first setContentTintColor: [NSColor redColor]];
    CHECK([first contentTintColor] != nil, "NSButton lost its content tint color");
    CHECK([second contentTintColor] == nil, "NSButton extras are shared between objects");
    [first release];
    [second release];

    NSPanel *panel = [[NSPanel alloc] initWithContentRect: NSMakeRect(0, 0, 100, 100)
                                                styleMask: NSTitledWindowMask
                                                  backing: NSBackingStoreBuffered
                                                    defer: YES];
    [panel setWorksWhenModal: YES];
    [panel setBecomesKeyOnlyIfNeeded: YES];
    CHECK([panel worksWhenModal], "NSPanel lost worksWhenModal");
    CHECK([panel becomesKeyOnlyIfNeeded], "NSPanel lost becomesKeyOnlyIfNeeded");
    [panel release];
}

int main(void) {
    @autoreleasepool {
#if !__LP64__
        checkLayout();
#endif
        checkExtraState();
    }
    if (failures != 0)
        return 1;
    printf("OK\n");
    return 0;
}
