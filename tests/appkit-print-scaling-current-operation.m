/* Copyright (C) 2026 Lubos Dolezel */
/* NSPrintInfo.scalingFactor is the NSPrintScalingFactor entry of the
 * dictionary, 1 when the dictionary has none; NSPrintOperation.currentOperation
 * belongs to the thread that set it (observed on macOS 26.7.3). */
#import <AppKit/AppKit.h>
#include <stdio.h>
#include <unistd.h>

static int failures;
#define CHECK(c) do { if (!(c)) { fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #c); failures++; } } while (0)

int main(void)
{
    @autoreleasepool {
        NSPrintInfo *empty = [[[NSPrintInfo alloc] initWithDictionary: @{}] autorelease];
        CHECK([empty scalingFactor] == 1);
        CHECK([[[empty dictionary] objectForKey: NSPrintScalingFactor] doubleValue] == 1);

        NSPrintInfo *info = [[[NSPrintInfo alloc] init] autorelease];
        CHECK([info scalingFactor] == 1);
        [info setScalingFactor: 0.5];
        CHECK([info scalingFactor] == 0.5);
        CHECK([[[info dictionary] objectForKey: NSPrintScalingFactor] doubleValue] == 0.5);
        [[info dictionary] setObject: @2 forKey: NSPrintScalingFactor];
        CHECK([info scalingFactor] == 2);

        NSView *view = [[[NSView alloc] initWithFrame: NSMakeRect(0, 0, 10, 10)] autorelease];
        NSPrintOperation *operation = [NSPrintOperation printOperationWithView: view];
        CHECK([NSPrintOperation currentOperation] == nil);
        [NSPrintOperation setCurrentOperation: operation];
        CHECK([NSPrintOperation currentOperation] == operation);

        __block int seen = -1;
        NSThread *thread = [[[NSThread alloc] initWithBlock: ^{
            seen = [NSPrintOperation currentOperation] == operation;
        }] autorelease];
        [thread start];
        for (int i = 0; seen < 0 && i < 5000; i++)
            usleep(1000);
        CHECK(seen == 0);

        [NSPrintOperation setCurrentOperation: nil];
        CHECK([NSPrintOperation currentOperation] == nil);
    }
    if (failures == 0)
        printf("PASS\n");
    return failures != 0;
}
