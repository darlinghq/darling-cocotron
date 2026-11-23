// SPDX-License-Identifier: GPL-3.0-or-later
//
// NSManagedObjectContext undo and redo, from the documented contract:
// https://developer.apple.com/documentation/coredata/nsmanagedobjectcontext/undo()
// https://developer.apple.com/documentation/coredata/nsmanagedobjectcontext/undomanager
// Documented: undo sends an undo message to the undo manager to reverse the latest uncommitted changes
// of the object graph; the public header NSPropertyDescription.h says transient properties are managed
// for undo and redo too. The rest is what macOS 10.14.4 and 26.7.3 do (they agree; mac-probes und1.m of
// batch11b): changes of attribute values, insertions and deletions of objects are recorded; a save does
// not end the history, a rollback does; undoing every change of an object leaves it not updated and
// the context without changes; redo applies what undo recorded; replacing the undo manager takes the
// context's actions out of the old one. Whether a new context has an undo manager differs: macOS
// 10.14.4 has one (groups by event), macOS 26.7.3 has none; Darling follows 10.14.4 (QUIRK) and the test
// checks it when started with the argument "default-manager".
// Prints PASS when everything holds; the exit code is the number of failed checks.

#import <Foundation/Foundation.h>
#import <CoreData/CoreData.h>
#include <stdio.h>
#include <string.h>

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

int main(int argc, char **argv) {
    @autoreleasepool {
        NSPersistentStoreCoordinator *psc =
            [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:makeModel()];
        CHECK([psc addPersistentStoreWithType:NSInMemoryStoreType configuration:nil URL:nil options:nil error:NULL] != nil);
        NSManagedObjectContext *context = [[NSManagedObjectContext alloc] init];
        context.persistentStoreCoordinator = psc;

        if (argc > 1 && strcmp(argv[1], "default-manager") == 0) {
            CHECK([context undoManager] != nil);
            CHECK([[context undoManager] groupsByEvent]);
        }

        /* undo and redo without an undo manager do nothing */
        context.undoManager = nil;
        CHECK([context undoManager] == nil);
        [context undo];
        [context redo];

        NSManagedObject *note = [NSEntityDescription insertNewObjectForEntityForName:@"Note" inManagedObjectContext:context];
        [note setValue:@"a" forKey:@"text"];
        CHECK([context save:NULL]);

        NSUndoManager *undoManager = [[NSUndoManager alloc] init];
        [undoManager setGroupsByEvent:NO];
        context.undoManager = undoManager;
        CHECK(context.undoManager == undoManager);
        CHECK(![undoManager canUndo]);

        /* two changes in one group are undone together; the object is then no longer updated */
        [undoManager beginUndoGrouping];
        [note setValue:@"b" forKey:@"text"];
        [note setValue:@"c" forKey:@"text"];
        [undoManager endUndoGrouping];
        CHECK([undoManager canUndo]);
        CHECK([[context updatedObjects] containsObject:note] && [context hasChanges]);
        [context undo];
        CHECK([[note valueForKey:@"text"] isEqual:@"a"]);
        CHECK(![undoManager canUndo] && [undoManager canRedo]);
        CHECK(![[context updatedObjects] containsObject:note]);
        CHECK(![context hasChanges]);
        /* redo applies the changes again */
        [context redo];
        CHECK([[note valueForKey:@"text"] isEqual:@"c"]);
        CHECK([[context updatedObjects] containsObject:note]);
        [context undo];
        CHECK([[note valueForKey:@"text"] isEqual:@"a"]);
        [undoManager removeAllActions];

        /* a value that was nil comes back as nil, and a set to nil is undone */
        [undoManager beginUndoGrouping];
        [note setValue:nil forKey:@"text"];
        [undoManager endUndoGrouping];
        CHECK([context save:NULL]);
        [undoManager removeAllActions];
        [undoManager beginUndoGrouping];
        [note setValue:@"d" forKey:@"text"];
        [undoManager endUndoGrouping];
        [context undo];
        CHECK([note valueForKey:@"text"] == nil);
        [undoManager beginUndoGrouping];
        [note setValue:nil forKey:@"text"];
        [note setValue:@"e" forKey:@"text"];
        [undoManager endUndoGrouping];
        [context undo];
        CHECK([note valueForKey:@"text"] == nil);

        /* transient properties are recorded too */
        [undoManager beginUndoGrouping];
        [note setValue:@"temp" forKey:@"scratch"];
        [undoManager endUndoGrouping];
        [context undo];
        CHECK([note valueForKey:@"scratch"] == nil);
        [undoManager removeAllActions];

        /* a save does not end the history: the change that was saved is undone, and the object is updated again */
        [undoManager beginUndoGrouping];
        [note setValue:@"f" forKey:@"text"];
        [undoManager endUndoGrouping];
        CHECK([context save:NULL]);
        CHECK([undoManager canUndo]);
        CHECK(![[context updatedObjects] containsObject:note]);
        [context undo];
        CHECK([note valueForKey:@"text"] == nil);
        CHECK([[context updatedObjects] containsObject:note]);
        [context redo];
        CHECK([[note valueForKey:@"text"] isEqual:@"f"]);
        CHECK([context save:NULL]);
        [undoManager removeAllActions];

        /* changes without an open group on a manager that does not group by event do not raise, and are undone */
        NSUndoManager *plain = [[NSUndoManager alloc] init];
        [plain setGroupsByEvent:NO];
        context.undoManager = plain;
        [note setValue:@"p" forKey:@"text"];
        [note setValue:@"q" forKey:@"text"];
        [context processPendingChanges];
        CHECK([plain canUndo]);
        for (int i = 0; i < 4 && [plain canUndo]; i++)
            [context undo];
        CHECK([[note valueForKey:@"text"] isEqual:@"f"]);
        CHECK(![context hasChanges]);
        context.undoManager = undoManager;

        /* several groups are undone one at a time, the last change first */
        [undoManager beginUndoGrouping];
        [note setValue:@"x" forKey:@"text"];
        [undoManager endUndoGrouping];
        [undoManager beginUndoGrouping];
        [note setValue:@"y" forKey:@"text"];
        [undoManager endUndoGrouping];
        [undoManager beginUndoGrouping];
        [note setValue:@"z" forKey:@"text"];
        [undoManager endUndoGrouping];
        [context undo];
        CHECK([[note valueForKey:@"text"] isEqual:@"y"] && [[context updatedObjects] containsObject:note]);
        [context undo];
        CHECK([[note valueForKey:@"text"] isEqual:@"x"] && [[context updatedObjects] containsObject:note]);
        [context undo];
        CHECK([[note valueForKey:@"text"] isEqual:@"f"]);
        CHECK(![[context updatedObjects] containsObject:note] && ![context hasChanges]);
        CHECK(![undoManager canUndo]);
        [undoManager removeAllActions];

        /* a rollback ends the history */
        [undoManager beginUndoGrouping];
        [note setValue:@"g" forKey:@"text"];
        [undoManager endUndoGrouping];
        CHECK([undoManager canUndo]);
        [context rollback];
        CHECK([[note valueForKey:@"text"] isEqual:@"f"]);
        CHECK(![undoManager canUndo]);

        /* an insertion is recorded and undone: the object is no longer inserted; redo inserts it again */
        [undoManager beginUndoGrouping];
        NSManagedObject *fresh = [NSEntityDescription insertNewObjectForEntityForName:@"Note" inManagedObjectContext:context];
        [fresh setValue:@"fresh" forKey:@"text"];
        [undoManager endUndoGrouping];
        CHECK([undoManager canUndo]);
        CHECK([[context insertedObjects] containsObject:fresh]);
        [context undo];
        CHECK(![[context insertedObjects] containsObject:fresh]);
        CHECK(![context hasChanges]);
        [context redo];
        CHECK([[context insertedObjects] containsObject:fresh]);
        [context rollback];
        [undoManager removeAllActions];

        /* a deletion is recorded and undone; redo deletes the object again */
        [undoManager beginUndoGrouping];
        [context deleteObject:note];
        [undoManager endUndoGrouping];
        CHECK([undoManager canUndo]);
        CHECK([[context deletedObjects] containsObject:note]);
        [context undo];
        CHECK(![[context deletedObjects] containsObject:note] && ![note isDeleted]);
        CHECK(![context hasChanges]);
        [context redo];
        CHECK([[context deletedObjects] containsObject:note]);
        [context rollback];
        [undoManager removeAllActions];

        /* setting the undo manager that is already set keeps the history */
        [undoManager beginUndoGrouping];
        [note setValue:@"s" forKey:@"text"];
        [undoManager endUndoGrouping];
        context.undoManager = undoManager;
        CHECK([undoManager canUndo]);
        [context undo];
        CHECK([[note valueForKey:@"text"] isEqual:@"f"]);
        [undoManager removeAllActions];

        /* a new undo manager gets no actions of the old one, which loses the context's actions */
        [undoManager beginUndoGrouping];
        [note setValue:@"h" forKey:@"text"];
        [undoManager endUndoGrouping];
        NSUndoManager *other = [[NSUndoManager alloc] init];
        [other setGroupsByEvent:NO];
        context.undoManager = other;
        CHECK(![undoManager canUndo]);
        CHECK(![other canUndo]);
        CHECK(context.undoManager == other);
        [other beginUndoGrouping];
        [note setValue:@"i" forKey:@"text"];
        [other endUndoGrouping];
        CHECK([other canUndo]);
        [context undo];
        CHECK([[note valueForKey:@"text"] isEqual:@"h"]);
        context.undoManager = nil;
        CHECK(context.undoManager == nil);
    }
    if (failures == 0)
        printf("PASS\n");
    return failures;
}
