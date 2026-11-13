/*
 Copyright (C) 2026 Lubos Dolezel

 Licensed under the MIT license, the same as the rest of this project.
*/
// Guest side of appkit-unordered-windows.py: windows that have not been
// ordered in are not on the screen. The program creates windows in several
// ways without ordering any of them in, lets the application finish launching
// and become active, and logs what it did; the host script then looks at the
// X server (xwininfo) and finds no mapped window of the program except the one
// that was ordered in, titled "visible" (and a window of the nib that the nib
// itself shows at launch).
//
//   appkit-unordered-windows LOG [Fixture.nib]
//
// With a nib (tests/fixtures/Fixture.nib), its window is loaded as well.
#import <AppKit/AppKit.h>
#include <stdio.h>
#include <stdlib.h>

static FILE *logFile;

static void note(const char *format, ...) __attribute__((format(printf, 1, 2)));
static void note(const char *format, ...) {
    va_list args;

    va_start(args, format);
    vfprintf(logFile, format, args);
    va_end(args);
    fputc('\n', logFile);
    fflush(logFile);
}

@interface FixtureOwner : NSObject {
    NSWindow *_window;
    NSTextField *_label;
}
@property (strong) IBOutlet NSWindow *window;
@property (strong) IBOutlet NSTextField *label;
- (IBAction) press: (id) sender;
@end
@implementation FixtureOwner
@synthesize window = _window, label = _label;
- (IBAction) press: (id) sender {
}
@end

static NSMutableArray *keep;

static NSWindow *make(Class cls, NSString *title, NSWindowStyleMask mask, BOOL defer) {
    NSWindow *window = [[cls alloc] initWithContentRect: NSMakeRect(300 + 20 * [keep count], 300, 260, 140)
                                              styleMask: mask
                                                backing: NSBackingStoreBuffered
                                                  defer: defer];
    [window setTitle: title];
    [keep addObject: window];
    return window;
}

@interface Target : NSObject <NSApplicationDelegate>
@end
@implementation Target
- (void) applicationDidFinishLaunching: (NSNotification *) n {
    [self performSelector: @selector(ready) withObject: nil afterDelay: 2.0];
}
- (void) ready {
    note("READY");
}
@end

int main(int argc, char **argv) {
    @autoreleasepool {
        if (argc < 2)
            return 2;
        logFile = fopen(argv[1], "a");
        if (logFile == NULL)
            return 2;
        keep = [NSMutableArray array];
        [NSApplication sharedApplication];
        [NSApp setDelegate: [Target new]];

        NSWindowStyleMask titled = NSWindowStyleMaskTitled | NSWindowStyleMaskClosable;
        NSWindow *w;

        make([NSWindow class], @"deferred", titled, YES);
        make([NSWindow class], @"not-deferred", titled, NO);
        make([NSPanel class], @"deferred-panel", titled | NSWindowStyleMaskUtilityWindow, YES);
        NSPanel *floating = (NSPanel *) make([NSPanel class], @"floating-panel", titled | NSWindowStyleMaskUtilityWindow, NO);
        [floating setFloatingPanel: YES];
        [floating setHidesOnDeactivate: YES];
        make([NSWindow class], @"borderless", NSWindowStyleMaskBorderless, NO);

        // Things done to a window that is not on the screen.
        w = make([NSWindow class], @"configured", titled, YES);
        [w setContentView: [[NSView alloc] initWithFrame: NSMakeRect(0, 0, 260, 140)]];
        [w setFrame: NSMakeRect(500, 400, 300, 200) display: YES];
        [w setLevel: NSFloatingWindowLevel];
        [w setHidesOnDeactivate: YES];
        [w setAlphaValue: 0.9];
        [w display];
        note("configured number=%ld visible=%d", (long) [w windowNumber], (int) [w isVisible]);

        w = make([NSWindow class], @"made-key", titled, NO);
        [w makeKeyWindow];
        [w makeMainWindow];
        note("made-key visible=%d", (int) [w isVisible]);

        w = make([NSWindow class], @"ordered-out", titled, NO);
        [w orderFront: nil];
        [w orderOut: nil];

        NSWindow *deferred = make([NSWindow class], @"deferred-number", titled, YES);
        note("deferred number=%ld", (long) [deferred windowNumber]);

        if (argc > 2) {
            NSString *path = [NSString stringWithUTF8String: argv[2]];
            NSBundle *bundle = [NSBundle bundleWithPath: [path stringByDeletingLastPathComponent]];
            NSNib *nib = [[NSNib alloc] initWithNibNamed: [[path lastPathComponent] stringByDeletingPathExtension]
                                                  bundle: bundle];
            FixtureOwner *owner = [FixtureOwner new];
            NSArray *top = nil;
            note("nib loaded=%d", (int) [nib instantiateWithOwner: owner topLevelObjects: &top]);
            [keep addObject: owner];
            [keep addObject: top];
            note("nib window visible=%d", (int) [[owner window] isVisible]);
        }

        w = make([NSWindow class], @"visible", titled, NO);
        [w makeKeyAndOrderFront: nil];

        [NSTimer scheduledTimerWithTimeInterval: 60 repeats: NO block: ^(NSTimer *t) {
            exit(3);
        }];
        [NSApp run];
    }
    return 0;
}
