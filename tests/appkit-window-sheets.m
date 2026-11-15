/*
 Copyright (C) 2026 Lubos Dolezel

 Licensed under the MIT license, the same as the rest of this project.
*/
// NSWindow sheets: -sheets lists the attached sheet, the delegate is told when
// a sheet begins and ends, and -beginCriticalSheet:completionHandler: presents
// the sheet like -beginSheet:completionHandler:. Needs a display. Expected
// behaviour was observed on macOS 10.14.4 and 26.7.3.
#import <AppKit/AppKit.h>
#include <stdio.h>

@interface NSWindow (SheetsTest)
- (NSArray *) sheets;
- (void) beginCriticalSheet: (NSWindow *) sheet
          completionHandler: (void (^)(NSModalResponse returnCode)) handler;
@end

static int failures;

static void expect(BOOL condition, const char *what) {
    if (!condition) {
        fprintf(stderr, "FAIL: %s\n", what);
        failures++;
    }
}

@interface Delegate : NSObject <NSWindowDelegate> {
  @public
    int began, ended;
}
@end

@implementation Delegate
- (void) windowWillBeginSheet: (NSNotification *) note {
    began++;
}
- (void) windowDidEndSheet: (NSNotification *) note {
    ended++;
}
@end

static void spin(NSTimeInterval seconds) {
    [[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: seconds]];
}

static NSWindow *makeWindow(NSRect rect, NSWindowStyleMask style) {
    return [[NSWindow alloc] initWithContentRect: rect
                                       styleMask: style
                                         backing: NSBackingStoreBuffered
                                           defer: NO];
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSWindow *parent = makeWindow(NSMakeRect(100, 300, 400, 300),
                                      NSWindowStyleMaskTitled | NSWindowStyleMaskClosable);
        Delegate *delegate = [[Delegate alloc] init];
        [parent setDelegate: delegate];
        [parent makeKeyAndOrderFront: nil];
        spin(0.3);

        for (int critical = 0; critical < 2; critical++) {
            NSWindow *sheet = makeWindow(NSMakeRect(0, 0, 200, 100), NSWindowStyleMaskTitled);
            __block NSModalResponse response = -1;
            int beganBefore = delegate->began, endedBefore = delegate->ended;
            void (^done)(NSModalResponse) = ^(NSModalResponse code) {
                response = code;
            };

            expect([[parent sheets] count] == 0, "no sheet before beginning");
            if (critical)
                [parent beginCriticalSheet: sheet completionHandler: done];
            else
                [parent beginSheet: sheet completionHandler: done];
            spin(0.5);
            expect(delegate->began == beganBefore + 1, "delegate told the sheet began");
            expect([[parent sheets] count] == 1 && [parent sheets][0] == sheet &&
                           [parent attachedSheet] == sheet,
                   "the attached sheet is listed");

            [parent endSheet: sheet returnCode: NSModalResponseOK];
            spin(1.0);
            expect(response == NSModalResponseOK, "completion handler gets the return code");
            expect(delegate->ended == endedBefore + 1, "delegate told the sheet ended");
            expect([[parent sheets] count] == 0, "no sheet after ending");
            [sheet close];
        }
        [parent close];
    }

    if (failures == 0)
        printf("PASS appkit-window-sheets\n");
    return failures != 0;
}
