/*
 Copyright (C) 2026 Lubos Dolezel

 Licensed under the MIT license, the same as the rest of this project.
*/
// What the window system does for the application's menu, on the Wayland backend and without AppKit (the program links
// only CoreGraphics and Foundation): whether the compositor carries the address of a window's application menu (KDE's
// appmenu protocol) and places a menu bar window (wlr-layer-shell), the flag the framework above sets once it found a
// desktop that shows application menus, and the address of a window's menu, which is accepted whether or not the compositor
// has the protocol. The program prints "FLAGS carries=<0|1> places=<0|1>" for the driver to compare with what the
// compositor offers, and PASS or FAIL lines, then RESULT.
// Usage: coregraphics-wayland-menu-capability
#import <Foundation/Foundation.h>
#include <CoreGraphics/CoreGraphics.h>
#import <CoreGraphics/CGSWindow.h>
#include <dlfcn.h>
#include <stdio.h>

@protocol ToplevelWindow
- (CGError)setProperty:(CFStringRef)key value:(CFTypeRef)value;
- (CGError)orderWindow:(int)place relativeTo:(id)other;
- (CGError)setToplevelApplicationMenuServiceName:(NSString *)service objectPath:(NSString *)path;
- (CGError)drawImage:(CGImageRef)image atPoint:(CGPoint)origin;
@end

static int failures;
#define CHECK(cond, what)                                                      \
    do {                                                                       \
        if (cond)                                                              \
            printf("PASS: %s\n", what);                                        \
        else {                                                                 \
            printf("FAIL: %s (line %d)\n", what, __LINE__);                    \
            failures++;                                                        \
        }                                                                      \
    } while (0)

int main(void) {
    @autoreleasepool {
        id<ToplevelWindow> (*newToplevel)(const CGSToplevelAttributes *) = dlsym(RTLD_DEFAULT, "_CGSNewToplevelWindow");
        BOOL (*carries)(void) = dlsym(RTLD_DEFAULT, "_CGSNativeConnectionCarriesApplicationMenuAddress");
        BOOL (*places)(void) = dlsym(RTLD_DEFAULT, "_CGSNativeConnectionPlacesMenuBar");
        BOOL (*available)(void) = dlsym(RTLD_DEFAULT, "_CGSNativeConnectionGlobalMenuAvailable");
        void (*setAvailable)(BOOL) = dlsym(RTLD_DEFAULT, "_CGSNativeConnectionSetGlobalMenuAvailable");
        if (!newToplevel || !carries || !places || !available || !setAvailable) {
            printf("FAIL: the menu functions are missing\n");
            return 1;
        }
        CGSToplevelAttributes attributes = {CGRectMake(100, 100, 200, 100), false, false};
        id<ToplevelWindow> window = newToplevel(&attributes);
        if (window == nil) {
            printf("SKIP: this window system makes no toplevel windows\n");
            return 0;
        }
        printf("FLAGS carries=%d places=%d\n", carries(), places());
        CHECK(!available(), "no desktop menu is known before the framework above says so");
        setAvailable(YES);
        CHECK(available(), "what the framework above said is kept");
        setAvailable(NO);
        CHECK(!available(), "it can be taken back");
        CHECK([window setToplevelApplicationMenuServiceName:@"org.example.menu" objectPath:@"/MenuBar"] == 0,
              "the address of a menu is accepted before the window is shown");
        [window orderWindow:1 relativeTo:nil];
        CFRunLoopRunInMode(kCFRunLoopDefaultMode, 1.0, false);
        CHECK([window setToplevelApplicationMenuServiceName:nil objectPath:nil] == 0, "the address can be withdrawn");
        CHECK([window setToplevelApplicationMenuServiceName:@"org.example.menu" objectPath:@"/MenuBar"] == 0,
              "and given again while the window is shown");
        CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.5, false);
        printf("RESULT failures=%d\n", failures);
    }
    return failures != 0;
}
