/*
 Copyright (C) 2026 Lubos Dolezel

 Licensed under the MIT license, the same as the rest of this project.
*/
// Which display server the Wayland backend claims. The environment variable
// DARLING_APPKIT_BACKEND comes first, then the DisplayBackend preference of the
// org.darlinghq.AppKit domain, then detection by WAYLAND_DISPLAY. Names are
// case-insensitive, an empty value counts as unset and an unknown value falls
// through to the next source. Needs no compositor: the backend bundle is loaded and
// its selection predicate called directly. Prints SKIP when the bundle is not
// installed (it is built only with the Wayland development files).
#import <Foundation/Foundation.h>
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>

static int failures;

static void setPreference(const char *value) {
    CFPreferencesSetAppValue(CFSTR("DisplayBackend"),
                             value ? (CFTypeRef) [NSString stringWithUTF8String: value] : NULL,
                             CFSTR("org.darlinghq.AppKit"));
    CFPreferencesAppSynchronize(CFSTR("org.darlinghq.AppKit"));
}

static void expectSelection(bool (*selected)(void), const char *env, const char *preference,
                  const char *display, bool expected) {
    if (env) setenv("DARLING_APPKIT_BACKEND", env, 1); else unsetenv("DARLING_APPKIT_BACKEND");
    if (display) setenv("WAYLAND_DISPLAY", display, 1); else unsetenv("WAYLAND_DISPLAY");
    setPreference(preference);
    bool got = selected();
    if (got != expected) {
        fprintf(stderr, "FAIL: env=%s preference=%s WAYLAND_DISPLAY=%s: got %d, expected %d\n",
                env ?: "(unset)", preference ?: "(unset)", display ?: "(unset)", got, expected);
        failures++;
    }
}

int main(void) {
    @autoreleasepool {
        NSString *path = @"/System/Library/Frameworks/AppKit.framework/Versions/C/Resources/"
                         @"Backends/Wayland.backend/Contents/MacOS/Wayland";
        if (![[NSFileManager defaultManager] fileExistsAtPath: path]) {
            printf("SKIP: Wayland backend not installed\n");
            return 0;
        }
        void *handle = dlopen([path fileSystemRepresentation], RTLD_NOW | RTLD_LOCAL);
        bool (*selected)(void) = handle ? dlsym(handle, "WaylandBackendSelected") : NULL;
        if (!selected) {
            printf("FAIL: cannot load WaylandBackendSelected: %s\n", dlerror());
            return 1;
        }

        // Detection alone.
        expectSelection(selected, NULL, NULL, "wayland-0", true);
        expectSelection(selected, NULL, NULL, NULL, false);
        expectSelection(selected, "", NULL, "wayland-0", true);
        // The environment decides, whatever the compositor and the preference say.
        expectSelection(selected, "wayland", "x11", NULL, true);
        expectSelection(selected, "WAYLAND", NULL, NULL, true);
        expectSelection(selected, "x11", "wayland", "wayland-0", false);
        expectSelection(selected, "X11", NULL, "wayland-0", false);
        // The preference decides when the environment says nothing usable.
        expectSelection(selected, NULL, "wayland", NULL, true);
        expectSelection(selected, NULL, "x11", "wayland-0", false);
        expectSelection(selected, "", "X11", "wayland-0", false);
        expectSelection(selected, "bogus", "wayland", NULL, true);
        // Unknown values fall through to detection.
        expectSelection(selected, "bogus", NULL, "wayland-0", true);
        expectSelection(selected, NULL, "bogus", NULL, false);

        setPreference(NULL);
        printf(failures ? "FAIL\n" : "PASS\n");
    }
    return failures ? 1 : 0;
}
