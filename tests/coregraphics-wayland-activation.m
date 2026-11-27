/*
 Copyright (C) 2026 Lubos Dolezel

 Licensed under the MIT license, the same as the rest of this project.
*/
// Activation of a process' windows on the Wayland backend, without AppKit (the program links only CoreGraphics and
// Foundation): a request for the process' activation (_CGSActivateProcess(), which another process makes with the process
// identifier; here the process makes it for itself) makes the process' connection to the compositor ask for the focus of
// the window that was activated last, through xdg-activation. The driver, coregraphics-wayland-activation.sh, reads the
// requests from the protocol log. The program prints READY once its window is shown, then makes the request, waits for it
// to be sent and prints DONE.
// Usage: coregraphics-wayland-activation
#import <Foundation/Foundation.h>
#include <CoreGraphics/CoreGraphics.h>
#include <dlfcn.h>
#include <stdio.h>
#include <unistd.h>

typedef struct {
    CGRect frame;
    bool unmanaged;
    bool translucent;
} ToplevelAttributes;

@protocol ToplevelWindow
- (CGError)setProperty:(CFStringRef)key value:(CFTypeRef)value;
- (CGError)orderWindow:(int)place relativeTo:(id)other;
- (CGError)drawImage:(CGImageRef)image atPoint:(CGPoint)origin;
@end

CGError _CGSActivateProcess(pid_t pid, uint32_t options);

static void listen(double seconds) {
    CFRunLoopRunInMode(kCFRunLoopDefaultMode, seconds, false);
}

int main(int argc, char **argv) {
    @autoreleasepool {
        id<ToplevelWindow> (*newToplevel)(const ToplevelAttributes *) = dlsym(RTLD_DEFAULT, "_CGSNewToplevelWindow");
        ToplevelAttributes attributes = {CGRectMake(100, 100, 300, 200), false, false};
        id<ToplevelWindow> window = newToplevel != NULL ? newToplevel(&attributes) : nil;
        if (window == nil) {
            printf("SKIP: this window system makes no toplevel windows\n");
            return 0;
        }
        [window setProperty:CFSTR("WindowTitle") value:@"tl-activation"];
        [window orderWindow:1 relativeTo:nil];
        CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
        CGContextRef context = CGBitmapContextCreate(NULL, 300, 200, 8, 0, space,
                                                     kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst);
        CGColorSpaceRelease(space);
        CGContextSetRGBFillColor(context, 0.2, 0.5, 0.8, 1);
        CGContextFillRect(context, CGRectMake(0, 0, 300, 200));
        CGImageRef image = CGBitmapContextCreateImage(context);
        CGContextRelease(context);
        [window drawImage:image atPoint:CGPointZero];
        CGImageRelease(image);
        listen(1.0);
        printf("READY\n");
        fflush(stdout);
        CGError error = _CGSActivateProcess(getpid(), 1);
        printf("%s: the request for the process' activation is accepted\n", error == kCGErrorSuccess ? "PASS" : "FAIL");
        listen(2.0);
        printf("DONE\n");
        fflush(stdout);
        return error == kCGErrorSuccess ? 0 : 1;
    }
}
