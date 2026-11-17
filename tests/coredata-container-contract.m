/*
 * Copyright (C) 2026 Lubos Dolezel
 *
 * NSPersistentContainer, NSPersistentStoreDescription and store-type behaviour
 * that is visible through the public API. Every expectation was observed on
 * macOS 10.14 and macOS 26 with the same program.
 */
#import <Foundation/Foundation.h>
#import <CoreData/CoreData.h>
#import <dispatch/dispatch.h>
#include <stdio.h>

static int failures;
#define CHECK(c) do { if (!(c)) { printf("FAIL line %d: %s\n", __LINE__, #c); failures++; } } while (0)

static NSString *raiseName(void (^block)(void)) {
    @try { block(); } @catch (NSException *e) { return [e name]; }
    return nil;
}

int main(int argc, char **argv) {
    @autoreleasepool {
        NSString *dir = [NSTemporaryDirectory() stringByAppendingPathComponent:
            [NSString stringWithFormat:@"cd-contract-%d", getpid()]];
        [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:NULL];

        /* store type names */
        CHECK([NSInMemoryStoreType isEqual:@"InMemory"]);
        CHECK([NSXMLStoreType isEqual:@"XML"] && [NSSQLiteStoreType isEqual:@"SQLite"] && [NSBinaryStoreType isEqual:@"Binary"]);

        /* coordinator argument validation */
        NSManagedObjectModel *model = [[[NSManagedObjectModel alloc] init] autorelease];
        NSPersistentStoreCoordinator *psc = [[[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:model] autorelease];
        NSURL *fileURL = [NSURL fileURLWithPath:[dir stringByAppendingPathComponent:@"s"]];
        NSURL *webURL = [NSURL URLWithString:@"https://store.example/s"];
        CHECK([raiseName(^{ [psc addPersistentStoreWithType:@"Bogus" configuration:nil URL:fileURL options:nil error:NULL]; })
              isEqual:NSInvalidArgumentException]);
        CHECK([raiseName(^{ [psc addPersistentStoreWithType:NSXMLStoreType configuration:nil URL:webURL options:nil error:NULL]; })
              isEqual:NSInvalidArgumentException]);
        CHECK([raiseName(^{ [psc addPersistentStoreWithType:NSSQLiteStoreType configuration:nil URL:webURL options:nil error:NULL]; })
              isEqual:NSInvalidArgumentException]);
        NSError *error = nil;
        CHECK([psc addPersistentStoreWithType:NSInMemoryStoreType configuration:nil URL:webURL options:nil error:&error] != nil);
        NSError *inferError = nil;
        CHECK([psc addPersistentStoreWithType:nil configuration:nil URL:[NSURL fileURLWithPath:[dir stringByAppendingPathComponent:@"absent"]]
                                      options:nil error:&inferError] == nil);
        CHECK([inferError code] == 134000 && [[inferError domain] isEqual:@"NSCocoaErrorDomain"]);

        /* store description defaults, options and copying */
        NSPersistentStoreDescription *blank = [[[NSPersistentStoreDescription alloc] init] autorelease];
        CHECK([[blank.URL path] isEqual:@"/dev/null"] && [blank.type isEqual:NSSQLiteStoreType]);
        NSPersistentStoreDescription *d = [NSPersistentStoreDescription persistentStoreDescriptionWithURL:fileURL];
        CHECK(d.timeout == 240 && [d.sqlitePragmas count] == 0);
        CHECK(d.shouldMigrateStoreAutomatically && d.shouldInferMappingModelAutomatically && !d.isReadOnly);
        CHECK([d.options count] == 2);
        [d setValue:@"WAL" forPragmaNamed:@"journal_mode"];
        CHECK([[d.sqlitePragmas objectForKey:@"journal_mode"] isEqual:@"WAL"]);
        CHECK([[d.options objectForKey:NSSQLitePragmasOption] isEqual:d.sqlitePragmas]);
        d.timeout = 7;
        CHECK([[d.options objectForKey:NSPersistentStoreTimeoutOption] isEqual:@7]);
        NSPersistentStoreDescription *copy = [[d copy] autorelease];
        CHECK(copy != d && [copy isEqual:d] && [copy.URL isEqual:d.URL] && copy.timeout == 7);
        copy.readOnly = YES;
        CHECK(![copy isEqual:d]);

        /* relationship cardinality is a 32-bit quantity */
        NSRelationshipDescription *relationship = [[[NSRelationshipDescription alloc] init] autorelease];
        relationship.maxCount = (NSUInteger)0xFFFFFFFFull + 7;
        CHECK(relationship.maxCount == 6);
        relationship.maxCount = 100000;
        relationship.minCount = 3;
        CHECK(relationship.maxCount == 100000 && relationship.minCount == 3);

        /* container construction */
        CHECK([[NSPersistentContainer defaultDirectoryURL] isFileURL]);
        CHECK([[[NSPersistentContainer defaultDirectoryURL] lastPathComponent] isEqual:[[NSProcessInfo processInfo] processName]]);
        NSPersistentContainer *container = [NSPersistentContainer persistentContainerWithName:@"Prog" managedObjectModel:model];
        NSPersistentStoreDescription *initial = [container.persistentStoreDescriptions firstObject];
        CHECK([container.persistentStoreDescriptions count] == 1);
        CHECK([[initial.URL lastPathComponent] isEqual:@"Prog.sqlite"]);
        CHECK([[initial.URL URLByDeletingLastPathComponent] isEqual:
              [[NSPersistentContainer defaultDirectoryURL] URLByAppendingPathComponent:@""]] ||
              [[[initial.URL URLByDeletingLastPathComponent] path] isEqual:[[NSPersistentContainer defaultDirectoryURL] path]]);
        CHECK([container.name isEqual:@"Prog"] && container.managedObjectModel == model);
        CHECK([container.viewContext concurrencyType] == NSMainQueueConcurrencyType);
        NSManagedObjectContext *background = [container newBackgroundContext];
        CHECK([background concurrencyType] == NSPrivateQueueConcurrencyType);
        CHECK([background persistentStoreCoordinator] == container.persistentStoreCoordinator);
        [background release];
        CHECK([[NSPersistentContainer alloc] initWithName:@"NoSuchModelInThisBundle"] == nil);

        /* loading: synchronous callback on the caller's thread, with a copy of the description */
        NSPersistentStoreDescription *memory = [NSPersistentStoreDescription persistentStoreDescriptionWithURL:fileURL];
        memory.type = NSInMemoryStoreType;
        container.persistentStoreDescriptions = @[memory];
        __block int calls = 0;
        __block id delivered = nil;
        __block BOOL onMain = NO;
        [container loadPersistentStoresWithCompletionHandler:^(NSPersistentStoreDescription *dd, NSError *e) {
            calls++; delivered = dd; onMain = [NSThread isMainThread]; CHECK(e == nil);
        }];
        CHECK(calls == 1 && onMain && delivered != memory && [delivered isEqual:memory]);
        CHECK([[container.persistentStoreCoordinator persistentStores] count] == 1);

        /* the store directory is created; a read-only store is not created */
        NSPersistentContainer *xml = [NSPersistentContainer persistentContainerWithName:@"Xml" managedObjectModel:model];
        NSPersistentStoreDescription *xd = [NSPersistentStoreDescription persistentStoreDescriptionWithURL:
            [NSURL fileURLWithPath:[dir stringByAppendingPathComponent:@"made/on/demand/x.xml"]]];
        xd.type = NSXMLStoreType;
        xml.persistentStoreDescriptions = @[xd];
        [xml loadPersistentStoresWithCompletionHandler:^(NSPersistentStoreDescription *dd, NSError *e) { CHECK(e == nil); }];
        BOOL isDir = NO;
        CHECK([[NSFileManager defaultManager] fileExistsAtPath:[dir stringByAppendingPathComponent:@"made/on/demand"] isDirectory:&isDir] && isDir);

        /* a non-file URL for a file-backed store, and an unknown type, raise out of the load */
        NSPersistentContainer *bad = [NSPersistentContainer persistentContainerWithName:@"Bad" managedObjectModel:model];
        NSPersistentStoreDescription *bd = [NSPersistentStoreDescription persistentStoreDescriptionWithURL:webURL];
        bad.persistentStoreDescriptions = @[bd];
        CHECK([raiseName(^{ [bad loadPersistentStoresWithCompletionHandler:^(NSPersistentStoreDescription *dd, NSError *e) {}]; })
              isEqual:NSInvalidArgumentException]);
        bd.type = @"Bogus";
        bd.URL = fileURL;
        CHECK([raiseName(^{ [bad loadPersistentStoresWithCompletionHandler:^(NSPersistentStoreDescription *dd, NSError *e) {}]; })
              isEqual:NSInvalidArgumentException]);

        /* asynchronous description: load returns first, the handler runs on the main queue */
        NSPersistentContainer *async = [NSPersistentContainer persistentContainerWithName:@"Async" managedObjectModel:model];
        NSPersistentStoreDescription *ad = [NSPersistentStoreDescription persistentStoreDescriptionWithURL:fileURL];
        ad.type = NSInMemoryStoreType;
        ad.shouldAddStoreAsynchronously = YES;
        async.persistentStoreDescriptions = @[ad];
        __block int asyncState = 0;
        __block BOOL asyncOnMain = NO;
        [async loadPersistentStoresWithCompletionHandler:^(NSPersistentStoreDescription *dd, NSError *e) {
            asyncOnMain = [NSThread isMainThread]; asyncState = 2;
        }];
        CHECK(asyncState == 0);
        NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:5];
        while (asyncState == 0 && [deadline timeIntervalSinceNow] > 0)
            [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
        CHECK(asyncState == 2 && asyncOnMain);

        /* performBackgroundTask runs the block on a private queue context */
        dispatch_semaphore_t done = dispatch_semaphore_create(0);
        __block BOOL taskOnMain = YES;
        __block NSUInteger taskType = 99;
        [container performBackgroundTask:^(NSManagedObjectContext *c) {
            taskOnMain = [NSThread isMainThread]; taskType = [c concurrencyType]; dispatch_semaphore_signal(done);
        }];
        CHECK(dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC)) == 0);
        CHECK(!taskOnMain && taskType == NSPrivateQueueConcurrencyType);

        [[NSFileManager defaultManager] removeItemAtPath:dir error:NULL];
    }
    if (failures)
        return 1;
    puts("PASS_COREDATA_CONTAINER_CONTRACT");
    return 0;
}
