/*
 Copyright (C) 2026 Lubos Dolezel

 Licensed under the MIT license, the same as the rest of this project.
*/
// A dialog shown while a fully transparent window is the key window of the application: when the
// application asks for the key status (makeKeyAndOrderFront:, runModalForWindow:) the dialog
// becomes key and Return clicks its default button; ordering it in does not make it key (the
// transparent window stays key and gets the keys, as the application that put it there expects). argv[1] is "front" (makeKeyAndOrderFront:) or "modal"
// (runModalForWindow:) or "order" (orderFront:, which does not ask for the key status), argv[2] the seconds to wait for the typed Return. Run by run.sh.
#import <AppKit/AppKit.h>
#include <stdio.h>

static int clicks;

@interface DialogTarget : NSObject
- (void) okay: (id) sender;
@end

@implementation DialogTarget
- (void) okay: (id) sender {
    clicks++;
    [NSApp stopModal];
}
@end

@interface HiddenWindow : NSWindow
@end
@implementation HiddenWindow
- (BOOL) canBecomeKeyWindow { return YES; }
@end

int main(int argc, char **argv) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        BOOL modal = argc > 1 && !strcmp(argv[1], "modal");
        BOOL order = argc > 1 && !strcmp(argv[1], "order");
        NSTimeInterval wait = argc > 2 ? atof(argv[2]) : 12;
        DialogTarget *target = [[DialogTarget alloc] init];

        NSWindow *hidden = [[HiddenWindow alloc] initWithContentRect: NSMakeRect(0, 0, 200, 100)
                                                           styleMask: NSWindowStyleMaskTitled
                                                             backing: NSBackingStoreBuffered
                                                               defer: NO];
        [hidden setTitle: @"dd-hidden"];
        [hidden setAlphaValue: 0];
        [hidden makeKeyAndOrderFront: nil];

        NSWindow *dialog = [[NSWindow alloc] initWithContentRect: NSMakeRect(300, 300, 360, 200)
                                                       styleMask: NSWindowStyleMaskTitled
                                                         backing: NSBackingStoreBuffered
                                                           defer: NO];
        [dialog setTitle: @"dd-dialog"];
        NSScrollView *scroll = [[NSScrollView alloc] initWithFrame: NSMakeRect(10, 50, 340, 140)];
        NSTextView *text = [[NSTextView alloc] initWithFrame: NSMakeRect(0, 0, 340, 140)];
        [text setString: @"Thank you for taking a look."];
        [text setEditable: NO];
        [scroll setDocumentView: text];
        [[dialog contentView] addSubview: scroll];
        NSButton *okay = [[NSButton alloc] initWithFrame: NSMakeRect(250, 10, 90, 30)];
        [okay setTitle: @"Okay"];
        [okay setBezelStyle: NSRoundedBezelStyle];
        [okay setKeyEquivalent: @"\r"];
        [okay setTarget: target];
        [okay setAction: @selector(okay:)];
        [[dialog contentView] addSubview: okay];

        // Common modes, so that the timers also run while the modal session does.
        NSTimer *ready = [NSTimer timerWithTimeInterval: 2 repeats: NO block: ^(NSTimer *timer) {
            printf("KEY dialog=%d hidden=%d\n", [dialog isKeyWindow], [hidden isKeyWindow]);
            printf("READY\n");
            fflush(stdout);
        }];
        NSTimer *giveUp = [NSTimer timerWithTimeInterval: wait repeats: NO block: ^(NSTimer *timer) {
            [NSApp abortModal];
        }];
        [[NSRunLoop currentRunLoop] addTimer: ready forMode: NSRunLoopCommonModes];
        [[NSRunLoop currentRunLoop] addTimer: giveUp forMode: NSRunLoopCommonModes];
        if (modal) {
            [dialog makeKeyAndOrderFront: nil];
            [NSApp runModalForWindow: dialog];
        } else {
            if (order)
                [dialog orderFront: nil];
            else
                [dialog makeKeyAndOrderFront: nil];
            NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow: wait];
            while ([deadline timeIntervalSinceNow] > 0 && clicks == 0) {
                NSEvent *event = [NSApp nextEventMatchingMask: NSAnyEventMask
                                                    untilDate: [NSDate dateWithTimeIntervalSinceNow: 0.1]
                                                       inMode: NSDefaultRunLoopMode
                                                      dequeue: YES];
                if (event != nil)
                    [NSApp sendEvent: event];
            }
        }
        printf("KEY dialog=%d hidden=%d\n", [dialog isKeyWindow], [hidden isKeyWindow]);
        printf("CLICKS %d\n", clicks);
        BOOL ok = order ? (clicks == 0 && [hidden isKeyWindow] && ![dialog isKeyWindow]) : clicks == 1;
        printf(ok ? "DONE\n" : "FAILED\n");
        return !ok;
    }
}
