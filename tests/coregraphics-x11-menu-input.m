/*
 Copyright (C) 2026 Lubos Dolezel

 Licensed under the MIT license, the same as the rest of this project.
*/
// The parts of the application's menus that belong to the window system, on the X11 backend and without AppKit (the program
// links only CoreGraphics and Foundation):
//  - the window of a menu that is being tracked holds the pointer and the keyboard of the connection while it is shown
//    (-[CGSWindow setToplevelHoldsInputForMenu:]), for the newest such window, and lets go when none is shown;
//  - the address of a window's application menu is a property of the window (-[CGSWindow
//    setToplevelApplicationMenuServiceName:objectPath:]), withdrawn with nil;
//  - what the window system does for the menu (_CGSNativeConnectionCarriesApplicationMenuAddress() and the functions that
//    follow it).
// The driver, coregraphics-x11-menu-input.sh, asks the X server what became of the windows: another client tries to grab the
// pointer and the keyboard. The program prints READY, then waits for the files go1 to go4 in the directory it is given and
// prints STAGE <n> when it has done what the stage says.
// Usage: coregraphics-x11-menu-input <directory>
#import <Foundation/Foundation.h>
#include <CoreGraphics/CoreGraphics.h>
#import <CoreGraphics/CGSWindow.h>
#include <dlfcn.h>
#include <stdio.h>
#include <unistd.h>

@protocol ToplevelWindow
- (CGError)setProperty:(CFStringRef)key value:(CFTypeRef)value;
- (CGError)orderWindow:(int)place relativeTo:(id)other;
- (CGError)setToplevelHints:(const CGSToplevelHints *)hints;
- (CGError)setToplevelHoldsInputForMenu:(BOOL)holds;
- (CGError)setToplevelApplicationMenuServiceName:(NSString *)service objectPath:(NSString *)path;
- (CGError)drawImage:(CGImageRef)image atPoint:(CGPoint)origin;
- (unsigned)windowId;
- (void *)nativeWindow;
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

static void listen(double seconds) {
    CFRunLoopRunInMode(kCFRunLoopDefaultMode, seconds, false);
}

static void waitFor(const char *directory, const char *name) {
    char path[1024];
    snprintf(path, sizeof(path), "%s/%s", directory, name);
    for (int i = 0; i < 1200 && access(path, F_OK) != 0; i++)
        listen(0.1);
}

static void stage(int n) {
    printf("STAGE %d\n", n);
    fflush(stdout);
}

static id<ToplevelWindow> make(id<ToplevelWindow> (*newToplevel)(const CGSToplevelAttributes *), const char *title, CGFloat x,
                               BOOL unmanaged) {
    CGSToplevelAttributes attributes = {CGRectMake(x, 200, 160, 120), unmanaged, false};
    id<ToplevelWindow> window = newToplevel(&attributes);
    [window setProperty:CFSTR("WindowTitle") value:[NSString stringWithUTF8String:title]];
    CGSToplevelHints hints = {unmanaged ? kCGSToplevelKindDropdownMenu : kCGSToplevelKindNormal, !unmanaged, !unmanaged, true,
                              nil};
    [window setToplevelHints:&hints];
    return window;
}

int main(int argc, char **argv) {
    @autoreleasepool {
        if (argc != 2)
            return 2;
        id<ToplevelWindow> (*newToplevel)(const CGSToplevelAttributes *) = dlsym(RTLD_DEFAULT, "_CGSNewToplevelWindow");
        BOOL (*carries)(void) = dlsym(RTLD_DEFAULT, "_CGSNativeConnectionCarriesApplicationMenuAddress");
        BOOL (*places)(void) = dlsym(RTLD_DEFAULT, "_CGSNativeConnectionPlacesMenuBar");
        BOOL (*available)(void) = dlsym(RTLD_DEFAULT, "_CGSNativeConnectionGlobalMenuAvailable");
        void (*setAvailable)(BOOL) = dlsym(RTLD_DEFAULT, "_CGSNativeConnectionSetGlobalMenuAvailable");
        if (!newToplevel || !carries || !places || !available || !setAvailable) {
            printf("FAIL: the menu functions are missing\n");
            return 1;
        }
        id<ToplevelWindow> window = make(newToplevel, "menu-window", 20, NO);
        if (window == nil) {
            printf("SKIP: this window system makes no toplevel windows\n");
            return 0;
        }
        CHECK(carries(), "the window system carries the address of an application menu");
        printf("FLAGS places=%d\n", places());
        CHECK(!available(), "no desktop menu is known before the framework above says so");
        setAvailable(YES);
        CHECK(available(), "what the framework above said is kept");
        setAvailable(NO);
        CHECK(!available(), "it can be taken back");

        [window orderWindow:1 relativeTo:nil];
        CHECK([window setToplevelApplicationMenuServiceName:@"org.example.menu" objectPath:@"/MenuBar"] == 0,
              "the address of the menu is accepted");
        id<ToplevelWindow> first = make(newToplevel, "menu-first", 240, YES);
        id<ToplevelWindow> second = make(newToplevel, "menu-second", 420, YES);
        CHECK([first setToplevelHoldsInputForMenu:YES] == 0, "a menu window is given the input of the menu");
        CHECK([second setToplevelHoldsInputForMenu:YES] == 0, "so is another");
        listen(0.5);
        printf("READY %u\n", [window windowId]);
        fflush(stdout);

        // Stage 1: a menu is shown, and the pointer and the keyboard are held for it.
        waitFor(argv[1], "go1");
        [first orderWindow:1 relativeTo:nil];
        listen(0.5);
        stage(1);

        // Stage 2: a second menu; hiding it leaves the first holding.
        waitFor(argv[1], "go2");
        [second orderWindow:1 relativeTo:nil];
        listen(0.3);
        [second orderWindow:0 relativeTo:nil];
        listen(0.5);
        stage(2);

        // Stage 3: the last is hidden, and the input is let go.
        waitFor(argv[1], "go3");
        [first orderWindow:0 relativeTo:nil];
        listen(0.5);
        stage(3);

        // Stage 4: the address is withdrawn.
        waitFor(argv[1], "go4");
        CHECK([window setToplevelApplicationMenuServiceName:nil objectPath:nil] == 0, "the address can be withdrawn");
        listen(0.3);
        stage(4);
        waitFor(argv[1], "go5");
        printf("RESULT failures=%d\n", failures);
        fflush(stdout);
    }
    return failures != 0;
}
