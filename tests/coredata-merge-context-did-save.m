// SPDX-License-Identifier: GPL-3.0-or-later
//
// NSManagedObjectContext mergeChangesFromContextDidSaveNotification:, from the documented
// contract (the public NSManagedObjectContext.h and the page
// https://developer.apple.com/documentation/coredata/nsmanagedobjectcontext/mergechanges(fromcontextdidsave:) ):
// the merge refreshes objects updated in the other context, faults in newly inserted objects and
// deletes the objects the other context deleted.
// The rest is what macOS 10.14.4 and 26.7.3 do (they agree; mac-probes mrg1.m of batch11b): a deleted
// object stays registered and becomes a pending delete of the receiver (it is in deletedObjects until
// the next save), also when the receiver has changed it; an object the receiver deleted stays deleted
// and takes the values of a remote update; the receiver's own change to an updated object stays on top
// of the refreshed values; the merge is reported through one change notification (inserted, refreshed,
// deleted) before it returns; a notification without user info changes nothing.
// Prints PASS when everything holds; the exit code is the number of failed checks.

#import <Foundation/Foundation.h>
#import <CoreData/CoreData.h>
#include <stdio.h>

static int failures;
/* the 32-bit build has no ARC: a notification kept by a block has to be retained there */
#if __has_feature(objc_arc)
#define KEEP(x) (x)
#else
#define KEEP(x) [(x) retain]
#endif
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
                                                                    usingBlock:^(NSNotification *n) { saved = KEEP(n); }];
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
                                                                 usingBlock:^(NSNotification *n) { changes = KEEP([n userInfo]); }];
        [receiver processPendingChanges];
        changes = nil;
        [receiver mergeChangesFromContextDidSaveNotification:saved];
        [[NSNotificationCenter defaultCenter] removeObserver:observer];

        /* the updated object is refreshed, the inserted one is faulted in, the deleted one is a pending delete */
        CHECK([[r1 valueForKey:@"text"] isEqual:@"uno"]);
        NSManagedObject *r4 = [receiver objectRegisteredForID:id4];
        CHECK(r4 != nil && [[r4 valueForKey:@"text"] isEqual:@"four"]);
        CHECK([receiver objectRegisteredForID:id3] == r3);
        CHECK([[receiver deletedObjects] containsObject:r3]);
        CHECK([r3 isDeleted]);

        /* the receiver's own change stays on top of the refreshed value */
        CHECK([[r2 valueForKey:@"text"] isEqual:@"local"]);
        CHECK([[r2 changedValues] objectForKey:@"text"] != nil);
        /* the refreshed and the faulted-in objects are no changes of the receiver's own */
        CHECK(![[receiver updatedObjects] containsObject:r1]);
        CHECK(![[receiver insertedObjects] containsObject:r4]);

        /* the receiver reports what was merged through its change notification */
        CHECK([[changes objectForKey:NSRefreshedObjectsKey] containsObject:r1]);
        CHECK([[changes objectForKey:NSInsertedObjectsKey] containsObject:r4]);
        CHECK([[changes objectForKey:NSDeletedObjectsKey] containsObject:r3]);

        /* a notification without user info changes nothing */
        NSUInteger registered = [[receiver registeredObjects] count];
        [receiver mergeChangesFromContextDidSaveNotification:
            [NSNotification notificationWithName:NSManagedObjectContextDidSaveNotification object:source]];
        CHECK([[receiver registeredObjects] count] == registered);

        /* the receiver may save after the merge: the deleted object goes */
        CHECK([receiver save:NULL]);
        CHECK([receiver objectRegisteredForID:id3] == nil);
        CHECK(![receiver hasChanges]);

        /* a local change does not keep an object that the other context deleted; a local delete stays when the
           other context only updates the object (and the object takes the updated values) */
        NSManagedObject *m1 = newNote(source, @"m1"), *m2 = newNote(source, @"m2");
        CHECK([source save:NULL]);
        NSManagedObject *q1 = [receiver objectWithID:[m1 objectID]], *q2 = [receiver objectWithID:[m2 objectID]];
        CHECK([[q1 valueForKey:@"text"] isEqual:@"m1"] && [[q2 valueForKey:@"text"] isEqual:@"m2"]);
        [q1 setValue:@"local-m1" forKey:@"text"];
        [receiver deleteObject:q2];
        observer = [[NSNotificationCenter defaultCenter] addObserverForName:NSManagedObjectContextDidSaveNotification
                                                                     object:source queue:nil
                                                                 usingBlock:^(NSNotification *n) { saved = KEEP(n); }];
        [source deleteObject:m1];
        [m2 setValue:@"remote-m2" forKey:@"text"];
        CHECK([source save:NULL]);
        [[NSNotificationCenter defaultCenter] removeObserver:observer];
        [receiver mergeChangesFromContextDidSaveNotification:saved];
        CHECK([[receiver deletedObjects] containsObject:q1]);
        CHECK([[q1 valueForKey:@"text"] isEqual:@"local-m1"]);
        CHECK([[receiver deletedObjects] containsObject:q2]);
        CHECK([[q2 valueForKey:@"text"] isEqual:@"remote-m2"]);
        CHECK([receiver save:NULL]);
        CHECK([receiver objectRegisteredForID:[m1 objectID]] == nil);
    }
    if (failures == 0)
        printf("PASS\n");
    return failures;
}
