// Copyright (C) 2026 Lubos Dolezel
//
// Key-value observing of NSArrayController and NSObjectController:
//  - observing the controllers' own keys does not change the controller's
//    class: the controllers post those changes themselves, and
//    +automaticallyNotifiesObserversForKey: is NO for them (YES for others,
//    such as "editable" or "contentArray");
//  - each setter posts one notification when it changes the value and none
//    when the value stays the same (setContent: on an array controller always
//    posts, as it always takes a new array);
//  - the keys that follow the selection (selection, selectionIndex,
//    selectedObjects, canSelectNext) post once per selection change;
//  - new sort descriptors rearrange the objects even when the controller does
//    not rearrange automatically.
// Black-box observation: the program passes unchanged on macOS 10.14.4 (i386)
// and 26.7.3 (x86_64).
#import <AppKit/AppKit.h>
#include <objc/runtime.h>
#include <stdio.h>

static int failures;
#define CHECK(...) do { if (!(__VA_ARGS__)) { printf("FAIL %d: %s\n", __LINE__, #__VA_ARGS__); failures++; } } while (0)

@interface Counter : NSObject {
@public
    int count;
}
@end

@implementation Counter
- (void) observeValueForKeyPath: (NSString *) keyPath ofObject: (id) object change: (NSDictionary *) change context: (void *) context {
    count++;
}
@end

static id newController(BOOL array) {
    if (array)
        return [[NSArrayController alloc] initWithContent: [NSMutableArray arrayWithObjects: @"a", @"b", @"c", nil]];
    return [[NSObjectController alloc] initWithContent: @"x"];
}

// Observes key, runs change and then same, and checks the notification counts
// and that the class stayed the same
static void expectNotifications(BOOL array, NSString *key, int expectChange, int expectSame,
                                void (^change)(id controller), void (^same)(id controller)) {
    id controller = newController(array);
    Class before = object_getClass(controller);
    Counter *counter = [[Counter alloc] init];

    [controller addObserver: counter forKeyPath: key options: 0 context: NULL];
    BOOL swizzled = object_getClass(controller) != before;
    change(controller);
    int changed = counter->count;
    counter->count = 0;
    if (same)
        same(controller);
    int unchanged = counter->count;
    [controller removeObserver: counter forKeyPath: key];

    const char *name = array ? "NSArrayController" : "NSObjectController";
    if (changed != expectChange || unchanged != expectSame) {
        printf("FAIL: %s %s: %d notifications for a change (expected %d), %d for the same value (expected %d)\n",
               name, [key UTF8String], changed, expectChange, unchanged, expectSame);
        failures++;
    }
    BOOL automatic = [[controller class] automaticallyNotifiesObserversForKey: key];
    if (swizzled != automatic) {
        printf("FAIL: %s %s: class changed %d, automatic notification %d\n", name, [key UTF8String], swizzled, automatic);
        failures++;
    }
    [counter release];
    [controller release];
}

int main(void) {
    setvbuf(stdout, NULL, _IONBF, 0);
    @autoreleasepool {
        NSSortDescriptor *descending = [NSSortDescriptor sortDescriptorWithKey: @"self" ascending: NO];

        // Which keys post automatically
        const char *manualArray[] = { "selectionIndexes", "selectionIndex", "selectedObjects", "selection", "content",
                                      "arrangedObjects", "sortDescriptors", "filterPredicate", "avoidsEmptySelection",
                                      "preservesSelection", "selectsInsertedObjects", "automaticallyRearrangesObjects",
                                      "clearsFilterPredicateOnInsertion", "alwaysUsesMultipleValuesMarker",
                                      "objectClass", "canAdd", "canRemove", "canSelectNext" };
        for (size_t i = 0; i < sizeof(manualArray) / sizeof(manualArray[0]); i++) {
            NSString *key = [NSString stringWithUTF8String: manualArray[i]];
            if ([NSArrayController automaticallyNotifiesObserversForKey: key]) {
                printf("FAIL: NSArrayController notifies %s automatically\n", manualArray[i]);
                failures++;
            }
        }
        const char *manualObject[] = { "selectedObjects", "selection", "content", "objectClass", "canAdd", "canRemove" };
        for (size_t i = 0; i < sizeof(manualObject) / sizeof(manualObject[0]); i++) {
            NSString *key = [NSString stringWithUTF8String: manualObject[i]];
            if ([NSObjectController automaticallyNotifiesObserversForKey: key]) {
                printf("FAIL: NSObjectController notifies %s automatically\n", manualObject[i]);
                failures++;
            }
        }
        CHECK([NSArrayController automaticallyNotifiesObserversForKey: @"editable"]);
        CHECK([NSArrayController automaticallyNotifiesObserversForKey: @"contentArray"]);
        CHECK([NSObjectController automaticallyNotifiesObserversForKey: @"editable"]);
        CHECK([NSObjectController automaticallyNotifiesObserversForKey: @"selectionIndexes"]);

        // NSArrayController
        expectNotifications(YES, @"selectionIndexes", 1, 0,
            ^(id c) { CHECK([(NSArrayController *) c setSelectionIndexes: [NSIndexSet indexSetWithIndex: 2]]); },
            ^(id c) { [c setSelectionIndexes: [NSIndexSet indexSetWithIndex: 2]]; });
        expectNotifications(YES, @"selectionIndex", 1, 0,
            ^(id c) { [c setSelectionIndex: 2]; }, ^(id c) { [c setSelectionIndex: 2]; });
        expectNotifications(YES, @"selectedObjects", 1, 0,
            ^(id c) { [c setSelectedObjects: [NSArray arrayWithObject: @"b"]]; },
            ^(id c) { [c setSelectedObjects: [NSArray arrayWithObject: @"b"]]; });
        expectNotifications(YES, @"selection", 1, 0, ^(id c) { [c setSelectionIndex: 1]; }, ^(id c) { [c setSelectionIndex: 1]; });
        expectNotifications(YES, @"canSelectNext", 1, 0, ^(id c) { [c setSelectionIndex: 2]; }, ^(id c) { [c setSelectionIndex: 2]; });
        expectNotifications(YES, @"content", 1, 1,
            ^(id c) { [c setContent: [NSMutableArray arrayWithObject: @"q"]]; }, ^(id c) { [c setContent: [c content]]; });
        expectNotifications(YES, @"objectClass", 1, 0,
            ^(id c) { [c setObjectClass: [NSString class]]; }, ^(id c) { [c setObjectClass: [NSString class]]; });
        expectNotifications(YES, @"editable", 1, 1, ^(id c) { [c setEditable: NO]; }, ^(id c) { [c setEditable: NO]; });
        expectNotifications(YES, @"sortDescriptors", 1, 0,
            ^(id c) { [c setSortDescriptors: [NSArray arrayWithObject: descending]]; },
            ^(id c) { [c setSortDescriptors: [c sortDescriptors]]; });
        expectNotifications(YES, @"arrangedObjects", 1, 0,
            ^(id c) { [c setSortDescriptors: [NSArray arrayWithObject: descending]]; },
            ^(id c) { [c setSortDescriptors: [c sortDescriptors]]; });
        expectNotifications(YES, @"filterPredicate", 1, 0,
            ^(id c) { [c setFilterPredicate: [NSPredicate predicateWithFormat: @"self != 'a'"]]; },
            ^(id c) { [c setFilterPredicate: [c filterPredicate]]; });
        expectNotifications(YES, @"avoidsEmptySelection", 1, 0,
            ^(id c) { [c setAvoidsEmptySelection: NO]; }, ^(id c) { [c setAvoidsEmptySelection: NO]; });
        expectNotifications(YES, @"preservesSelection", 1, 0,
            ^(id c) { [c setPreservesSelection: NO]; }, ^(id c) { [c setPreservesSelection: NO]; });
        expectNotifications(YES, @"selectsInsertedObjects", 1, 0,
            ^(id c) { [c setSelectsInsertedObjects: NO]; }, ^(id c) { [c setSelectsInsertedObjects: NO]; });
        expectNotifications(YES, @"automaticallyRearrangesObjects", 1, 0,
            ^(id c) { [c setAutomaticallyRearrangesObjects: YES]; }, ^(id c) { [c setAutomaticallyRearrangesObjects: YES]; });
        expectNotifications(YES, @"clearsFilterPredicateOnInsertion", 1, 0,
            ^(id c) { [c setClearsFilterPredicateOnInsertion: NO]; }, ^(id c) { [c setClearsFilterPredicateOnInsertion: NO]; });
        expectNotifications(YES, @"alwaysUsesMultipleValuesMarker", 1, 0,
            ^(id c) { [c setAlwaysUsesMultipleValuesMarker: YES]; }, ^(id c) { [c setAlwaysUsesMultipleValuesMarker: YES]; });

        // NSObjectController
        expectNotifications(NO, @"content", 1, 0, ^(id c) { [c setContent: @"y"]; }, ^(id c) { [c setContent: [c content]]; });
        expectNotifications(NO, @"objectClass", 1, 0,
            ^(id c) { [c setObjectClass: [NSString class]]; }, ^(id c) { [c setObjectClass: [NSString class]]; });
        expectNotifications(NO, @"editable", 1, 1, ^(id c) { [c setEditable: NO]; }, ^(id c) { [c setEditable: NO]; });

        // Sorting rearranges without automatic rearranging
        NSArrayController *controller = newController(YES);
        CHECK(![controller automaticallyRearrangesObjects]);
        [controller setSortDescriptors: [NSArray arrayWithObject: descending]];
        CHECK([[controller arrangedObjects] isEqualToArray: [NSArray arrayWithObjects: @"c", @"b", @"a", nil]]);
        [controller release];
    }

    if (failures)
        printf("FAIL: %d check(s) failed\n", failures);
    else
        printf("PASS\n");
    return failures ? 1 : 0;
}
