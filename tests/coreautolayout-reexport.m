// Copyright (C) 2026 Lubos Dolezel
// The Auto Layout classes live in the private CoreAutoLayout framework; Foundation and AppKit re-export them.
// Programs bind the class symbols with either one as the library (newer SDKs: Foundation, older SDKs: AppKit),
// and both must give the same Class object as CoreAutoLayout itself.
//
// Build (guest-cc.sh), run on a display for the default mode:
//   default:         -framework Foundation -framework AppKit
//                    dlsym finds NSLayoutConstraint, NSLayoutAnchor, NSLayoutXAxisAnchor, NSLayoutYAxisAnchor and
//                    NSLayoutDimension through Foundation, AppKit and CoreAutoLayout with identical addresses,
//                    and constraints made from anchors and visual format strings lay out views in a window.
//   -DFOUNDATION_ONLY: -framework Foundation (not AppKit). The binary binds _OBJC_CLASS_$_NSLayoutConstraint
//                    to Foundation, so it fails to link or load when Foundation does not re-export it.
#import <Foundation/Foundation.h>
#include <dlfcn.h>
#include <math.h>
#include <stdio.h>
#ifndef FOUNDATION_ONLY
#import <AppKit/AppKit.h>
#else
@class NSLayoutConstraint;
@interface NSLayoutConstraint : NSObject
@end
#endif

static int failures;
#define CHECK(cond) do { if (!(cond)) { printf("FAIL: %s (line %d)\n", #cond, __LINE__); failures++; } } while (0)

static void *symbolIn(const char *path, const char *name) {
    void *handle = dlopen(path, RTLD_LAZY);
    return handle ? dlsym(handle, name) : NULL;
}

static void checkIdentity(void) {
#if __OBJC2__
    static const char *const libraries[] = {
        "/System/Library/Frameworks/Foundation.framework/Foundation",
#ifndef FOUNDATION_ONLY
        "/System/Library/Frameworks/AppKit.framework/AppKit",
#endif
        "/System/Library/PrivateFrameworks/CoreAutoLayout.framework/CoreAutoLayout",
    };
    static const char *const classes[] = {
        "NSLayoutConstraint", "NSLayoutAnchor", "NSLayoutXAxisAnchor", "NSLayoutYAxisAnchor", "NSLayoutDimension",
    };
    for (unsigned c = 0; c < sizeof(classes) / sizeof(classes[0]); c++) {
        char symbol[96];
        snprintf(symbol, sizeof(symbol), "OBJC_CLASS_$_%s", classes[c]);
        void *first = NULL;
        for (unsigned l = 0; l < sizeof(libraries) / sizeof(libraries[0]); l++) {
            void *address = symbolIn(libraries[l], symbol);
            if (address == NULL)
                printf("FAIL: dlsym(%s, %s) is NULL\n", libraries[l], symbol), failures++;
            else if (first == NULL)
                first = address;
            else if (address != first)
                printf("FAIL: %s differs between libraries\n", symbol), failures++;
        }
        CHECK(first != NULL && (Class) first == objc_getClass(classes[c]));
    }
    // the metaclass and the class objects agree with the runtime
    CHECK([NSLayoutConstraint class] == (Class) symbolIn(libraries[0], "OBJC_CLASS_$_NSLayoutConstraint"));
#else
    // the legacy ABI has no class symbols to bind; the classes are found by name in the runtime
    CHECK(objc_getClass("NSLayoutConstraint") != Nil && objc_getClass("NSLayoutDimension") != Nil);
    CHECK(symbolIn("/System/Library/PrivateFrameworks/CoreAutoLayout.framework/CoreAutoLayout",
                   "_NSDictionaryOfVariableBindings") != NULL);
#endif
}

#ifndef FOUNDATION_ONLY
static BOOL near(CGFloat a, CGFloat b) { return fabs(a - b) < .01; }

static void checkWindowLayout(void) {
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(100, 100, 300, 200)
                                                   styleMask:NSWindowStyleMaskTitled
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];
    NSView *content = [window contentView];
    NSView *a = [[[NSView alloc] initWithFrame:NSZeroRect] autorelease];
    NSView *b = [[[NSView alloc] initWithFrame:NSZeroRect] autorelease];
    [a setTranslatesAutoresizingMaskIntoConstraints:NO];
    [b setTranslatesAutoresizingMaskIntoConstraints:NO];
    [content addSubview:a];
    [content addSubview:b];

    NSMutableArray *constraints = [NSMutableArray array];
    [constraints addObject:[[a leftAnchor] constraintEqualToAnchor:[content leftAnchor] constant:10]];
    [constraints addObject:[[a topAnchor] constraintEqualToAnchor:[content topAnchor] constant:10]];
    [constraints addObject:[[a widthAnchor] constraintEqualToConstant:50]];
    [constraints addObject:[[a heightAnchor] constraintEqualToConstant:30]];
    [constraints addObjectsFromArray:[NSLayoutConstraint constraintsWithVisualFormat:@"H:[a]-8-[b(60)]"
                                                                             options:0
                                                                             metrics:nil
                                                                               views:NSDictionaryOfVariableBindings(a, b)]];
    [constraints addObject:[[b topAnchor] constraintEqualToAnchor:[a topAnchor]]];
    [constraints addObject:[[b heightAnchor] constraintEqualToAnchor:[a heightAnchor]]];
    for (NSLayoutConstraint *constraint in constraints)
        CHECK([constraint class] == [NSLayoutConstraint class] && ![constraint isActive]);
    [NSLayoutConstraint activateConstraints:constraints];
    for (NSLayoutConstraint *constraint in constraints)
        CHECK([constraint isActive]);

    [content layoutSubtreeIfNeeded];
    CHECK(near([a frame].size.width, 50) && near([a frame].size.height, 30) && near([a frame].origin.x, 10));
    CHECK(near([b frame].origin.x, 68) && near([b frame].size.width, 60) && near([b frame].size.height, 30));
    // a one-item constraint is held by its item, the others by the common ancestor
    CHECK([[content constraints] count] == 5 && [[a constraints] count] == 2 && [[b constraints] count] == 1);

    [NSLayoutConstraint deactivateConstraints:constraints];
    CHECK([[content constraints] count] == 0 && [[a constraints] count] == 0 && [[b constraints] count] == 0);
    [window close];
}
#endif

int main(void) {
    @autoreleasepool {
        checkIdentity();
#ifndef FOUNDATION_ONLY
        checkWindowLayout();
#endif
    }
    printf(failures ? "FAIL (%d)\n" : "PASS\n", failures);
    return failures ? 1 : 0;
}
