// SPDX-License-Identifier: GPL-3.0-or-later
//
// NSManagedObjectContext refreshObject:mergeChanges:, from the documented contract:
// https://developer.apple.com/documentation/coredata/nsmanagedobjectcontext/refresh(_:mergechanges:)
// Documented: with NO the pending changes are discarded and the values come from the store again;
// with YES the values are reloaded and the local changes applied over them (never a conflict);
// with YES transient properties are not affected, with NO they are disposed.
// The rest is what macOS 10.14.4 and 26.7.3 do (they agree; mac-probes ref1.m and ref2.m of batch11b):
// NO also drops a pending delete; the object is reported as refreshed in the change notification in
// both cases; hasChanges is not recomputed by a refresh; an object inserted and not yet saved is left
// alone with YES and loses its values and its insertion with NO (QUIRK); an object of another context
// and nil are ignored (macOS 26.7.3 raises for an object of another context, 10.14.4 does not).
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
    NSAttributeDescription *scratch = [[NSAttributeDescription alloc] init];
    scratch.name = @"scratch";
    scratch.attributeType = NSStringAttributeType;
    scratch.optional = YES;
    scratch.transient = YES;
    note.properties = @[text, scratch];
    NSManagedObjectModel *model = [[NSManagedObjectModel alloc] init];
    model.entities = @[note];
    return model;
}

int main(void) {
    @autoreleasepool {
        NSPersistentStoreCoordinator *psc =
            [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:makeModel()];
        CHECK([psc addPersistentStoreWithType:NSInMemoryStoreType configuration:nil URL:nil options:nil error:NULL] != nil);
        NSManagedObjectContext *writer = [[NSManagedObjectContext alloc] init];
        writer.persistentStoreCoordinator = psc;
        NSManagedObjectContext *context = [[NSManagedObjectContext alloc] init];
        context.persistentStoreCoordinator = psc;

        NSManagedObject *stored = [NSEntityDescription insertNewObjectForEntityForName:@"Note" inManagedObjectContext:writer];
        [stored setValue:@"orig" forKey:@"text"];
        CHECK([writer save:NULL]);
        NSManagedObject *note = [context objectWithID:[stored objectID]];
        CHECK([[note valueForKey:@"text"] isEqual:@"orig"]);

        /* NO: the local change is discarded; the object is no longer updated (hasChanges stays YES) */
        [note setValue:@"mine" forKey:@"text"];
        CHECK([[context updatedObjects] containsObject:note] && [context hasChanges]);
        [context refreshObject:note mergeChanges:NO];
        CHECK([[note valueForKey:@"text"] isEqual:@"orig"]);
        CHECK([[note changedValues] count] == 0);
        CHECK(![[context updatedObjects] containsObject:note]);
        CHECK(![note isUpdated]);
        CHECK([context hasChanges]);

        /* NO also takes the value the store has now */
        [stored setValue:@"remote" forKey:@"text"];
        CHECK([writer save:NULL]);
        CHECK([[note valueForKey:@"text"] isEqual:@"orig"]);
        [context refreshObject:note mergeChanges:NO];
        CHECK([[note valueForKey:@"text"] isEqual:@"remote"]);

        /* YES: the local change stays on top of the reloaded value, never a conflict */
        [note setValue:@"mine2" forKey:@"text"];
        [stored setValue:@"remote2" forKey:@"text"];
        CHECK([writer save:NULL]);
        [context refreshObject:note mergeChanges:YES];
        CHECK([[note valueForKey:@"text"] isEqual:@"mine2"]);
        CHECK([[[note committedValuesForKeys:@[@"text"]] objectForKey:@"text"] isEqual:@"remote2"]);
        CHECK([[context updatedObjects] containsObject:note]);

        /* YES without a local change takes the new value and does not dirty the object */
        [context refreshObject:note mergeChanges:NO];
        [stored setValue:@"remote3" forKey:@"text"];
        CHECK([writer save:NULL]);
        [context refreshObject:note mergeChanges:YES];
        CHECK([[note valueForKey:@"text"] isEqual:@"remote3"]);
        CHECK(![[context updatedObjects] containsObject:note]);

        /* transient properties: untouched with YES, disposed with NO */
        [note setValue:@"temp" forKey:@"scratch"];
        [context refreshObject:note mergeChanges:YES];
        CHECK([[note valueForKey:@"scratch"] isEqual:@"temp"]);
        [context refreshObject:note mergeChanges:NO];
        CHECK([note valueForKey:@"scratch"] == nil);

        /* NO also drops a pending delete, YES keeps it */
        [context deleteObject:note];
        CHECK([[context deletedObjects] containsObject:note]);
        [context refreshObject:note mergeChanges:YES];
        CHECK([[context deletedObjects] containsObject:note]);
        [context refreshObject:note mergeChanges:NO];
        CHECK(![[context deletedObjects] containsObject:note]);
        CHECK(![note isDeleted]);
        [context rollback];

        /* QUIRK (observed): an inserted, unsaved object is left alone by YES, and by NO it loses its values and
           its insertion; it stays registered and the next save does not store it */
        NSManagedObject *fresh = [NSEntityDescription insertNewObjectForEntityForName:@"Note" inManagedObjectContext:context];
        [fresh setValue:@"unsaved" forKey:@"text"];
        [context processPendingChanges];
        [context refreshObject:fresh mergeChanges:YES];
        CHECK([[context insertedObjects] containsObject:fresh]);
        CHECK([[fresh valueForKey:@"text"] isEqual:@"unsaved"]);
        [context refreshObject:fresh mergeChanges:NO];
        CHECK(![[context insertedObjects] containsObject:fresh]);
        CHECK([fresh valueForKey:@"text"] == nil);
        CHECK(![fresh isInserted]);
        CHECK([[context registeredObjects] containsObject:fresh]);
        CHECK([context save:NULL]);
        CHECK([fresh objectID].isTemporaryID);
        [context rollback];

        /* nil is ignored */
        [context refreshObject:nil mergeChanges:NO];

        /* the object is reported as refreshed, with both flags, when the store has new values for it (macOS
           reports nothing for an object that is up to date) */
        [context processPendingChanges];
        for (int flag = 0; flag < 2; flag++) {
            [stored setValue:[NSString stringWithFormat:@"news%d", flag] forKey:@"text"];
            CHECK([writer save:NULL]);
            (void)[note valueForKey:@"text"]; /* a fault that is refreshed is not reported */
            __block NSDictionary *changes = nil;
            id observer = [[NSNotificationCenter defaultCenter] addObserverForName:NSManagedObjectContextObjectsDidChangeNotification
                                                                            object:context queue:nil
                                                                        usingBlock:^(NSNotification *n) { changes = KEEP([n userInfo]); }];
            [context refreshObject:note mergeChanges:flag];
            [context processPendingChanges];
            [[NSNotificationCenter defaultCenter] removeObserver:observer];
            CHECK([[changes objectForKey:NSRefreshedObjectsKey] containsObject:note]);
        }
    }
    if (failures == 0)
        printf("PASS\n");
    return failures;
}
