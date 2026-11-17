// Copyright (C) 2026 Lubos Dolezel
//
// The Go to Folder sheet of an open panel (Command-Shift-G) takes typed text: the sheet opens, the characters typed
// with the keyboard (events queued for the sheet while the panel runs modally) arrive in its text field, and the
// modal loop waits for events instead of keeping the main thread busy (a timer keeps firing, little CPU time is
// used). A watchdog turns a stuck main thread into a failure. Needs a display.
#import <AppKit/AppKit.h>
#include <signal.h>
#include <time.h>
#include <stdio.h>
#include <unistd.h>

static int failures;
#define CHECK(...) do { if (!(__VA_ARGS__)) { fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #__VA_ARGS__); failures++; } } while (0)

static void spin(NSTimeInterval seconds) {
    [[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: seconds]];
}

static void watchdog(int sig) {
    static const char msg[] = "FAIL: the main thread is stuck\n";
    (void) !write(2, msg, sizeof msg - 1);
    _exit(2);
}

static void pressKey(NSWindow *window, NSString *chars, NSString *plain, NSUInteger flags) {
    NSEvent *event = [NSEvent keyEventWithType: NSKeyDown location: NSZeroPoint modifierFlags: flags
                                     timestamp: 0 windowNumber: [window windowNumber] context: nil
                                    characters: chars charactersIgnoringModifiers: plain
                                     isARepeat: NO keyCode: 0];
    [NSApp postEvent: event atStart: NO];
}

static NSTextField *editableFieldOf(NSView *view) {
    if ([view isKindOfClass: [NSTextField class]] && [(NSTextField *) view isEditable])
        return (NSTextField *) view;
    for (NSView *sub in [view subviews]) {
        NSTextField *found = editableFieldOf(sub);
        if (found != nil)
            return found;
    }
    return nil;
}

int main(void)
{
    signal(SIGALRM, watchdog);
    alarm(60);
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSOpenPanel *panel = [NSOpenPanel openPanel];
        [panel setDirectoryURL: [NSURL fileURLWithPath: NSTemporaryDirectory() isDirectory: YES]];

        // The user drives the modal panel: Command-Shift-G, a pause, typing, Cancel. Each step is a timer of the
        // modal run loop.
        __block int ticks = 0, ticksBeforeTyping = 0;
        __block NSString *typed = nil, *folder = nil;
        __block BOOL sheetShown = NO;
        __block clock_t cpuStart = 0;
        __block double cpuUsed = 0;
        NSTimer *counter = [NSTimer timerWithTimeInterval: 0.02 repeats: YES block: ^(NSTimer *t) { ticks++; }];
        [[NSRunLoop currentRunLoop] addTimer: counter forMode: NSRunLoopCommonModes];
        void (^later)(NSTimeInterval, void (^)(void)) = ^(NSTimeInterval delay, void (^block)(void)) {
            NSTimer *t = [NSTimer timerWithTimeInterval: delay repeats: NO block: ^(NSTimer *timer) { block(); }];
            [[NSRunLoop currentRunLoop] addTimer: t forMode: NSRunLoopCommonModes];
        };
        later(0.5, ^{
            pressKey(panel, @"G", @"g", NSCommandKeyMask | NSShiftKeyMask);
        });
        later(0.8, ^{
            sheetShown = [panel attachedSheet] != nil;
            cpuStart = clock();
        });
        later(2.8, ^{
            ticksBeforeTyping = ticks;
            cpuUsed = (double) (clock() - cpuStart) / CLOCKS_PER_SEC;
            NSWindow *sheet = [panel attachedSheet];
            for (NSString *c in @[ @"a", @"b", @"c" ])
                pressKey(sheet, c, c, 0);
        });
        later(3.5, ^{
            // replace the text by an existing folder and confirm with Return: the panel goes there
            NSWindow *sheet = [panel attachedSheet];
            [editableFieldOf([sheet contentView]) setStringValue: @"/usr"];
            pressKey(sheet, @"\r", @"\r", 0);
        });
        later(4.0, ^{ folder = [[[panel directoryURL] path] copy]; });
        later(3.3, ^{
            NSWindow *sheet = [panel attachedSheet];
            id responder = [sheet firstResponder];
            typed = [responder isKindOfClass: [NSTextView class]] ? [[(NSTextView *) responder string] copy]
                                                                   : [editableFieldOf([sheet contentView]) stringValue];
        });
        later(4.3, ^{ [panel cancel: nil]; });
        [panel runModal];
        [counter invalidate];

        CHECK(sheetShown);
        // the 0.02 s timer fired for most of the two seconds with the sheet up, and the loop mostly slept
        CHECK(ticksBeforeTyping > 60);
        CHECK(cpuUsed < 1.0);
        CHECK([typed isEqual: @"abc"]);
        CHECK([folder isEqual: @"/usr"]);
    }
    if (failures == 0)
        puts("PASS");
    return failures ? 1 : 0;
}
