#import <AppKit/AppKit.h>
#import <objc/runtime.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// Shared by the collection layout tests. The classes are looked up by name so a test runs, and fails with a message,
// against an AppKit that lacks them.
static void expect(BOOL condition, NSString *message) {
    if (!condition) {
        printf("FAIL: %s\n", [message UTF8String]);
        exit(1);
    }
}

// The NSCollectionLayout* classes come from the CollectionViewCore image AppKit re-exports (the stand-in on plain
// Darling), not from AppKit itself: a copy in AppKit would be a duplicate of the cache's class on a cache stage.
static void expectFromCollectionViewCore(Class cls) {
    const char *image = cls != Nil ? class_getImageName(cls) : NULL;
    expect(image != NULL && strstr(image, "/CollectionViewCore.framework/") != NULL,
           [NSString stringWithFormat: @"%s is defined by CollectionViewCore (image: %s)",
                                       cls != Nil ? class_getName(cls) : "(missing class)", image ? image : "none"]);
}
