/*
 Copyright (C) 2026 Lubos Dolezel

 Licensed under the MIT license, the same as the rest of this project.
*/
// The hand-written protocol opcodes of both Wayland backends (AppKit's and CoreGraphics')
// must agree with the interface tables wayland-scanner generates from the protocol XML the
// bundles were built with: a wrong opcode would send one request in place of another.
// Each bundle checks itself at startup, WaylandCheckOpcodes() reports the result. Needs no
// compositor. Prints SKIP for a bundle that is not installed (they are built only with the
// Wayland development files).
#import <Foundation/Foundation.h>
#include <dlfcn.h>
#include <stdbool.h>
#include <stdio.h>

int main(void) {
    NSString *bundles[] = {
        @"/System/Library/Frameworks/AppKit.framework/Versions/C/Resources/Backends/Wayland.backend/Contents/MacOS/Wayland",
        @"/System/Library/Frameworks/CoreGraphics.framework/Versions/A/Resources/Backends/Wayland.backend/Contents/MacOS/Wayland",
    };
    int failures = 0, checked = 0;
    @autoreleasepool {
        for (size_t i = 0; i < sizeof(bundles) / sizeof(bundles[0]); i++) {
            if (![[NSFileManager defaultManager] fileExistsAtPath: bundles[i]]) {
                printf("SKIP: %s is not installed\n", [bundles[i] UTF8String]);
                continue;
            }
            void *handle = dlopen([bundles[i] fileSystemRepresentation], RTLD_NOW | RTLD_LOCAL);
            bool (*opcodesAgree)(void) = NULL;
            if (handle)
                opcodesAgree = (bool (*)(void)) dlsym(handle, "WaylandCheckOpcodes");
            if (!opcodesAgree) {
                fprintf(stderr, "FAIL: cannot load WaylandCheckOpcodes from %s: %s\n",
                        [bundles[i] UTF8String], dlerror());
                failures++;
                continue;
            }
            checked++;
            if (!opcodesAgree()) {
                fprintf(stderr, "FAIL: opcodes disagree with the generated tables in %s\n", [bundles[i] UTF8String]);
                failures++;
            }
        }
    }
    if (checked == 0 && failures == 0) {
        printf("SKIP: no Wayland backend installed\n");
        return 0;
    }
    printf(failures ? "FAIL\n" : "PASS\n");
    return failures ? 1 : 0;
}
