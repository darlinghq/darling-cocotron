// Copyright (C) 2026 Lubos Dolezel
//
// NSSharingServicePicker and its delegate. The contract is the NSSharingServicePicker and
// NSSharingServicePickerDelegate references
// (https://developer.apple.com/documentation/appkit/nssharingservicepicker,
// https://developer.apple.com/documentation/appkit/nssharingservicepickerdelegate):
//  - the delegate can replace the proposed services before the picker appears;
//  - when a service is chosen the picker tells the delegate, and the service receives the items
//    after that call returns;
//  - the delegate can give the chosen service its own delegate;
// Darling has no system services, so the proposed list is empty and the services here are
// custom ones made with a handler. The menu of services is read through -menu, which is not in
// the reference. Showing the picker runs a menu and is not tested.
// Written from the documentation; not yet run in a guest.
// Build: clang -framework AppKit appkit-sharing-service-picker.m (no ARC)
#import <AppKit/AppKit.h>
#include <stdio.h>

static int failures;
#define CHECK(c) do { if (!(c)) { fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #c); failures++; } } while (0)

static NSMutableArray *log_;

@interface ServiceDelegate : NSObject <NSSharingServiceDelegate>
@end
@implementation ServiceDelegate
@end

@interface PickerDelegate : NSObject <NSSharingServicePickerDelegate> {
@public
    NSSharingService *custom;
    ServiceDelegate *serviceDelegate;
    NSArray *seenProposed;
    NSArray *seenItems;
}
@end
@implementation PickerDelegate
- (NSArray *) sharingServicePicker: (NSSharingServicePicker *) picker sharingServicesForItems: (NSArray *) items
           proposedSharingServices: (NSArray *) proposed {
    seenItems = items;
    seenProposed = proposed;
    NSMutableArray *services = [NSMutableArray arrayWithArray: proposed];
    [services addObject: custom];
    return services;
}
- (id <NSSharingServiceDelegate>) sharingServicePicker: (NSSharingServicePicker *) picker
                             delegateForSharingService: (NSSharingService *) service {
    [log_ addObject: @"delegateFor"];
    return serviceDelegate;
}
- (void) sharingServicePicker: (NSSharingServicePicker *) picker didChooseSharingService: (NSSharingService *) service {
    [log_ addObject: service == custom ? @"didChoose" : @"didChoose-other"];
}
@end

static void test_delegate_services_and_choice(void) {
    PickerDelegate *delegate = [[PickerDelegate new] autorelease];
    delegate->serviceDelegate = [[ServiceDelegate new] autorelease];
    delegate->custom = [[[NSSharingService alloc] initWithTitle: @"Custom" image: nil alternateImage: nil
                                                         handler: ^{ [log_ addObject: @"handler"]; }] autorelease];
    NSArray *items = [NSArray arrayWithObject: @"item"];
    NSSharingServicePicker *picker = [[[NSSharingServicePicker alloc] initWithItems: items] autorelease];
    [picker setDelegate: delegate];

    NSMenu *menu = [picker menu];
    CHECK([delegate->seenProposed isKindOfClass: [NSArray class]]);
    CHECK([delegate->seenItems isEqual: items]);
    CHECK([menu numberOfItems] == 1);
    CHECK([[[menu itemAtIndex: 0] title] isEqualToString: @"Custom"]);

    log_ = [NSMutableArray array];
    [menu performActionForItemAtIndex: 0];
    CHECK([[delegate->custom delegate] isEqual: delegate->serviceDelegate]);
    NSArray *expected = [NSArray arrayWithObjects: @"delegateFor", @"didChoose", @"handler", nil];
    CHECK([log_ isEqual: expected]);
}

static void test_no_delegate(void) {
    NSSharingServicePicker *picker = [[[NSSharingServicePicker alloc] initWithItems: [NSArray arrayWithObject: @"x"]] autorelease];

    CHECK([[picker menu] numberOfItems] == 0);
    [picker close];
}

// A delegate may release the picker from its callback; the service must still get the items.
@interface ReleasingDelegate : NSObject <NSSharingServicePickerDelegate> {
@public
    NSSharingServicePicker *picker;
}
@end
@implementation ReleasingDelegate
- (NSArray *) sharingServicePicker: (NSSharingServicePicker *) p sharingServicesForItems: (NSArray *) items
           proposedSharingServices: (NSArray *) proposed {
    return [NSArray arrayWithObject: [[[NSSharingService alloc] initWithTitle: @"Once" image: nil alternateImage: nil
                                                                        handler: ^{ [log_ addObject: @"handler"]; }] autorelease]];
}
- (void) sharingServicePicker: (NSSharingServicePicker *) p didChooseSharingService: (NSSharingService *) service {
    [picker release];
    picker = nil;
}
@end

static void test_picker_released_by_the_delegate(void) {
    ReleasingDelegate *delegate = [[ReleasingDelegate new] autorelease];
    delegate->picker = [[NSSharingServicePicker alloc] initWithItems: [NSArray arrayWithObject: @"x"]];
    [delegate->picker setDelegate: delegate];
    NSMenu *menu = [delegate->picker menu];
    log_ = [NSMutableArray array];
    [menu performActionForItemAtIndex: 0];
    CHECK(delegate->picker == nil);
    CHECK([log_ isEqual: [NSArray arrayWithObject: @"handler"]]);
}

#define RUN(t) do { @try { t; } @catch (id e) { fprintf(stderr, "FAIL: %s raised %s\n", #t, [[e description] UTF8String]); failures++; } } while (0)

int main(void) {
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    [NSApplication sharedApplication];
    RUN(test_delegate_services_and_choice());
    RUN(test_no_delegate());
    RUN(test_picker_released_by_the_delegate());
    if (failures == 0)
        printf("PASS appkit-sharing-service-picker\n");
    [pool release];
    return failures != 0;
}
