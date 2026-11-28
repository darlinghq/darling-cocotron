// Copyright (C) 2026 Lubos Dolezel
//
// The public accessibility posting entry points must reach registered internal handlers with their element,
// notification name and user info unchanged. The private focus-change entry point posts the focused-element
// notification with no element. This is a general delivery contract, not a client-specific path.
// Build: clang -framework AppKit <private include dirs> appkit-accessibility-notification-delivery.m
#import <AppKit/AppKit.h>
#import <AppKit/NSAccessibility+Private.h>
#include <stdio.h>

static int failures;
static NSMutableArray *events;

static id Box(id value)
{
    return value != nil ? value : (id) [NSNull null];
}

static void RecordNotification(id element, NSString *notification, NSDictionary *userInfo, void *context)
{
    if (context != NULL)
        failures++;
    [events addObject: [NSDictionary dictionaryWithObjectsAndKeys:
            Box(element), @"element",
            Box(notification), @"notification",
            Box(userInfo), @"userInfo",
            nil]];
}

static void CheckEvent(NSUInteger index, id element, NSString *notification, NSDictionary *userInfo)
{
    if (index >= [events count]) {
        fprintf(stderr, "FAIL: missing notification %lu\n", (unsigned long) index);
        failures++;
        return;
    }
    NSDictionary *event = [events objectAtIndex: index];
    if (![[event objectForKey: @"element"] isEqual: Box(element)]
        || ![[event objectForKey: @"notification"] isEqual: Box(notification)]
        || ![[event objectForKey: @"userInfo"] isEqual: Box(userInfo)]) {
        fprintf(stderr, "FAIL: wrong notification %lu: %s\n", (unsigned long) index,
                [[event description] UTF8String]);
        failures++;
    }
}

int main(void)
{
    @autoreleasepool {
        events = [[NSMutableArray alloc] init];
        NSAccessibilityRegisterNotificationHandler(RecordNotification, NULL);

        NSObject *element = [[NSObject alloc] init];
        NSAccessibilityPostNotification(element, NSAccessibilityValueChangedNotification);
        CheckEvent(0, element, NSAccessibilityValueChangedNotification, nil);

        NSDictionary *info = [NSDictionary dictionaryWithObject: @"hello"
                                                         forKey: NSAccessibilityAnnouncementKey];
        NSAccessibilityPostNotificationWithUserInfo(element,
                                                    NSAccessibilityAnnouncementRequestedNotification,
                                                    info);
        CheckEvent(1, element, NSAccessibilityAnnouncementRequestedNotification, info);

        NSAccessibilityHandleFocusChanged();
        CheckEvent(2, nil, NSAccessibilityFocusedUIElementChangedNotification, nil);

        if ([events count] != 3) {
            fprintf(stderr, "FAIL: unexpected extra notifications (%lu)\n", (unsigned long) [events count]);
            failures++;
        }

        NSAccessibilityUnregisterNotificationHandler(RecordNotification, NULL);
        NSAccessibilityPostNotification(element, NSAccessibilityValueChangedNotification);
        if ([events count] != 3) {
            fprintf(stderr, "FAIL: unregistered handler still received a notification\n");
            failures++;
        }
    }

    if (failures == 0)
        printf("PASS: accessibility notification delivery\n");
    return failures ? 1 : 0;
}
