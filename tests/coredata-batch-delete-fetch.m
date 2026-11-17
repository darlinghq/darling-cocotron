/*
 * Copyright (C) 2026 Lubos Dolezel
 *
 * NSBatchDeleteRequest created from a fetch request: it deletes the rows the fetch request
 * selects and reports them according to the result type. Public API only; the expectations
 * hold on macOS. An optional argument names the directory for the store files.
 */
#import <Foundation/Foundation.h>
#import <CoreData/CoreData.h>
#include <stdio.h>
#include <unistd.h>

static int failures;
#define CHECK(c) do { if (!(c)) { printf("FAIL line %d: %s\n", __LINE__, #c); failures++; } } while (0)

static NSManagedObjectModel *makeModel(void) {
    NSEntityDescription *item = [[NSEntityDescription alloc] init];
    item.name = @"Item";
    item.managedObjectClassName = @"NSManagedObject";
    NSAttributeDescription *title = [[NSAttributeDescription alloc] init];
    title.name = @"title";
    title.attributeType = NSStringAttributeType;
    title.optional = YES;
    NSAttributeDescription *kind = [[NSAttributeDescription alloc] init];
    kind.name = @"kind";
    kind.attributeType = NSStringAttributeType;
    kind.optional = YES;
    NSAttributeDescription *weight = [[NSAttributeDescription alloc] init];
    weight.name = @"weight";
    weight.attributeType = NSInteger32AttributeType;
    weight.optional = YES;
    item.properties = @[title, kind, weight];
    NSManagedObjectModel *model = [[NSManagedObjectModel alloc] init];
    model.entities = @[item];
    return model;
}

static NSManagedObjectContext *openContext(NSManagedObjectModel *model, NSURL *url) {
    NSPersistentStoreCoordinator *psc = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:model];
    if (![psc addPersistentStoreWithType:NSSQLiteStoreType configuration:nil URL:url options:nil error:NULL])
        return nil;
    NSManagedObjectContext *context = [[NSManagedObjectContext alloc] init];
    [context setPersistentStoreCoordinator:psc];
    return context;
}

static NSString *titles(NSManagedObjectModel *model, NSURL *url) {
    NSManagedObjectContext *context = openContext(model, url);
    NSFetchRequest *request = [NSFetchRequest fetchRequestWithEntityName:@"Item"];
    request.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:@"title" ascending:YES]];
    return [[[context executeFetchRequest:request error:NULL] valueForKey:@"title"] componentsJoinedByString:@","];
}

static void seed(NSManagedObjectContext *context) {
    NSArray *rows = @[@[@"a", @"x", @1], @[@"b", @"y", @2], @[@"c", @"x", @3], @[@"d", @"x", @4], @[@"e", @"z", @5]];
    for (NSArray *row in rows) {
        NSManagedObject *o = [NSEntityDescription insertNewObjectForEntityForName:@"Item" inManagedObjectContext:context];
        [o setValue:row[0] forKey:@"title"];
        [o setValue:row[1] forKey:@"kind"];
        [o setValue:row[2] forKey:@"weight"];
    }
    CHECK([context save:NULL]);
}

int main(int argc, char **argv) {
    @autoreleasepool {
        NSString *base = argc > 1 ? [NSString stringWithUTF8String:argv[1]] : NSTemporaryDirectory();
        NSString *dir = [base stringByAppendingPathComponent:[NSString stringWithFormat:@"batch-delete-fetch-%d", getpid()]];
        [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:NULL];
        NSURL *url = [NSURL fileURLWithPath:[dir stringByAppendingPathComponent:@"items.sqlite"]];
        NSManagedObjectModel *model = makeModel();
        NSManagedObjectContext *context = openContext(model, url);
        seed(context);
        NSError *error = nil;

        // Count result with a predicate.
        NSFetchRequest *fetch = [NSFetchRequest fetchRequestWithEntityName:@"Item"];
        fetch.predicate = [NSPredicate predicateWithFormat:@"kind == %@", @"x"];
        NSBatchDeleteRequest *delete = [[NSBatchDeleteRequest alloc] initWithFetchRequest:fetch];
        delete.resultType = NSBatchDeleteResultTypeCount;
        NSBatchDeleteResult *result = (NSBatchDeleteResult *)[context executeRequest:delete error:&error];
        CHECK(result != nil);
        CHECK([result.result isEqual:@3]);
        CHECK(result.resultType == NSBatchDeleteResultTypeCount);
        CHECK([titles(model, url) isEqualToString:@"b,e"]);

        // Object IDs of the deleted rows, with a comparison and an IN predicate.
        NSManagedObjectContext *reader = openContext(model, url);
        NSFetchRequest *all = [NSFetchRequest fetchRequestWithEntityName:@"Item"];
        all.predicate = [NSPredicate predicateWithFormat:@"weight > 1 AND title IN %@", @[@"b", @"q"]];
        NSArray *expected = [[reader executeFetchRequest:all error:NULL] valueForKey:@"objectID"];
        CHECK([expected count] == 1);
        NSFetchRequest *byIDs = [NSFetchRequest fetchRequestWithEntityName:@"Item"];
        byIDs.predicate = [NSPredicate predicateWithFormat:@"weight > 1 AND title IN %@", @[@"b", @"q"]];
        delete = [[NSBatchDeleteRequest alloc] initWithFetchRequest:byIDs];
        delete.resultType = NSBatchDeleteResultTypeObjectIDs;
        result = (NSBatchDeleteResult *)[context executeRequest:delete error:&error];
        CHECK(result != nil);
        // The IDs come from another coordinator than the expected ones, so they compare by URI.
        NSSet *deletedURIs = [NSSet setWithArray:[result.result valueForKeyPath:@"URIRepresentation.absoluteString"]];
        NSSet *expectedURIs = [NSSet setWithArray:[expected valueForKeyPath:@"URIRepresentation.absoluteString"]];
        CHECK([deletedURIs isEqual:expectedURIs]);
        CHECK([titles(model, url) isEqualToString:@"e"]);

        // A predicate that selects nothing deletes nothing; status only reports success.
        fetch = [NSFetchRequest fetchRequestWithEntityName:@"Item"];
        fetch.predicate = [NSPredicate predicateWithFormat:@"title BEGINSWITH[c] %@", @"Q"];
        delete = [[NSBatchDeleteRequest alloc] initWithFetchRequest:fetch];
        delete.resultType = NSBatchDeleteResultTypeCount;
        result = (NSBatchDeleteResult *)[context executeRequest:delete error:&error];
        CHECK(result != nil && [result.result isEqual:@0]);
        delete = [[NSBatchDeleteRequest alloc] initWithFetchRequest:fetch];
        delete.resultType = NSBatchDeleteResultTypeStatusOnly;
        result = (NSBatchDeleteResult *)[context executeRequest:delete error:&error];
        CHECK(result != nil && [result.result isEqual:@YES]);
        CHECK([titles(model, url) isEqualToString:@"e"]);

        // Without a predicate every row of the entity goes.
        seed(context);
        CHECK([titles(model, url) isEqualToString:@"a,b,c,d,e,e"]);
        delete = [[NSBatchDeleteRequest alloc] initWithFetchRequest:[NSFetchRequest fetchRequestWithEntityName:@"Item"]];
        delete.resultType = NSBatchDeleteResultTypeCount;
        result = (NSBatchDeleteResult *)[context executeRequest:delete error:&error];
        CHECK(result != nil && [result.result isEqual:@6]);
        CHECK([titles(model, url) isEqualToString:@""]);

        // The fetch request's own settings that do not select objects do not matter: another result
        // type, a batch size, no pending changes. Sorting and a limit select the first rows.
        seed(context);
        NSFetchRequest *firstTwo = [NSFetchRequest fetchRequestWithEntityName:@"Item"];
        firstTwo.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:@"title" ascending:YES]];
        firstTwo.fetchLimit = 2;
        firstTwo.fetchBatchSize = 1;
        firstTwo.includesPendingChanges = NO;
        firstTwo.resultType = NSManagedObjectIDResultType;
        delete = [[NSBatchDeleteRequest alloc] initWithFetchRequest:firstTwo];
        delete.resultType = NSBatchDeleteResultTypeCount;
        result = (NSBatchDeleteResult *)[context executeRequest:delete error:&error];
        CHECK(result != nil && [result.result isEqual:@2]);
        CHECK([titles(model, url) isEqualToString:@"c,d,e"]);

        [[NSFileManager defaultManager] removeItemAtPath:dir error:NULL];
    }
    if (failures) { printf("FAILURES: %d\n", failures); return 1; }
    printf("PASS_BATCH_DELETE_FETCH\n");
    return 0;
}
