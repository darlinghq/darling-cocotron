// SPDX-License-Identifier: GPL-3.0-or-later
//
// NSManagedObjectContext reset, from the documented contract:
// https://developer.apple.com/documentation/coredata/nsmanagedobjectcontext/reset()
// Documented: reset returns the context to its base state and all its managed objects are
// "forgotten"; the caller must discard references to objects fetched through the context.
// Lines marked GUESS pin what the page leaves open (they are not observed on macOS): that the
// pending changes and the undo stack are dropped too, and that reset posts no change
// notification (nor leaves one pending). That reset also removes the context's key-value
// observers is not pinned: it cannot be seen without touching a forgotten object. The test never
// touches an object after the reset, as the page requires. Prints PASS when everything holds;
// the exit code is the number of failed checks.

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

static NSUInteger gNotifications;

int main(void) {
    @autoreleasepool {
        NSPersistentStoreCoordinator *psc =
            [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:makeModel()];
        CHECK([psc addPersistentStoreWithType:NSInMemoryStoreType configuration:nil URL:nil options:nil error:NULL] != nil);
        NSManagedObjectContext *context = [[NSManagedObjectContext alloc] init];
        context.persistentStoreCoordinator = psc;

        /* one saved object; the save has posted its notifications, so none are pending */
        NSManagedObject *saved = [NSEntityDescription insertNewObjectForEntityForName:@"Note" inManagedObjectContext:context];
        [saved setValue:@"saved" forKey:@"text"];
        CHECK([context save:NULL]);
        NSManagedObjectID *savedID = [saved objectID];
        [context processPendingChanges];

        [[NSNotificationCenter defaultCenter] addObserverForName:NSManagedObjectContextObjectsDidChangeNotification
                                                          object:context queue:nil
                                                      usingBlock:^(NSNotification *n) { gNotifications++; }];
        NSUInteger before = gNotifications;

        /* an undoable action on the context's undo manager */
        NSUndoManager *undoManager = [[NSUndoManager alloc] init];
        [undoManager setGroupsByEvent:NO];
        context.undoManager = undoManager;
        [undoManager beginUndoGrouping];
        [undoManager registerUndoWithTarget:undoManager selector:@selector(removeAllActions) object:nil];
        [undoManager endUndoGrouping];
        CHECK([undoManager canUndo]);

        /* an unsaved edit and an unsaved insertion, whose change notification is still pending */
        [saved setValue:@"edited" forKey:@"text"];
        NSManagedObject *unsaved = [NSEntityDescription insertNewObjectForEntityForName:@"Note" inManagedObjectContext:context];
        [unsaved setValue:@"unsaved" forKey:@"text"];
        CHECK([[context registeredObjects] count] == 2 && [context hasChanges]);
        CHECK([[context updatedObjects] count] == 1 && [[context insertedObjects] count] == 1);

        [context reset];
        [context processPendingChanges];    /* would post the pending changes if reset left them */

        CHECK([[context registeredObjects] count] == 0);
        CHECK([[context insertedObjects] count] == 0 && [[context updatedObjects] count] == 0 && [[context deletedObjects] count] == 0);
        CHECK([context objectRegisteredForID:savedID] == nil);
        CHECK(![context hasChanges]);                       /* GUESS: pending changes dropped */
        CHECK(gNotifications == before);                    /* GUESS: no change notification, and none left pending */
        CHECK(![undoManager canUndo]);                      /* GUESS: the undo stack is cleared */

        /* the store was not touched: only the saved object comes back, with its saved value, as a new instance */
        NSFetchRequest *request = [NSFetchRequest fetchRequestWithEntityName:@"Note"];
        NSArray *objects = [context executeFetchRequest:request error:NULL];
        CHECK([objects count] == 1);
        NSManagedObject *again = [objects firstObject];
        CHECK([[again objectID] isEqual:savedID] && again != saved);
        CHECK([[again valueForKey:@"text"] isEqual:@"saved"]);
        CHECK([[context registeredObjects] count] == 1 && ![context hasChanges]);

        /* the context keeps working: edits to the new object are tracked and saved */
        [again setValue:@"after reset" forKey:@"text"];
        CHECK([context hasChanges] && [[context updatedObjects] containsObject:again]);
        CHECK([context save:NULL] && ![context hasChanges]);

        /* reset on an empty context is harmless */
        [context reset];
        [context reset];
        CHECK([[context registeredObjects] count] == 0 && ![context hasChanges]);
    }
    if (!failures) printf("PASS\n");
    return failures;
}
