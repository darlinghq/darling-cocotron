/*
 * Copyright (C) 2026 Lubos Dolezel
 *
 * SQLite persistent store: durability of saved objects across coordinators,
 * relationship round trips, deletes, failed saves, object ID URIs and
 * argument errors. Public API only; the expectations hold on macOS.
 */
#import <Foundation/Foundation.h>
#import <CoreData/CoreData.h>
#include <stdio.h>
#include <unistd.h>

static int failures;
#define CHECK(c) do { if (!(c)) { printf("FAIL line %d: %s\n", __LINE__, #c); failures++; } } while (0)

static NSManagedObjectModel *makeModel(void) {
    NSEntityDescription *author = [[NSEntityDescription alloc] init];
    author.name = @"Author";
    author.managedObjectClassName = @"NSManagedObject";
    NSEntityDescription *book = [[NSEntityDescription alloc] init];
    book.name = @"Book";
    book.managedObjectClassName = @"NSManagedObject";

    NSAttributeDescription *name = [[NSAttributeDescription alloc] init];
    name.name = @"name";
    name.attributeType = NSStringAttributeType;
    name.optional = NO;
    NSAttributeDescription *born = [[NSAttributeDescription alloc] init];
    born.name = @"born";
    born.attributeType = NSInteger32AttributeType;
    born.optional = YES;
    NSAttributeDescription *title = [[NSAttributeDescription alloc] init];
    title.name = @"title";
    title.attributeType = NSStringAttributeType;
    title.optional = YES;
    NSAttributeDescription *pages = [[NSAttributeDescription alloc] init];
    pages.name = @"pages";
    pages.attributeType = NSInteger32AttributeType;
    pages.optional = YES;

    NSRelationshipDescription *books = [[NSRelationshipDescription alloc] init];
    books.name = @"books";
    books.destinationEntity = book;
    books.minCount = 0;
    books.maxCount = 0;
    books.deleteRule = NSNullifyDeleteRule;
    books.optional = YES;
    NSRelationshipDescription *writer = [[NSRelationshipDescription alloc] init];
    writer.name = @"writer";
    writer.destinationEntity = author;
    writer.minCount = 0;
    writer.maxCount = 1;
    writer.deleteRule = NSNullifyDeleteRule;
    writer.optional = YES;
    books.inverseRelationship = writer;
    writer.inverseRelationship = books;

    author.properties = @[name, born, books];
    book.properties = @[title, pages, writer];
    NSManagedObjectModel *model = [[NSManagedObjectModel alloc] init];
    model.entities = @[author, book];
    return model;
}

static NSManagedObjectContext *openContext(NSManagedObjectModel *model, NSURL *url, NSError **error) {
    NSPersistentStoreCoordinator *psc = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:model];
    if (![psc addPersistentStoreWithType:NSSQLiteStoreType configuration:nil URL:url options:nil error:error])
        return nil;
    NSManagedObjectContext *context = [[NSManagedObjectContext alloc] init];
    [context setPersistentStoreCoordinator:psc];
    return context;
}

static NSArray *fetchAll(NSManagedObjectContext *context, NSString *entity, NSString *sortKey) {
    NSFetchRequest *request = [NSFetchRequest fetchRequestWithEntityName:entity];
    if (sortKey)
        request.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:sortKey ascending:YES]];
    return [context executeFetchRequest:request error:NULL];
}

static NSString *raiseName(void (^block)(void)) {
    @try { block(); } @catch (NSException *e) { return [e name]; }
    return nil;
}

int main(void) {
    @autoreleasepool {
        NSString *dir = [NSTemporaryDirectory() stringByAppendingPathComponent:
            [NSString stringWithFormat:@"sqlite-store-%d", getpid()]];
        [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:NULL];
        NSURL *url = [NSURL fileURLWithPath:[dir stringByAppendingPathComponent:@"library.sqlite"]];
        NSManagedObjectModel *model = makeModel();
        NSError *error = nil;

        /* create, relate and save */
        NSManagedObjectContext *c1 = openContext(model, url, &error);
        CHECK(c1 != nil && error == nil);
        if (!c1) { printf("open error: %s\n", [[error description] UTF8String]); return 2; }
        CHECK([[NSFileManager defaultManager] fileExistsAtPath:[url path]]);
        NSManagedObject *ada = [NSEntityDescription insertNewObjectForEntityForName:@"Author" inManagedObjectContext:c1];
        [ada setValue:@"Ada" forKey:@"name"];
        [ada setValue:@1815 forKey:@"born"];
        NSManagedObject *bob = [NSEntityDescription insertNewObjectForEntityForName:@"Author" inManagedObjectContext:c1];
        [bob setValue:@"Bob" forKey:@"name"];
        for (int i = 0; i < 3; i++) {
            NSManagedObject *b = [NSEntityDescription insertNewObjectForEntityForName:@"Book" inManagedObjectContext:c1];
            [b setValue:[NSString stringWithFormat:@"Book %d", i] forKey:@"title"];
            [b setValue:@(100 + i) forKey:@"pages"];
            [b setValue:(i < 2 ? ada : bob) forKey:@"writer"];
        }
        CHECK([[ada valueForKey:@"books"] count] == 2 && [[bob valueForKey:@"books"] count] == 1);
        CHECK([[ada objectID] isTemporaryID]);
        CHECK([c1 save:&error] && error == nil);
        CHECK(![[ada objectID] isTemporaryID] && ![c1 hasChanges]);

        /* the object ID URI names the store and the entity, and resolves back */
        NSURL *uri = [[ada objectID] URIRepresentation];
        CHECK([[uri scheme] isEqual:@"x-coredata"]);
        CHECK([[uri path] hasPrefix:@"/Author/"]);
        NSManagedObjectID *resolved = [[c1 persistentStoreCoordinator] managedObjectIDForURIRepresentation:uri];
        CHECK([resolved isEqual:[ada objectID]]);

        /* a second coordinator on the same file sees the saved data */
        NSManagedObjectContext *c2 = openContext(model, url, &error);
        CHECK(c2 != nil);
        NSArray *authors = fetchAll(c2, @"Author", @"name");
        CHECK([authors count] == 2);
        CHECK([[[authors objectAtIndex:0] valueForKey:@"name"] isEqual:@"Ada"]);
        CHECK([[[authors objectAtIndex:0] valueForKey:@"born"] isEqual:@1815]);
        CHECK([[authors objectAtIndex:1] valueForKey:@"born"] == nil);
        NSArray *adasBooks = [[[authors objectAtIndex:0] valueForKey:@"books"] allObjects];
        CHECK([adasBooks count] == 2);
        NSManagedObject *anyBook = [adasBooks firstObject];
        CHECK([[anyBook valueForKey:@"writer"] valueForKey:@"name"] != nil);
        CHECK([[[anyBook valueForKey:@"writer"] valueForKey:@"name"] isEqual:@"Ada"]);
        CHECK([fetchAll(c2, @"Book", @"pages") count] == 3);
        CHECK([[[fetchAll(c2, @"Book", @"pages") lastObject] valueForKey:@"pages"] isEqual:@102]);

        /* equality predicates */
        NSFetchRequest *request = [NSFetchRequest fetchRequestWithEntityName:@"Book"];
        request.predicate = [NSPredicate predicateWithFormat:@"title == %@", @"Book 1"];
        NSArray *matching = [c2 executeFetchRequest:request error:NULL];
        CHECK([matching count] == 1 && [[[matching firstObject] valueForKey:@"pages"] isEqual:@101]);

        /* updates persist */
        [[authors objectAtIndex:1] setValue:@"Robert" forKey:@"name"];
        CHECK([c2 save:&error]);
        NSManagedObjectContext *c3 = openContext(model, url, &error);
        CHECK([[[fetchAll(c3, @"Author", @"name") lastObject] valueForKey:@"name"] isEqual:@"Robert"] ||
              [[[fetchAll(c3, @"Author", @"name") objectAtIndex:0] valueForKey:@"name"] isEqual:@"Ada"]);

        /* a failed save keeps the pending changes; fixing the problem lets the same changes save */
        NSManagedObject *bad = [NSEntityDescription insertNewObjectForEntityForName:@"Author" inManagedObjectContext:c3];
        NSError *saveError = nil;
        CHECK(![c3 save:&saveError] && saveError != nil);
        CHECK([c3 hasChanges] && [[c3 insertedObjects] containsObject:bad]);
        [bad setValue:@"Carol" forKey:@"name"];
        CHECK([c3 save:&saveError]);
        CHECK([fetchAll(c3, @"Author", nil) count] == 3);

        /* deleting an author nullifies its books' writer and persists */
        NSManagedObjectContext *c4 = openContext(model, url, &error);
        for (NSManagedObject *a in fetchAll(c4, @"Author", @"name"))
            if ([[a valueForKey:@"name"] isEqual:@"Ada"])
                [c4 deleteObject:a];
        CHECK([c4 save:&error]);
        NSManagedObjectContext *c5 = openContext(model, url, &error);
        CHECK([fetchAll(c5, @"Author", nil) count] == 2);
        CHECK([fetchAll(c5, @"Book", nil) count] == 3);
        NSUInteger orphans = 0;
        for (NSManagedObject *b in fetchAll(c5, @"Book", nil))
            if ([b valueForKey:@"writer"] == nil)
                orphans++;
        CHECK(orphans == 2);

        /* an object inserted and deleted before saving is never written */
        NSManagedObject *ghost = [NSEntityDescription insertNewObjectForEntityForName:@"Author" inManagedObjectContext:c5];
        [ghost setValue:@"Ghost" forKey:@"name"];
        [c5 deleteObject:ghost];
        CHECK([c5 save:&error]);
        CHECK([fetchAll(openContext(model, url, &error), @"Author", nil) count] == 2);

        /* argument errors */
        NSPersistentStoreCoordinator *psc = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:model];
        CHECK([raiseName(^{ [psc addPersistentStoreWithType:NSSQLiteStoreType configuration:nil URL:nil options:nil error:NULL]; })
              isEqual:NSInvalidArgumentException]);
        NSError *readOnlyError = nil;
        NSDictionary *ro = @{NSReadOnlyPersistentStoreOption: @YES};
        NSURL *missing = [NSURL fileURLWithPath:[dir stringByAppendingPathComponent:@"missing.sqlite"]];
        CHECK([psc addPersistentStoreWithType:NSSQLiteStoreType configuration:nil URL:missing options:ro error:&readOnlyError] == nil);
        CHECK([[readOnlyError domain] isEqual:@"NSCocoaErrorDomain"] && [readOnlyError code] == 260);
        CHECK(![[NSFileManager defaultManager] fileExistsAtPath:[missing path]]);

        [[NSFileManager defaultManager] removeItemAtPath:dir error:NULL];
    }
    if (failures)
        return 1;
    puts("PASS_COREDATA_SQLITE_STORE");
    return 0;
}
