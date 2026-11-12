/*
 Copyright (C) 2026 Lubos Dolezel

 Licensed under the MIT license, the same as the rest of this project.
*/
// NSSharingService created with a handler runs the handler when performed;
// NSTitlebarAccessoryViewController and NSSegmentedControl keep their
// properties. No window is shown.
#import <AppKit/AppKit.h>
#include <stdio.h>

static int failures;

static void expect(BOOL condition, const char *what) {
    if (!condition) {
        fprintf(stderr, "FAIL: %s\n", what);
        failures++;
    }
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        __block int performed = 0;
        NSSharingService *service = [[NSSharingService alloc]
                initWithTitle: @"Custom" image: nil alternateImage: nil
                      handler: ^{ performed++; }];
        expect([[service title] isEqualToString: @"Custom"], "the title is kept");
        expect([service canPerformWithItems: @[]], "a service with a handler can perform");
        [service performWithItems: @[ @"item" ]];
        expect(performed == 1, "performWithItems: runs the handler");
        [service release];

        NSSharingService *none = [NSSharingService sharingServiceNamed: @"no.such.service"];
        expect(none == nil, "an unknown service name gives nil");
        expect([[NSSharingService sharingServicesForItems: @[ @"x" ]] isKindOfClass: [NSArray class]],
               "sharingServicesForItems: gives an array");

        NSTitlebarAccessoryViewController *accessory = [[NSTitlebarAccessoryViewController alloc] init];
        expect([accessory automaticallyAdjustsSize], "automaticallyAdjustsSize defaults to YES");
        expect(![accessory isHidden], "an accessory is visible by default");
        expect([accessory fullScreenMinHeight] == 0, "fullScreenMinHeight defaults to 0");
        [accessory setHidden: YES];
        [accessory setFullScreenMinHeight: 12];
        [accessory setAutomaticallyAdjustsSize: NO];
        expect([accessory isHidden] && [accessory fullScreenMinHeight] == 12 &&
               ![accessory automaticallyAdjustsSize], "the accessory properties are kept");
        [accessory release];

        NSSegmentedControl *segments = [[NSSegmentedControl alloc] initWithFrame: NSMakeRect(0, 0, 100, 24)];
        expect([segments trackingMode] == NSSegmentSwitchTrackingSelectOne, "the default tracking mode");
        [segments setTrackingMode: NSSegmentSwitchTrackingMomentary];
        expect([segments trackingMode] == NSSegmentSwitchTrackingMomentary, "setTrackingMode: is kept");
        [segments release];
    }
    printf("sharing service and small controls: %s\n", failures ? "FAIL" : "PASS");
    return failures ? 1 : 0;
}
