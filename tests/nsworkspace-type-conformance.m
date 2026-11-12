// Copyright (C) 2026 Lubos Dolezel
//
// -[NSWorkspace type:conformsToType:] and the +sharedWorkspace class property,
// from the public contract: an identifier conforms to itself and to every type
// above it in the hierarchy (public.png -> public.image -> public.data ->
// public.item), not to unrelated types, and not to a type below it; an unknown
// identifier conforms only to itself. +sharedWorkspace is the same object
// through the class property and the class method.
#import <AppKit/AppKit.h>
#include <stdio.h>

static int failures;

#define CHECK(cond, ...) \
    do { \
        if (!(cond)) { \
            fprintf(stderr, "FAIL line %d: ", __LINE__); \
            fprintf(stderr, __VA_ARGS__); \
            fputc('\n', stderr); \
            failures++; \
        } \
    } while (0)

int main(void) {
    @autoreleasepool {
        NSWorkspace *workspace = NSWorkspace.sharedWorkspace;
        CHECK(workspace != nil && workspace == [NSWorkspace sharedWorkspace], "sharedWorkspace class property");

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        CHECK([workspace type: @"public.png" conformsToType: @"public.png"], "png conforms to itself");
        CHECK([workspace type: @"public.png" conformsToType: @"public.image"], "png conforms to image");
        CHECK([workspace type: @"public.png" conformsToType: @"public.data"], "png conforms to data");
        CHECK([workspace type: @"public.png" conformsToType: @"public.item"], "png conforms to item");
        CHECK(![workspace type: @"public.png" conformsToType: @"public.text"], "png does not conform to text");
        CHECK(![workspace type: @"public.image" conformsToType: @"public.png"], "image does not conform to png");
        CHECK([workspace type: @"public.plain-text" conformsToType: @"public.text"], "plain text conforms to text");
        CHECK([workspace type: @"public.html" conformsToType: @"public.text"], "html conforms to text");
        CHECK([workspace type: @"com.example.no-such-type" conformsToType: @"com.example.no-such-type"],
              "an unknown identifier conforms to itself");
        CHECK(![workspace type: @"com.example.no-such-type" conformsToType: @"public.data"],
              "an unknown identifier does not conform to data");
        CHECK(![workspace type: @"public.png" conformsToType: @"com.example.no-such-type"], "png does not conform to an unknown type");
#pragma clang diagnostic pop
    }
    if (failures) {
        fprintf(stderr, "%d failure(s)\n", failures);
        return 1;
    }
    puts("PASS: NSWorkspace type conformance");
    return 0;
}
