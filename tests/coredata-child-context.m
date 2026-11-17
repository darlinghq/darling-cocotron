/*
 * Copyright (C) 2026 Lubos Dolezel
 *
 * Nested managed object contexts: parentContext, saves that move into the parent first and
 * reach the store only with the parent's save, the notifications of those saves, fetches through
 * the nesting, relationships, grandchildren and automaticallyMergesChangesFromParent. Public API
 * only; the expectations hold on macOS. An optional argument names the directory for the store.
 */
#import <Foundation/Foundation.h>
#import <CoreData/CoreData.h>
#include <stdio.h>
#include <unistd.h>

static int failures;
#define HAS(events, part) do { if (![(events) containsString:(part)]) { printf("FAIL line %d: events \"%s\" lack \"%s\"\n", __LINE__, [(events) UTF8String], [(part) UTF8String]); failures++; } } while (0)
#define EXPECT(got, want) do { NSString *g_ = (got); NSString *w_ = (want); if (![g_ isEqualToString:w_]) { printf("FAIL line %d: got \"%s\" expected \"%s\"\n", __LINE__, [g_ UTF8String], [w_ UTF8String]); failures++; } } while (0)
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
    name.optional = YES;
    NSAttributeDescription *title = [[NSAttributeDescription alloc] init];
    title.name = @"title";
    title.attributeType = NSStringAttributeType;
    title.optional = YES;
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
    author.properties = @[name, books];
    book.properties = @[title, writer];
    NSManagedObjectModel *model = [[NSManagedObjectModel alloc] init];
    model.entities = @[author, book];
    return model;
}

/* A context that has not seen anything yet; registered objects keep their values across fetches. */
static NSManagedObjectContext *fresh(NSPersistentStoreCoordinator *psc) {
    NSManagedObjectContext *c = [[NSManagedObjectContext alloc] init];
    c.persistentStoreCoordinator = psc;
    return c;
}

static NSManagedObjectContext *gRoot, *gChild, *gOther, *gGrand;
static NSMutableArray *gEvents;
static NSDictionary *gLastChange;  /* userInfo of the latest change notification */

static NSString *tag(id context) {
    return context == gRoot ? @"P" : context == gChild ? @"C" : context == gOther ? @"C2" : context == gGrand ? @"G" : @"?";
}

/* The kinds of change with objects in a change notification, without touching the objects. */
static NSString *keys(NSNotification *n) {
    NSMutableArray *parts = [NSMutableArray array];
    NSDictionary *names = @{NSInsertedObjectsKey: @"ins", NSUpdatedObjectsKey: @"upd", NSDeletedObjectsKey: @"del", NSRefreshedObjectsKey: @"ref"};
    for (NSString *key in @[NSInsertedObjectsKey, NSUpdatedObjectsKey, NSDeletedObjectsKey, NSRefreshedObjectsKey]) {
        id v = [n.userInfo objectForKey:key];
        if ([v count])
            [parts addObject:[NSString stringWithFormat:@"%@=%lu", names[key], (unsigned long)[v count]]];
    }
    return [parts componentsJoinedByString:@" "];
}

static void observe(void) {
    NSDictionary *kinds = @{NSManagedObjectContextWillSaveNotification: @"WillSave",
                            NSManagedObjectContextDidSaveNotification: @"DidSave",
                            NSManagedObjectContextObjectsDidChangeNotification: @"Changed"};
    for (NSString *name in kinds) {
        NSString *label = kinds[name];
        [[NSNotificationCenter defaultCenter] addObserverForName:name object:nil queue:nil usingBlock:^(NSNotification *n) {
            NSString *k = keys(n);
            if ([label isEqualToString:@"Changed"])
                gLastChange = [n.userInfo retain];
            @synchronized (gEvents) {
                [gEvents addObject:[NSString stringWithFormat:@"%@ %@%@%@", tag(n.object), label, [k length] ? @" " : @"", k]];
            }
        }];
    }
}

static NSString *gLastEvents;
static NSString *takeEvents(void) {
    @synchronized (gEvents) {
        NSString *s = [gEvents componentsJoinedByString:@"; "];
        [gEvents removeAllObjects];
        gLastEvents = s;
        return s;
    }
}

/* Runs the block on the context's queue; objects and arrays created in it must be copied out. */
static void on(NSManagedObjectContext *c, void (^block)(void)) {
    if (c.concurrencyType == NSConfinementConcurrencyType)
        block();
    else
        [c performBlockAndWait:block];
}

static NSString *namesIn(NSManagedObjectContext *c, NSString *entity, NSString *key, NSPredicate *p, NSUInteger offset, NSUInteger limit) {
    __block NSString *result = nil;
    on(c, ^{
        NSFetchRequest *f = [NSFetchRequest fetchRequestWithEntityName:entity];
        f.predicate = p;
        f.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:key ascending:YES]];
        f.fetchOffset = offset;
        f.fetchLimit = limit;
        NSArray *objects = [c executeFetchRequest:f error:NULL];
        NSMutableArray *names = [NSMutableArray array];
        for (NSManagedObject *o in objects)
            [names addObject:[o valueForKey:key] ?: @"-"];
        result = [[names componentsJoinedByString:@","] retain];
    });
    return [result autorelease];
}

static NSString *authors(NSManagedObjectContext *c, NSPredicate *p) {
    return namesIn(c, @"Author", @"name", p, 0, 0);
}

static NSManagedObject *fetchOne(NSManagedObjectContext *c, NSString *entity, NSString *key, NSString *value) {
    __block NSManagedObject *result = nil;
    on(c, ^{
        NSFetchRequest *f = [NSFetchRequest fetchRequestWithEntityName:entity];
        f.predicate = [NSPredicate predicateWithFormat:@"%K == %@", key, value];
        result = [[[c executeFetchRequest:f error:NULL] firstObject] retain];
    });
    return [result autorelease];
}

static NSManagedObject *insert(NSManagedObjectContext *c, NSString *entity, NSString *key, NSString *value) {
    __block NSManagedObject *result = nil;
    on(c, ^{
        result = [[NSEntityDescription insertNewObjectForEntityForName:entity inManagedObjectContext:c] retain];
        [result setValue:value forKey:key];
    });
    return [result autorelease];
}

static BOOL saveIn(NSManagedObjectContext *c) {
    __block BOOL ok = NO;
    on(c, ^{ NSError *e = nil; ok = [c save:&e]; });
    return ok;
}

static id valueOf(NSManagedObjectContext *c, NSManagedObject *o, NSString *key) {
    __block id v = nil;
    on(c, ^{ v = [[o valueForKey:key] retain]; });
    return [v autorelease];
}

static void setIn(NSManagedObjectContext *c, NSManagedObject *o, NSString *key, id value) {
    on(c, ^{ [o setValue:value forKey:key]; [c processPendingChanges]; });
}

static BOOL hasChanges(NSManagedObjectContext *c) {
    __block BOOL v = NO;
    on(c, ^{ v = c.hasChanges; });
    return v;
}

static NSUInteger countOf(NSManagedObjectContext *c, NSString *which) {
    __block NSUInteger n = 0;
    on(c, ^{ n = [[c valueForKey:which] count]; });
    return n;
}

static NSString *raised(void (^block)(void)) {
    @try { block(); } @catch (NSException *e) { return [e name]; }
    return nil;
}

static void exercise(NSString *kind, NSURL *url) {
    NSPersistentStoreCoordinator *psc = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:makeModel()];
    CHECK([psc addPersistentStoreWithType:kind configuration:nil URL:url options:nil error:NULL] != nil);
    // A context that reads the store directly, to tell what has reached it.
    NSManagedObjectContext *reader = [[NSManagedObjectContext alloc] init];
    reader.persistentStoreCoordinator = psc;
    gRoot = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSPrivateQueueConcurrencyType];
    gRoot.persistentStoreCoordinator = psc;
    gChild = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSPrivateQueueConcurrencyType];

    // The parent relationship.
    CHECK(gChild.parentContext == nil);
    gChild.parentContext = gRoot;
    CHECK(gChild.parentContext == gRoot);
    CHECK(gRoot.parentContext == nil);
    CHECK(gChild.persistentStoreCoordinator == psc);
    CHECK(!gChild.automaticallyMergesChangesFromParent);
    gChild.name = @"child";
    EXPECT(gChild.name, @"child");
    CHECK([raised(^{ gOther = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSPrivateQueueConcurrencyType]; gOther.parentContext = nil; }) isEqualToString:NSInvalidArgumentException]);
    CHECK([raised(^{ gChild.persistentStoreCoordinator = psc; }) isEqualToString:NSInternalInconsistencyException]);
    CHECK([raised(^{ reader.parentContext = gRoot; }) isEqualToString:NSInternalInconsistencyException]);

    // A child's insert stays in the child until it is saved, then moves into the parent only.
    NSManagedObject *one = insert(gChild, @"Author", @"name", @"one");
    on(gChild, ^{ [gChild processPendingChanges]; });
    CHECK(hasChanges(gChild));
    CHECK(!hasChanges(gRoot));
    EXPECT(authors(gRoot, nil), @"");
    EXPECT(authors(gChild, nil), @"one");
    takeEvents();
    CHECK(saveIn(gChild));
    EXPECT(takeEvents(), @"C WillSave; P Changed ins=1; C DidSave ins=1");
    CHECK([gLastChange objectForKey:NSUpdatedObjectsKey] == nil && [gLastChange objectForKey:NSDeletedObjectsKey] == nil);
    CHECK(!hasChanges(gChild));
    CHECK(hasChanges(gRoot));
    CHECK(countOf(gRoot, @"insertedObjects") == 1);
    EXPECT(authors(gRoot, nil), @"one");
    EXPECT(authors(fresh(psc), nil), @"");
    EXPECT(authors(gChild, [NSPredicate predicateWithFormat:@"name BEGINSWITH 'o'"]), @"one");

    // The parent's save writes it to the store.
    CHECK(saveIn(gRoot));
    EXPECT(takeEvents(), @"P WillSave; P DidSave ins=1");
    EXPECT(authors(fresh(psc), nil), @"one");
    CHECK(!hasChanges(gRoot));

    // Updates: the child sees its own pending value in fetches, the parent only after the save.
    setIn(gChild, one, @"name", @"uno");
    EXPECT(authors(gChild, [NSPredicate predicateWithFormat:@"name == 'uno'"]), @"uno");
    EXPECT(authors(gChild, [NSPredicate predicateWithFormat:@"name == 'one'"]), @"");
    EXPECT(authors(gRoot, nil), @"one");
    takeEvents();
    CHECK(saveIn(gChild));
    EXPECT(takeEvents(), @"C WillSave; P Changed upd=1; C DidSave upd=1");
    EXPECT(authors(gRoot, nil), @"uno");
    CHECK(countOf(gRoot, @"updatedObjects") == 1);
    EXPECT(authors(fresh(psc), nil), @"one");
    CHECK(saveIn(gRoot));
    EXPECT(authors(fresh(psc), nil), @"uno");
    takeEvents();

    // Unsaved changes of the parent are visible to a child's fetch; deletes move up too.
    insert(gRoot, @"Author", @"name", @"two");
    EXPECT(authors(gChild, nil), @"two,uno");
    on(gChild, ^{ [gChild deleteObject:fetchOne(gChild, @"Author", @"name", @"uno")]; });
    EXPECT(authors(gChild, nil), @"two");
    CHECK(saveIn(gChild));
    CHECK(countOf(gRoot, @"deletedObjects") == 1);
    EXPECT(authors(gRoot, nil), @"two");
    EXPECT(authors(fresh(psc), nil), @"uno");
    CHECK(saveIn(gRoot));
    EXPECT(authors(fresh(psc), nil), @"two");
    EXPECT(authors(gChild, nil), @"two");
    takeEvents();

    // Fetches through the nesting: predicates, sort, offset and limit.
    for (NSString *n in @[@"alpha", @"Beta", @"gamma", @"delta"])
        insert(gRoot, @"Author", @"name", n);
    CHECK(saveIn(gRoot));
    EXPECT(authors(gChild, [NSPredicate predicateWithFormat:@"name BEGINSWITH[c] 'b'"]), @"Beta");
    EXPECT(authors(gChild, [NSPredicate predicateWithFormat:@"name IN {'gamma', 'two', 'zzz'}"]), @"gamma,two");
    EXPECT(namesIn(gChild, @"Author", @"name", nil, 1, 2), @"alpha,delta");
    EXPECT(authors(gChild, [NSPredicate predicateWithFormat:@"NOT (name LIKE[c] '*A')"]), @"two");

    // Relationships created in the child reach the parent and the store.
    NSManagedObject *gammaChild = fetchOne(gChild, @"Author", @"name", @"gamma");
    NSManagedObject *book = insert(gChild, @"Book", @"title", @"Red");
    on(gChild, ^{ [book setValue:gammaChild forKey:@"writer"]; });
    CHECK(saveIn(gChild));
    NSManagedObject *gammaRoot = fetchOne(gRoot, @"Author", @"name", @"gamma");
    __block NSUInteger parentBooks = 0;
    on(gRoot, ^{ parentBooks = [[gammaRoot valueForKey:@"books"] count]; });
    CHECK(parentBooks == 1);
    EXPECT(namesIn(gRoot, @"Book", @"title", [NSPredicate predicateWithFormat:@"writer.name == 'gamma'"], 0, 0), @"Red");
    EXPECT(namesIn(fresh(psc), @"Book", @"title", nil, 0, 0), @"");
    CHECK(saveIn(gRoot));
    EXPECT(namesIn(fresh(psc), @"Book", @"title", [NSPredicate predicateWithFormat:@"writer.name == 'gamma'"], 0, 0), @"Red");
    EXPECT(namesIn(gChild, @"Book", @"title", [NSPredicate predicateWithFormat:@"writer.name == 'gamma'"], 0, 0), @"Red");
    takeEvents();

    // A grandchild's changes go up one level per save.
    gGrand = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSPrivateQueueConcurrencyType];
    gGrand.parentContext = gChild;
    CHECK(gGrand.persistentStoreCoordinator == psc);
    insert(gGrand, @"Author", @"name", @"grand");
    CHECK(saveIn(gGrand));
    EXPECT(authors(gChild, [NSPredicate predicateWithFormat:@"name == 'grand'"]), @"grand");
    EXPECT(authors(gRoot, [NSPredicate predicateWithFormat:@"name == 'grand'"]), @"");
    CHECK(saveIn(gChild));
    EXPECT(authors(gRoot, [NSPredicate predicateWithFormat:@"name == 'grand'"]), @"grand");
    EXPECT(authors(fresh(psc), [NSPredicate predicateWithFormat:@"name == 'grand'"]), @"");
    CHECK(saveIn(gRoot));
    EXPECT(authors(fresh(psc), [NSPredicate predicateWithFormat:@"name == 'grand'"]), @"grand");
    takeEvents();

    // automaticallyMergesChangesFromParent: after the parent's save the child sees the saved
    // changes of objects it holds (as refreshed) and the inserted ones; unsaved parent changes
    // are not merged. A child without the option keeps its values.
    gOther = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSPrivateQueueConcurrencyType];
    gOther.parentContext = gRoot;
    gOther.automaticallyMergesChangesFromParent = YES;
    CHECK(gOther.automaticallyMergesChangesFromParent);
    NSManagedObject *heldAuto = fetchOne(gOther, @"Author", @"name", @"alpha");
    NSManagedObject *heldPlain = fetchOne(gChild, @"Author", @"name", @"alpha");
    // Objects are faults until a value is read; read one so the object holds its values.
    CHECK([valueOf(gOther, heldAuto, @"name") isEqualToString:@"alpha"]);
    CHECK([valueOf(gChild, heldPlain, @"name") isEqualToString:@"alpha"]);
    NSManagedObject *alphaRoot = fetchOne(gRoot, @"Author", @"name", @"alpha");
    setIn(gRoot, alphaRoot, @"name", @"alef");
    EXPECT(valueOf(gOther, heldAuto, @"name"), @"alpha");
    takeEvents();
    CHECK(saveIn(gRoot));
    EXPECT(valueOf(gOther, heldAuto, @"name"), @"alef");
    EXPECT(valueOf(gChild, heldPlain, @"name"), @"alpha");
    NSString *events = takeEvents();
    HAS(events, @"P DidSave upd=1");
    HAS(events, @"C2 Changed ref=1");
    CHECK(![events containsString:@" C Changed"] && ![events hasPrefix:@"C Changed"]);
    insert(gRoot, @"Author", @"name", @"epsilon");
    CHECK(saveIn(gRoot));
    on(gOther, ^{});  // the merge runs asynchronously on the child's queue
    HAS(takeEvents(), @"C2 Changed ins=1");
    EXPECT(authors(gOther, [NSPredicate predicateWithFormat:@"name == 'epsilon'"]), @"epsilon");
    CHECK(!hasChanges(gOther));
}

int main(int argc, char **argv) {
    @autoreleasepool {
        gEvents = [NSMutableArray array];
        observe();
        NSString *base = argc > 1 ? [NSString stringWithUTF8String:argv[1]] : NSTemporaryDirectory();
        NSString *dir = [base stringByAppendingPathComponent:[NSString stringWithFormat:@"child-context-%d", getpid()]];
        [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:NULL];
        for (NSString *kind in @[NSSQLiteStoreType, NSInMemoryStoreType]) {
            NSURL *url = [kind isEqualToString:NSSQLiteStoreType] ? [NSURL fileURLWithPath:[dir stringByAppendingPathComponent:@"c.sqlite"]] : nil;
            printf("-- %s\n", [kind UTF8String]);
            exercise(kind, url);
        }
        [[NSFileManager defaultManager] removeItemAtPath:dir error:NULL];
    }
    if (failures) { printf("FAILURES: %d\n", failures); return 1; }
    printf("PASS_CHILD_CONTEXT\n");
    return 0;
}
