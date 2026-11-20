/*
 Copyright (C) 2026 Lubos Dolezel

 Licensed under the MIT license, the same as the rest of this project.
*/
// A window controller keeps its window when the window is closed: -window
// returns the same window afterwards, -isWindowLoaded stays YES, -close again
// does nothing, and -showWindow: shows that same window again. A window
// controller whose -window is asked for after a close does not load its nib
// again. Closing the window of a document's only window controller still
// closes the document. Results as on macOS 26.7.3 and 10.14.4.
// Needs a display. Prints PASS/FAIL lines; exit status 1 on failure. No ARC.
#import <AppKit/AppKit.h>
#include <stdio.h>

static int failures;
static int willClose;

static void expect(BOOL ok, const char *label) {
    printf("%s %s\n", ok ? "PASS" : "FAIL", label);
    failures += !ok;
}

@interface CloseCounter : NSObject
@end

@implementation CloseCounter
- (void) windowWillClose: (NSNotification *) note {
    willClose++;
}
@end

// A window controller made with a nib name whose window is set in code: it
// counts the times it is asked to load its window.
@interface CountingController : NSWindowController {
@public
    int _loads;
}
@end

@implementation CountingController
- (void) loadWindow {
    _loads++;
    [self setWindow: [[[NSWindow alloc] initWithContentRect: NSMakeRect(100, 100, 200, 100)
                                                  styleMask: NSWindowStyleMaskTitled
                                                    backing: NSBackingStoreBuffered
                                                      defer: NO] autorelease]];
}
@end

@interface ClosingDocument : NSDocument {
@public
    BOOL _closed;
}
@end

@implementation ClosingDocument
- (void) close {
    _closed = YES;
    [super close];
}
@end

int main(void) {
    setvbuf(stdout, NULL, _IONBF, 0);
    @autoreleasepool {
        [NSApplication sharedApplication];
        CloseCounter *counter = [[CloseCounter alloc] init];
        [[NSNotificationCenter defaultCenter] addObserver: counter selector: @selector(windowWillClose:)
                                                     name: NSWindowWillCloseNotification object: nil];

        NSWindow *window = [[NSWindow alloc] initWithContentRect: NSMakeRect(100, 100, 200, 100)
                                                       styleMask: NSWindowStyleMaskTitled
                                                         backing: NSBackingStoreBuffered
                                                           defer: NO];
        NSWindowController *controller = [[NSWindowController alloc] initWithWindow: window];
        expect(![window isReleasedWhenClosed], "a controller's window is not released when closed");
        [controller showWindow: nil];
        expect([window isVisible], "-showWindow: shows the window");
        [controller close];
        expect(willClose == 1 && ![window isVisible], "-close closes the window");
        expect([controller window] == window, "the controller keeps its window after the close");
        expect([controller isWindowLoaded], "the window is still loaded after the close");
        [controller close];
        expect(willClose == 1, "a second -close posts no second will-close notification");
        [controller showWindow: nil];
        expect([window isVisible] && [controller window] == window, "-showWindow: shows the same window again");
        [controller close];
        expect(willClose == 2 && [controller window] == window, "closing it again keeps the window");
        [controller release];
        [window release];

        CountingController *counting = [[CountingController alloc] initWithWindowNibName: @"NoSuchNib"];
        NSWindow *loaded = [counting window];
        [counting showWindow: nil];
        [counting close];
        expect([counting window] == loaded && counting->_loads == 1, "-window after a close does not load the window again");
        [counting close];
        expect(counting->_loads == 1, "-close after a close does not load the window again");
        [counting release];

        ClosingDocument *document = [[ClosingDocument alloc] init];
        NSWindow *documentWindow = [[NSWindow alloc] initWithContentRect: NSMakeRect(100, 100, 200, 100)
                                                               styleMask: NSWindowStyleMaskTitled
                                                                 backing: NSBackingStoreBuffered
                                                                   defer: NO];
        NSWindowController *documentController = [[NSWindowController alloc] initWithWindow: documentWindow];
        [document addWindowController: documentController];
        [documentController showWindow: nil];
        [documentWindow close];
        expect(document->_closed, "closing the window of a document's only window controller closes the document");
        [documentController release];
        [documentWindow release];
        [document release];

        [[NSNotificationCenter defaultCenter] removeObserver: counter];
        [counter release];
    }
    printf("failures=%d\n", failures);
    return failures ? 1 : 0;
}
