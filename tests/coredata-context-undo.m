// SPDX-License-Identifier: GPL-3.0-or-later
//
// NSManagedObjectContext undo, from the documented contract:
// https://developer.apple.com/documentation/coredata/nsmanagedobjectcontext/undo()
// https://developer.apple.com/documentation/coredata/nsmanagedobjectcontext/undomanager
// Documented: the default undoManager is nil, setting one enables undo support, and undo sends an
// undo message to the undo manager to reverse the latest uncommitted changes of the object graph.
// The public header NSPropertyDescription.h says transient properties are managed for undo and redo too. Lines
// marked GUESS pin what the pages leave open (they are not observed on macOS): that a save and a
// rollback end the context's undo history (only the context's own actions, those of other
// targets of a shared undo manager stay), that inserting an object records nothing yet, and that
// an object whose changes were all undone stays among the updated objects.
// Prints PASS when everything holds; the exit code is the number of failed checks.

#import <Foundation/Foundation.h>
#import <CoreData/CoreData.h>
#include <stdio.h>

static int failures;
#define CHECK(...) do { if (!(__VA_ARGS__)) { printf("FAIL line %d: %s\n", __LINE__, #__VA_ARGS__); failures++; } } while (0)

static int markerRuns;

@interface Marker : NSObject
- (void)run:(id)ignored;
@end

@implementation Marker
- (void)run:(id)ignored { markerRuns++; }
@end

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
        NSManagedObjectContext *context = [[NSManagedObjectContext alloc] init];
        context.persistentStoreCoordinator = psc;

        /* the default is no undo manager, and undo without one does nothing */
        CHECK([context undoManager] == nil);
        [context undo];

        NSManagedObject *note = [NSEntityDescription insertNewObjectForEntityForName:@"Note" inManagedObjectContext:context];
        [note setValue:@"a" forKey:@"text"];
        CHECK([context save:NULL]);

        NSUndoManager *undoManager = [[NSUndoManager alloc] init];
        [undoManager setGroupsByEvent:NO];
        context.undoManager = undoManager;
        CHECK(context.undoManager == undoManager);
        CHECK(![undoManager canUndo]);

        /* two changes in one group are undone together */
        [undoManager beginUndoGrouping];
        [note setValue:@"b" forKey:@"text"];
        [note setValue:@"c" forKey:@"text"];
        [undoManager endUndoGrouping];
        CHECK([undoManager canUndo]);
        [context undo];
        CHECK([[note valueForKey:@"text"] isEqual:@"a"]);
        CHECK(![undoManager canUndo]);
        /* GUESS: the object stays updated although it is back to its committed value */
        CHECK([[context updatedObjects] containsObject:note]);

        /* a value that was nil comes back as nil, and a set to nil is undone */
        [undoManager beginUndoGrouping];
        [note setValue:nil forKey:@"text"];
        [undoManager endUndoGrouping];
        CHECK([context save:NULL]);
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

        /* GUESS: inserting an object records nothing */
        [context rollback];
        [undoManager beginUndoGrouping];
        NSManagedObject *fresh = [NSEntityDescription insertNewObjectForEntityForName:@"Note" inManagedObjectContext:context];
        [undoManager endUndoGrouping];
        (void)fresh;
        CHECK(![undoManager canUndo]);
        [context rollback];

        /* GUESS: a save ends the context's history and leaves the actions of other targets */
        Marker *marker = [[Marker alloc] init];
        [undoManager beginUndoGrouping];
        [note setValue:@"f" forKey:@"text"];
        [undoManager registerUndoWithTarget:marker selector:@selector(run:) object:nil];
        [undoManager endUndoGrouping];
        CHECK([context save:NULL]);
        CHECK([undoManager canUndo]);
        [undoManager undo];
        CHECK(markerRuns == 1);
        CHECK([[note valueForKey:@"text"] isEqual:@"f"]);

        /* several groups at a save: none of the context's actions may stay behind (this needs the
           NSUndoManager removeAllActionsWithTarget: fix of darling-foundation, which skipped every
           second group) */
        [undoManager beginUndoGrouping];
        [note setValue:@"x" forKey:@"text"];
        [undoManager endUndoGrouping];
        [undoManager beginUndoGrouping];
        [note setValue:@"y" forKey:@"text"];
        [undoManager endUndoGrouping];
        [undoManager beginUndoGrouping];
        [note setValue:@"z" forKey:@"text"];
        [undoManager endUndoGrouping];
        CHECK([context save:NULL]);
        CHECK(![undoManager canUndo]);
        [context undo];
        CHECK([[note valueForKey:@"text"] isEqual:@"z"]);

        /* setting the undo manager that is already set keeps the history */
        [undoManager beginUndoGrouping];
        [note setValue:@"s" forKey:@"text"];
        [undoManager endUndoGrouping];
        context.undoManager = undoManager;
        CHECK([undoManager canUndo]);
        [context undo];
        CHECK([[note valueForKey:@"text"] isEqual:@"z"]);

        /* GUESS: a rollback ends it too */
        [undoManager beginUndoGrouping];
        [note setValue:@"g" forKey:@"text"];
        [undoManager endUndoGrouping];
        [context rollback];
        CHECK(![undoManager canUndo]);

        /* a new undo manager gets no actions of the old one */
        [undoManager beginUndoGrouping];
        [note setValue:@"h" forKey:@"text"];
        [undoManager endUndoGrouping];
        context.undoManager = nil;
        CHECK(![undoManager canUndo]);
        CHECK(context.undoManager == nil);
    }
    if (failures == 0)
        printf("PASS\n");
    return failures;
}
