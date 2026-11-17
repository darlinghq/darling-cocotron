/*
 * Copyright (C) 2026 Lubos Dolezel
 *
 * The URI representation of managed object IDs: x-coredata://<store UUID>/<Entity>/p<N> for
 * saved objects of SQLite and in-memory stores, x-coredata:///<Entity>/t<...> before the first
 * save, and the round trip through the coordinator. Public API only; the expectations hold on
 * macOS. An optional argument names the directory for the store files.
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
    NSAttributeDescription *name = [[NSAttributeDescription alloc] init];
    name.name = @"name";
    name.attributeType = NSStringAttributeType;
    name.optional = YES;
    author.properties = @[name];
    NSEntityDescription *sub = [[NSEntityDescription alloc] init];
    sub.name = @"Sub";
    sub.managedObjectClassName = @"NSManagedObject";
    NSAttributeDescription *x = [[NSAttributeDescription alloc] init];
    x.name = @"x";
    x.attributeType = NSStringAttributeType;
    x.optional = YES;
    sub.properties = @[x];
    NSManagedObjectModel *model = [[NSManagedObjectModel alloc] init];
    model.entities = @[author, sub];
    return model;
}

static NSManagedObject *insert(NSManagedObjectContext *c, NSString *entity) {
    return [NSEntityDescription insertNewObjectForEntityForName:entity inManagedObjectContext:c];
}

/* Returns N when the URI is x-coredata://<uuid>/<entity>/p<N>, else -1. */
static long numberOf(NSURL *uri, NSString *uuid, NSString *entity) {
    NSString *prefix = [NSString stringWithFormat:@"x-coredata://%@/%@/p", uuid, entity];
    NSString *s = [uri absoluteString];
    if (![s hasPrefix:prefix] || [s length] == [prefix length])
        return -1;
    NSString *digits = [s substringFromIndex:[prefix length]];
    for (NSUInteger i = 0; i < [digits length]; i++)
        if ([digits characterAtIndex:i] < '0' || [digits characterAtIndex:i] > '9')
            return -1;
    return [digits integerValue];
}

int main(int argc, char **argv) {
    @autoreleasepool {
        NSString *base = argc > 1 ? [NSString stringWithUTF8String:argv[1]] : NSTemporaryDirectory();
        NSString *dir = [base stringByAppendingPathComponent:[NSString stringWithFormat:@"object-id-uri-%d", getpid()]];
        [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:NULL];
        NSString *path = [dir stringByAppendingPathComponent:@"u.sqlite"];
        NSURL *url = [NSURL fileURLWithPath:path];

        // SQLite: numbers are per entity, start at 1 and are not reused.
        NSPersistentStoreCoordinator *psc = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:makeModel()];
        NSPersistentStore *store = [psc addPersistentStoreWithType:NSSQLiteStoreType configuration:nil URL:url options:nil error:NULL];
        CHECK(store != nil);
        NSString *uuid = store.identifier;
        CHECK([[store.metadata objectForKey:NSStoreUUIDKey] isEqual:uuid]);
        NSManagedObjectContext *c = [[NSManagedObjectContext alloc] init];
        c.persistentStoreCoordinator = psc;
        NSArray *kinds = @[@"Author", @"Author", @"Sub", @"Author"];
        NSMutableArray *objs = [NSMutableArray array];
        for (NSString *e in kinds)
            [objs addObject:insert(c, e)];
        for (NSManagedObject *o in objs) {
            NSString *s = [[o.objectID URIRepresentation] absoluteString];
            NSString *prefix = [NSString stringWithFormat:@"x-coredata:///%@/t", o.entity.name];
            CHECK([s hasPrefix:prefix] && [s length] > [prefix length]);
            CHECK(o.objectID.isTemporaryID);
        }
        CHECK([c save:NULL]);
        NSMutableSet *authors = [NSMutableSet set], *subs = [NSMutableSet set];
        for (NSManagedObject *o in objs) {
            CHECK(!o.objectID.isTemporaryID);
            long n = numberOf(o.objectID.URIRepresentation, uuid, o.entity.name);
            CHECK(n > 0);
            [([o.entity.name isEqual:@"Sub"] ? subs : authors) addObject:@(n)];
        }
        NSSet *expectedAuthors = [NSSet setWithObjects:@1, @2, @3, nil];
        CHECK([authors isEqual:expectedAuthors]);
        CHECK([subs isEqual:[NSSet setWithObject:@1]]);

        // The URI resolves to the same ID, also through a second coordinator on the same file.
        for (NSManagedObject *o in objs)
            CHECK([[psc managedObjectIDForURIRepresentation:o.objectID.URIRepresentation] isEqual:o.objectID]);
        NSManagedObject *deleted = objs[1];
        NSString *deletedURI = [deleted.objectID.URIRepresentation absoluteString];
        [c deleteObject:deleted];
        CHECK([c save:NULL]);
        NSManagedObject *next = insert(c, @"Author");
        CHECK([c save:NULL]);
        CHECK(numberOf(next.objectID.URIRepresentation, uuid, @"Author") == 4);
        CHECK(![[next.objectID.URIRepresentation absoluteString] isEqual:deletedURI]);

        NSPersistentStoreCoordinator *psc2 = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:makeModel()];
        NSPersistentStore *store2 = [psc2 addPersistentStoreWithType:NSSQLiteStoreType configuration:nil URL:url options:nil error:NULL];
        CHECK([store2.identifier isEqual:uuid]);
        NSManagedObjectContext *c2 = [[NSManagedObjectContext alloc] init];
        c2.persistentStoreCoordinator = psc2;
        NSArray *fetched = [c2 executeFetchRequest:[NSFetchRequest fetchRequestWithEntityName:@"Author"] error:NULL];
        CHECK([fetched count] == 3);
        NSMutableSet *uris = [NSMutableSet set];
        for (NSManagedObject *o in fetched)
            [uris addObject:[o.objectID.URIRepresentation absoluteString]];
        CHECK([uris containsObject:[next.objectID.URIRepresentation absoluteString]]);
        CHECK(![uris containsObject:deletedURI]);
        NSManagedObjectID *resolved = [psc2 managedObjectIDForURIRepresentation:next.objectID.URIRepresentation];
        CHECK(resolved != nil);
        CHECK([fetched containsObject:[c2 objectWithID:resolved]]);

        // Numbers of deleted objects are not handed out again after reopening the store either.
        NSManagedObject *last = fetched[0];
        for (NSManagedObject *o in fetched)
            if (numberOf(o.objectID.URIRepresentation, uuid, @"Author") == 4)
                last = o;
        [c2 deleteObject:last];
        CHECK([c2 save:NULL]);
        NSPersistentStoreCoordinator *psc3 = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:makeModel()];
        CHECK([psc3 addPersistentStoreWithType:NSSQLiteStoreType configuration:nil URL:url options:nil error:NULL] != nil);
        NSManagedObjectContext *c3 = [[NSManagedObjectContext alloc] init];
        c3.persistentStoreCoordinator = psc3;
        NSManagedObject *again = insert(c3, @"Author");
        CHECK([c3 save:NULL]);
        CHECK(numberOf(again.objectID.URIRepresentation, uuid, @"Author") == 5);

        // Invalid URIs.
        NSURL *otherStore = [NSURL URLWithString:@"x-coredata://00000000-0000-0000-0000-000000000000/Author/p1"];
        CHECK([psc managedObjectIDForURIRepresentation:otherStore] == nil);
        NSURL *otherEntity = [NSURL URLWithString:[NSString stringWithFormat:@"x-coredata://%@/Nothing/p1", uuid]];
        // A URI that does not name an entity of the model, or has no store, is invalid.
        NSString *raised = nil;
        @try { [psc managedObjectIDForURIRepresentation:otherEntity]; } @catch (NSException *e) { raised = e.name; }
        CHECK([raised isEqualToString:NSInvalidArgumentException]);
        raised = nil;
        @try { [psc managedObjectIDForURIRepresentation:[NSURL URLWithString:@"x-coredata:///Author/tABCD"]]; } @catch (NSException *e) { raised = e.name; }
        CHECK([raised isEqualToString:NSInvalidArgumentException]);

        // In-memory: numbers are positive, distinct and keep the same form.
        NSPersistentStoreCoordinator *mpsc = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:makeModel()];
        NSPersistentStore *mstore = [mpsc addPersistentStoreWithType:NSInMemoryStoreType configuration:nil URL:nil options:nil error:NULL];
        NSManagedObjectContext *mc = [[NSManagedObjectContext alloc] init];
        mc.persistentStoreCoordinator = mpsc;
        NSMutableArray *mobjs = [NSMutableArray array];
        for (NSString *e in kinds)
            [mobjs addObject:insert(mc, e)];
        CHECK([mc save:NULL]);
        NSMutableSet *numbers = [NSMutableSet set];
        for (NSManagedObject *o in mobjs) {
            long n = numberOf(o.objectID.URIRepresentation, mstore.identifier, o.entity.name);
            CHECK(n > 0);
            [numbers addObject:@(n)];
            CHECK([[mpsc managedObjectIDForURIRepresentation:o.objectID.URIRepresentation] isEqual:o.objectID]);
        }
        CHECK([numbers count] == 4);
        [[NSFileManager defaultManager] removeItemAtPath:dir error:NULL];
    }
    if (failures) { printf("FAILURES: %d\n", failures); return 1; }
    printf("PASS_OBJECT_ID_URI\n");
    return 0;
}
