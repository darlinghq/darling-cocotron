/*
 * Copyright (C) 2026 Lubos Dolezel
 *
 * Batch delete and batch update requests executed against an SQLite store through
 * -[NSManagedObjectContext executeRequest:error:]. Public API only.
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
    item.properties = @[title, kind];
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

static NSArray *titles(NSManagedObjectContext *context) {
    NSFetchRequest *request = [NSFetchRequest fetchRequestWithEntityName:@"Item"];
    request.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:@"title" ascending:YES]];
    return [[context executeFetchRequest:request error:NULL] valueForKey:@"title"];
}

int main(void) {
    @autoreleasepool {
        NSString *dir = [NSTemporaryDirectory() stringByAppendingPathComponent:
            [NSString stringWithFormat:@"batch-exec-%d", getpid()]];
        [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:NULL];
        NSURL *url = [NSURL fileURLWithPath:[dir stringByAppendingPathComponent:@"items.sqlite"]];
        NSManagedObjectModel *model = makeModel();
        NSManagedObjectContext *seed = openContext(model, url);
        CHECK(seed != nil);
        NSArray *rows = @[@[@"a", @"x"], @[@"b", @"y"], @[@"c", @"x"], @[@"d", @"x"]];
        for (NSArray *row in rows) {
            NSManagedObject *o = [NSEntityDescription insertNewObjectForEntityForName:@"Item" inManagedObjectContext:seed];
            [o setValue:row[0] forKey:@"title"];
            [o setValue:row[1] forKey:@"kind"];
        }
        CHECK([seed save:NULL]);

        /* batch update changes the stored rows and reports their count */
        NSManagedObjectContext *context = openContext(model, url);
        NSBatchUpdateRequest *update = [NSBatchUpdateRequest batchUpdateRequestWithEntityName:@"Item"];
        update.predicate = [NSPredicate predicateWithFormat:@"kind == %@", @"y"];
        update.propertiesToUpdate = @{@"kind": @"z"};
        update.resultType = NSUpdatedObjectsCountResultType;
        NSError *error = nil;
        NSBatchUpdateResult *updateResult = (NSBatchUpdateResult *)[context executeRequest:update error:&error];
        CHECK(updateResult != nil && [updateResult.result isEqual:@1]);
        CHECK([titles(openContext(model, url)) count] == 4);

        /* batch delete removes the matching rows and reports their count */
        NSFetchRequest *xs = [NSFetchRequest fetchRequestWithEntityName:@"Item"];
        xs.predicate = [NSPredicate predicateWithFormat:@"kind == %@", @"x"];
        NSMutableArray *ids = [NSMutableArray array];
        for (NSManagedObject *o in [context executeFetchRequest:xs error:NULL])
            [ids addObject:[o objectID]];
        CHECK([ids count] == 3);
        NSBatchDeleteRequest *delete = [[NSBatchDeleteRequest alloc] initWithObjectIDs:ids];
        delete.resultType = NSBatchDeleteResultTypeCount;
        NSBatchDeleteResult *deleteResult = (NSBatchDeleteResult *)[context executeRequest:delete error:&error];
        CHECK(deleteResult != nil && [deleteResult.result isEqual:@3]);
        NSArray *left = titles(openContext(model, url));
        CHECK([left count] == 1 && [[left firstObject] isEqual:@"b"]);

        [[NSFileManager defaultManager] removeItemAtPath:dir error:NULL];
    }
    if (failures)
        return 1;
    puts("PASS_COREDATA_BATCH_EXECUTION");
    return 0;
}
