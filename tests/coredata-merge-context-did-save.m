// SPDX-License-Identifier: GPL-3.0-or-later
//
// NSManagedObjectContext mergeChangesFromContextDidSaveNotification:, from the documented
// contract (the public NSManagedObjectContext.h and the page
// https://developer.apple.com/documentation/coredata/nsmanagedobjectcontext/mergechanges(fromcontextdidsave:) ):
// the merge refreshes objects updated in the other context, faults in newly inserted objects and
// removes deleted ones (GUESS, a departure from the page: directly, not through deleteObject:).
// Lines marked GUESS pin what the pages leave open (they are not observed on macOS): that the receiver's own unsaved change to an object stays on top of the refreshed
// values, that a merge leaves the receiver with no changes of its own, and that the merged
// objects are reported through the receiver's change notification (inserted, refreshed, deleted).
// Prints PASS when everything holds; the exit code is the number of failed checks.

#import <Foundation/Foundation.h>
#import <CoreData/CoreData.h>
#include <stdio.h>

static int failures;
#define CHECK(...) do { if (!(__VA_ARGS__)) { printf("FAIL line %d: %s\n", __LINE__, #__VA_ARGS__); failures++; } } while (0)

static NSManagedObjectModel *makeModel(void) {
    NSEntityDescription *note = [[NSEntityDescription alloc] init];
    note.name = @"Note";
    note.managedObjectClassName = @"NSManagedObject";
    NSAttributeDescription *text = [[NSAttributeDescription alloc] init];
    text.name = @"text";
    text.attributeType = NSStringAttributeType;
    text.optional = YES;
    note.properties = @[text];
    NSManagedObjectModel *model = [[NSManagedObjectModel alloc] init];
    model.entities = @[note];
    return model;
}

static NSManagedObject *newNote(NSManagedObjectContext *context, NSString *text) {
    NSManagedObject *note = [NSEntityDescription insertNewObjectForEntityForName:@"Note" inManagedObjectContext:context];
    [note setValue:text forKey:@"text"];
    return note;
}

int main(void) {
    @autoreleasepool {
        NSPersistentStoreCoordinator *psc =
            [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:makeModel()];
        CHECK([psc addPersistentStoreWithType:NSInMemoryStoreType configuration:nil URL:nil options:nil error:NULL] != nil);
        NSManagedObjectContext *source = [[NSManagedObjectContext alloc] init];
        source.persistentStoreCoordinator = psc;
        NSManagedObjectContext *receiver = [[NSManagedObjectContext alloc] init];
        receiver.persistentStoreCoordinator = psc;

        NSManagedObject *n1 = newNote(source, @"one"), *n2 = newNote(source, @"two"), *n3 = newNote(source, @"three");
        CHECK([source save:NULL]);
        NSManagedObjectID *id1 = [n1 objectID], *id2 = [n2 objectID], *id3 = [n3 objectID];

        /* the receiver knows the three notes; it has its own unsaved change to the second */
        NSManagedObject *r1 = [receiver objectWithID:id1], *r2 = [receiver objectWithID:id2], *r3 = [receiver objectWithID:id3];
        CHECK([[r1 valueForKey:@"text"] isEqual:@"one"]);
        [r2 setValue:@"local" forKey:@"text"];

        /* the source updates the first and second, inserts a fourth and deletes the third */
        __block NSNotification *saved = nil;
        id observer = [[NSNotificationCenter defaultCenter] addObserverForName:NSManagedObjectContextDidSaveNotification
                                                                        object:source queue:nil
                                                                    usingBlock:^(NSNotification *n) { saved = n; }];
        [n1 setValue:@"uno" forKey:@"text"];
        [n2 setValue:@"dos" forKey:@"text"];
        NSManagedObject *n4 = newNote(source, @"four");
        [source deleteObject:n3];
        CHECK([source save:NULL]);
        [[NSNotificationCenter defaultCenter] removeObserver:observer];
        CHECK(saved != nil);
        NSManagedObjectID *id4 = [n4 objectID];
        CHECK([receiver objectRegisteredForID:id4] == nil);

        __block NSDictionary *changes = nil;
        observer = [[NSNotificationCenter defaultCenter] addObserverForName:NSManagedObjectContextObjectsDidChangeNotification
                                                                     object:receiver queue:nil
                                                                 usingBlock:^(NSNotification *n) { changes = [n userInfo]; }];
        [receiver processPendingChanges];
        changes = nil;
        [receiver mergeChangesFromContextDidSaveNotification:saved];
        [[NSNotificationCenter defaultCenter] removeObserver:observer];

        /* the updated object is refreshed, the inserted one is faulted in, the deleted one is gone */
        CHECK([[r1 valueForKey:@"text"] isEqual:@"uno"]);
        NSManagedObject *r4 = [receiver objectRegisteredForID:id4];
        CHECK(r4 != nil && [[r4 valueForKey:@"text"] isEqual:@"four"]);
        CHECK([receiver objectRegisteredForID:id3] == nil);
        CHECK(![[receiver registeredObjects] containsObject:r3]);

        /* GUESS: the receiver's own change stays on top of the refreshed value */
        CHECK([[r2 valueForKey:@"text"] isEqual:@"local"]);
        CHECK([[r2 changedValues] objectForKey:@"text"] != nil);
        /* GUESS: the merge itself leaves no change of the receiver's own on the merged objects */
        CHECK(![[receiver updatedObjects] containsObject:r1]);
        CHECK(![[receiver insertedObjects] containsObject:r4]);
        CHECK(![[receiver deletedObjects] containsObject:r3]);

        /* GUESS: the receiver reports what was merged through its change notification */
        CHECK([[changes objectForKey:NSRefreshedObjectsKey] containsObject:r1]);
        CHECK([[changes objectForKey:NSInsertedObjectsKey] containsObject:r4]);
        CHECK([[changes objectForKey:NSDeletedObjectsKey] containsObject:r3]);

        /* a notification without user info changes nothing */
        NSUInteger registered = [[receiver registeredObjects] count];
        [receiver mergeChangesFromContextDidSaveNotification:
            [NSNotification notificationWithName:NSManagedObjectContextDidSaveNotification object:source]];
        CHECK([[receiver registeredObjects] count] == registered);

        /* GUESS: the sets may hold object IDs instead of objects (what the automatic merge passes) */
        [n1 setValue:@"ein" forKey:@"text"];
        CHECK([source save:NULL]);
        NSDictionary *idInfo = @{NSUpdatedObjectsKey: [NSSet setWithObject:id1]};
        [receiver mergeChangesFromContextDidSaveNotification:
            [NSNotification notificationWithName:NSManagedObjectContextDidSaveNotification object:source userInfo:idInfo]];
        CHECK([[r1 valueForKey:@"text"] isEqual:@"ein"]);
    }
    if (failures == 0)
        printf("PASS\n");
    return failures;
}
