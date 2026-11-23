// SPDX-License-Identifier: GPL-3.0-or-later
//
// NSManagedObjectContext refreshObject:mergeChanges:, from the documented contract:
// https://developer.apple.com/documentation/coredata/nsmanagedobjectcontext/refresh(_:mergechanges:)
// Documented: with NO the pending changes are discarded and the values come from the store again;
// with YES the values are reloaded and the local changes applied over them (never a conflict);
// with YES transient properties are not affected, with NO they are disposed. Lines marked GUESS
// pin what the page leaves open (they are not observed on macOS): that an object inserted and not
// yet saved, and an object of another context, are left alone; that NO also drops a pending
// delete; and that the object is reported as refreshed in the change notification.
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

        /* NO: the local change is discarded; the context has no changes left */
        [note setValue:@"mine" forKey:@"text"];
        CHECK([[context updatedObjects] containsObject:note] && [context hasChanges]);
        [context refreshObject:note mergeChanges:NO];
        CHECK([[note valueForKey:@"text"] isEqual:@"orig"]);
        CHECK([[note changedValues] count] == 0);
        CHECK(![[context updatedObjects] containsObject:note] && ![context hasChanges]);
        CHECK(![note isUpdated]);

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
        CHECK(![[context updatedObjects] containsObject:note] && ![context hasChanges]);

        /* transient properties: untouched with YES, disposed with NO */
        [note setValue:@"temp" forKey:@"scratch"];
        [context refreshObject:note mergeChanges:YES];
        CHECK([[note valueForKey:@"scratch"] isEqual:@"temp"]);
        [context refreshObject:note mergeChanges:NO];
        CHECK([note valueForKey:@"scratch"] == nil);

        /* GUESS: NO also drops a pending delete */
        [context deleteObject:note];
        CHECK([[context deletedObjects] containsObject:note]);
        [context refreshObject:note mergeChanges:NO];
        CHECK(![[context deletedObjects] containsObject:note] && ![context hasChanges]);
        CHECK(![note isDeleted]);

        /* GUESS: an object inserted and not yet saved is left alone */
        NSManagedObject *fresh = [NSEntityDescription insertNewObjectForEntityForName:@"Note" inManagedObjectContext:context];
        [fresh setValue:@"unsaved" forKey:@"text"];
        [context refreshObject:fresh mergeChanges:NO];
        CHECK([[context insertedObjects] containsObject:fresh]);
        CHECK([[fresh valueForKey:@"text"] isEqual:@"unsaved"]);
        [context rollback];

        /* GUESS: an object of another context is left alone */
        [context refreshObject:stored mergeChanges:NO];
        CHECK([[stored valueForKey:@"text"] isEqual:@"remote3"]);

        /* GUESS: the object is reported as refreshed */
        [context processPendingChanges];
        __block NSDictionary *changes = nil;
        id observer = [[NSNotificationCenter defaultCenter] addObserverForName:NSManagedObjectContextObjectsDidChangeNotification
                                                                        object:context queue:nil
                                                                    usingBlock:^(NSNotification *n) { changes = [n userInfo]; }];
        [context refreshObject:note mergeChanges:YES];
        [context processPendingChanges];
        [[NSNotificationCenter defaultCenter] removeObserver:observer];
        CHECK([[changes objectForKey:NSRefreshedObjectsKey] containsObject:note]);
    }
    if (failures == 0)
        printf("PASS\n");
    return failures;
}
