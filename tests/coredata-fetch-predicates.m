/*
 * Copyright (C) 2026 Lubos Dolezel
 *
 * Fetch requests with the common NSPredicate forms against SQLite and in-memory stores:
 * comparisons, compound predicates, IN, string operators with the [cd] options, key paths
 * through to-one relationships, self comparisons, offsets and limits. Public API only; the
 * expectations hold on macOS. An optional argument names the directory for the store files.
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

static NSManagedObject *make(NSManagedObjectContext *c, NSString *entity, NSDictionary *values) {
    NSManagedObject *o = [NSEntityDescription insertNewObjectForEntityForName:entity inManagedObjectContext:c];
    for (NSString *k in values)
        [o setValue:values[k] forKey:k];
    return o;
}

static NSManagedObjectContext *gContext;
static NSString *gKind;
/* SQL stores treat a comparison with a nil value as unknown, so such rows match neither a predicate nor its negation. */
#define SQL_OR_MEM(sql, mem) ([gKind isEqualToString:@"sqlite"] ? (sql) : (mem))

static void report(int line, NSString *predicate, NSString *got, NSString *expected) {
    printf("FAIL %s line %d: %s -> %s (expected %s)\n", [gKind UTF8String], line, [predicate UTF8String],
           [got UTF8String], [expected UTF8String]);
    failures++;
}

/* Fetches the entity with the predicate, sorted by the key, and joins the names of the results. */
static NSString *run(NSString *entity, NSString *sortKey, NSString *show, NSPredicate *p, NSUInteger offset, NSUInteger limit) {
    NSFetchRequest *request = [NSFetchRequest fetchRequestWithEntityName:entity];
    request.predicate = p;
    request.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:sortKey ascending:YES]];
    request.fetchOffset = offset;
    request.fetchLimit = limit;
    NSError *error = nil;
    NSArray *result = [gContext executeFetchRequest:request error:&error];
    if (!result)
        return [NSString stringWithFormat:@"ERROR %ld", (long)error.code];
    NSMutableArray *names = [NSMutableArray array];
    for (NSManagedObject *o in result)
        [names addObject:[o valueForKey:show] ?: @"-"];
    return [names componentsJoinedByString:@","];
}

#define AUTH(fmt, expect, ...) do { NSString *got = run(@"Author", @"born", @"name", [NSPredicate predicateWithFormat:fmt, ##__VA_ARGS__], 0, 0); \
    if (![got isEqualToString:expect]) report(__LINE__, fmt, got, expect); } while (0)
#define BOOK(fmt, expect, ...) do { NSString *got = run(@"Book", @"pages", @"pages", [NSPredicate predicateWithFormat:fmt, ##__VA_ARGS__], 0, 0); \
    if (![got isEqualToString:expect]) report(__LINE__, fmt, got, expect); } while (0)

static void exercise(void) {
    NSManagedObject *alice = make(gContext, @"Author", @{@"name": @"Alice", @"born": @1970});
    make(gContext, @"Author", @{@"name": @"alina", @"born": @1980});
    NSManagedObject *bob = make(gContext, @"Author", @{@"name": @"Bob", @"born": @1960});
    make(gContext, @"Author", @{@"name": @"Carol", @"born": @1950});
    make(gContext, @"Author", @{@"name": @"Dave", @"born": @1990});
    make(gContext, @"Author", @{@"name": @"Émile", @"born": @2000});
    make(gContext, @"Book", @{@"title": @"Red", @"pages": @100, @"writer": alice});
    make(gContext, @"Book", @{@"title": @"Blue", @"pages": @200, @"writer": bob});
    make(gContext, @"Book", @{@"title": @"Green", @"pages": @300, @"writer": alice});
    make(gContext, @"Book", @{@"title": @"Grey", @"pages": @400});
    make(gContext, @"Book", @{@"pages": @500});
    NSError *error = nil;
    CHECK([gContext save:&error]);

    // Comparisons.
    AUTH(@"born > 1970", @"alina,Dave,Émile");
    AUTH(@"born >= 1970", @"Alice,alina,Dave,Émile");
    AUTH(@"born < 1960", @"Carol");
    AUTH(@"born <= 1960", @"Carol,Bob");
    AUTH(@"born == 1960", @"Bob");
    AUTH(@"born != 1960", @"Carol,Alice,alina,Dave,Émile");
    AUTH(@"name == 'Alice'", @"Alice");
    AUTH(@"name == 'alice'", @"");
    AUTH(@"name == 'alice'", @"", 0);
    AUTH(@"name ==[c] 'alice'", @"Alice");
    AUTH(@"name != 'Alice'", @"Carol,Bob,alina,Dave,Émile");
    AUTH(@"name > 'B'", @"Carol,Bob,alina,Dave,Émile");
    AUTH(@"born BETWEEN {1955, 1975}", @"Bob,Alice");
    AUTH(@"name == %@", @"Bob", @"Bob");
    AUTH(@"born == %d", @"Dave", 1990);

    // Compound predicates.
    AUTH(@"born > 1950 AND name BEGINSWITH 'A'", @"Alice");
    AUTH(@"born > 1980 OR name == 'Bob'", @"Bob,Dave,Émile");
    AUTH(@"NOT (born > 1960)", @"Carol,Bob");
    AUTH(@"NOT name BEGINSWITH 'A'", @"Carol,Bob,alina,Dave,Émile");
    AUTH(@"(born > 1950 AND born < 1990) AND NOT (name == 'Bob')", @"Alice,alina");
    AUTH(@"TRUEPREDICATE", @"Carol,Bob,Alice,alina,Dave,Émile");
    AUTH(@"FALSEPREDICATE", @"");

    // IN.
    AUTH(@"born IN {1960, 1970}", @"Bob,Alice");
    AUTH(@"name IN {'Bob', 'Carol', 'Zed'}", @"Carol,Bob");
    AUTH(@"name IN %@", @"Carol,Bob", @[@"Bob", @"Carol"]);
    AUTH(@"NOT (name IN {'Bob', 'Carol'})", @"Alice,alina,Dave,Émile");

    // String operators.
    AUTH(@"name BEGINSWITH 'Al'", @"Alice");
    AUTH(@"name BEGINSWITH 'al'", @"alina");
    AUTH(@"name BEGINSWITH[c] 'al'", @"Alice,alina");
    AUTH(@"name BEGINSWITH[cd] 'emi'", @"Émile");
    AUTH(@"name BEGINSWITH[d] 'Emi'", @"Émile");
    AUTH(@"name BEGINSWITH 'Emi'", @"");
    AUTH(@"name ENDSWITH 'e'", @"Alice,Dave,Émile");
    AUTH(@"name CONTAINS 'ar'", @"Carol");
    AUTH(@"name CONTAINS 'ro'", @"Carol");
    AUTH(@"name CONTAINS[c] 'IL'", @"Émile");
    AUTH(@"name CONTAINS[cd] 'EMI'", @"Émile");
    AUTH(@"name LIKE '?ob'", @"Bob");
    AUTH(@"name LIKE 'A*'", @"Alice");
    AUTH(@"name LIKE[c] 'A*'", @"Alice,alina");
    AUTH(@"name LIKE[c] '*LI?E'", @"Alice");
    AUTH(@"name LIKE[cd] 'emil?'", @"Émile");
    AUTH(@"name MATCHES '[A-C].*'", @"Carol,Bob,Alice");
    AUTH(@"name BEGINSWITH ''", @"");

    // Key paths through to-one relationships, nil and object comparisons.
    BOOK(@"writer.name == 'Alice'", @"100,300");
    BOOK(@"writer.born > 1965", @"100,300");
    BOOK(@"writer.born < 1965", @"200");
    BOOK(@"writer.name BEGINSWITH[c] 'b'", @"200");
    BOOK(@"writer.name IN {'Alice', 'Bob'}", @"100,200,300");
    BOOK(@"writer.name == 'Alice' AND pages > 100", @"300");
    BOOK(@"writer == nil", @"400,500");
    BOOK(@"writer != nil", @"100,200,300");
    BOOK(@"title == nil", @"500");
    BOOK(@"title != nil", @"100,200,300,400");
    BOOK(@"title != 'Red'", SQL_OR_MEM(@"200,300,400", @"200,300,400,500"));
    BOOK(@"NOT (title == 'Red')", SQL_OR_MEM(@"200,300,400", @"200,300,400,500"));
    BOOK(@"NOT (title BEGINSWITH 'R')", SQL_OR_MEM(@"200,300,400,500", @"200,300,400,500"));
    BOOK(@"title IN {'Red'}", SQL_OR_MEM(@"100", @"100"));
    BOOK(@"NOT (title IN {'Red'})", SQL_OR_MEM(@"200,300,400", @"200,300,400,500"));
    BOOK(@"title CONTAINS 'e'", SQL_OR_MEM(@"100,200,300,400", @"100,200,300,400"));
    BOOK(@"writer.name != 'Bob'", SQL_OR_MEM(@"100,300", @"100,300,400,500"));
    BOOK(@"NOT (writer.name == 'Bob')", SQL_OR_MEM(@"100,300", @"100,300,400,500"));
    BOOK(@"title == 'Red' OR title != 'Red'", SQL_OR_MEM(@"100,200,300,400", @"100,200,300,400,500"));
    BOOK(@"title == 'Red' OR NOT (title != 'Red')", SQL_OR_MEM(@"100", @"100"));
    BOOK(@"writer == %@", @"100,300", alice);
    BOOK(@"writer != %@", SQL_OR_MEM(@"200", @"200,400,500"), alice);
    BOOK(@"writer IN %@", @"100,200,300", @[alice, bob]);
    BOOK(@"NOT (writer == %@)", SQL_OR_MEM(@"200", @"200,400,500"), alice);

    NSString *got = run(@"Author", @"born", @"name", [NSPredicate predicateWithFormat:@"SELF == %@", bob], 0, 0);
    CHECK([got isEqualToString:@"Bob"]);
    got = run(@"Author", @"born", @"name", [NSPredicate predicateWithFormat:@"SELF != %@", bob], 0, 0);
    CHECK([got isEqualToString:@"Carol,Alice,alina,Dave,Émile"]);
    got = run(@"Author", @"born", @"name", [NSPredicate predicateWithFormat:@"SELF IN %@", @[alice, bob]], 0, 0);
    CHECK([got isEqualToString:@"Bob,Alice"]);
    got = run(@"Author", @"born", @"name", [NSPredicate predicateWithFormat:@"SELF == %@", alice.objectID], 0, 0);
    CHECK([got isEqualToString:@"Alice"]);

    // Offset and limit apply after filtering and sorting.
    got = run(@"Author", @"born", @"name", [NSPredicate predicateWithFormat:@"born > 1950"], 1, 2);
    CHECK([got isEqualToString:@"Alice,alina"]);
    got = run(@"Author", @"born", @"name", nil, 4, 0);
    CHECK([got isEqualToString:@"Dave,Émile"]);

    // Pending changes take part in the result.
    make(gContext, @"Author", @{@"name": @"Zed", @"born": @1955});
    AUTH(@"born > 1952 AND born < 1958", @"Zed");
    [alice setValue:@1900 forKey:@"born"];
    AUTH(@"born < 1960", @"Alice,Carol,Zed");
    [gContext deleteObject:bob];
    AUTH(@"name == 'Bob'", @"");

    // The values are bound, never interpreted.
    AUTH(@"name == %@", @"", @"x' OR '1'='1");
    AUTH(@"name LIKE %@", @"", @"%");
    AUTH(@"name == %@", @"", @"Carol\\");

    // A predicate on an unknown key raises on both store types.
    NSFetchRequest *bad = [NSFetchRequest fetchRequestWithEntityName:@"Author"];
    bad.predicate = [NSPredicate predicateWithFormat:@"nonexistent == 1"];
    NSString *raised = nil;
    @try { [gContext executeFetchRequest:bad error:NULL]; } @catch (NSException *e) { raised = e.name; }
    CHECK(raised != nil);
}

int main(int argc, char **argv) {
    @autoreleasepool {
        NSString *base = argc > 1 ? [NSString stringWithUTF8String:argv[1]] : NSTemporaryDirectory();
        NSString *dir = [base stringByAppendingPathComponent:[NSString stringWithFormat:@"fetch-pred-%d", getpid()]];
        [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:NULL];
        NSDictionary *kinds = @{@"sqlite": NSSQLiteStoreType, @"memory": NSInMemoryStoreType};
        for (NSString *kind in @[@"sqlite", @"memory"]) {
            gKind = kind;
            NSURL *url = [kind isEqualToString:@"sqlite"] ? [NSURL fileURLWithPath:[dir stringByAppendingPathComponent:@"s.sqlite"]] : nil;
            NSPersistentStoreCoordinator *psc = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:makeModel()];
            NSError *error = nil;
            CHECK([psc addPersistentStoreWithType:kinds[kind] configuration:nil URL:url options:nil error:&error]);
            gContext = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSMainQueueConcurrencyType];
            gContext.persistentStoreCoordinator = psc;
            exercise();
        }
        [[NSFileManager defaultManager] removeItemAtPath:dir error:NULL];
    }
    if (failures) { printf("FAILURES: %d\n", failures); return 1; }
    printf("PASS_FETCH_PREDICATES\n");
    return 0;
}
