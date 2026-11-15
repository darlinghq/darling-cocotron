/*
 Copyright (C) 2026 Lubos Dolezel

 Licensed under the MIT license, the same as the rest of this project.
*/
// NSModalResponse is a typed integer whose constants (OK, cancel, stop, abort, continue and the alert button
// returns) are the public values; the older NSRun*Response and NSOKButton names equal them.
#import <AppKit/AppKit.h>
#include <stdio.h>

static int failures;
static void expect(BOOL condition, const char *label)
{
    printf("%s %s\n", condition ? "PASS" : "FAIL", label);
    failures += !condition;
}

int main(void)
{
    expect(sizeof(NSModalResponse) == sizeof(NSInteger), "NSModalResponse is NSInteger sized");
    expect(NSModalResponseOK == 1 && NSModalResponseCancel == 0, "OK and cancel values");
    expect(NSModalResponseStop == -1000 && NSModalResponseAbort == -1001 && NSModalResponseContinue == -1002,
           "stop, abort and continue values");
    expect(NSAlertFirstButtonReturn == 1000 && NSAlertSecondButtonReturn == 1001 && NSAlertThirdButtonReturn == 1002,
           "alert button return values");
    expect(NSRunStoppedResponse == NSModalResponseStop && NSRunAbortedResponse == NSModalResponseAbort &&
                   NSRunContinuesResponse == NSModalResponseContinue,
           "old run response names equal the new ones");
    expect(NSOKButton == NSModalResponseOK && NSCancelButton == NSModalResponseCancel, "NSOKButton and NSCancelButton");
    expect(NSFileHandlingPanelOKButton == NSModalResponseOK, "NSFileHandlingPanelOKButton");
    NSModalResponse response = NSModalResponseOK;
    switch (response) {
        case NSModalResponseOK:
            expect(YES, "NSModalResponse constants are usable as case labels");
            break;
        default:
            expect(NO, "NSModalResponse constants are usable as case labels");
    }
    printf(failures ? "FAILED\n" : "ALL PASSED\n");
    return failures != 0;
}
