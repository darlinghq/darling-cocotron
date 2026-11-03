#import <Foundation/Foundation.h>
#import <CoreData/CoreData.h>
#import <dispatch/dispatch.h>
#include <stdio.h>

@protocol ContainerContract <NSObject>
- (instancetype)initWithName:(NSString *)name;
- (instancetype)initWithName:(NSString *)name managedObjectModel:(NSManagedObjectModel *)model;
- (NSString *)name;
- (NSManagedObjectModel *)managedObjectModel;
- (NSPersistentStoreCoordinator *)persistentStoreCoordinator;
- (NSManagedObjectContext *)viewContext;
- (NSArray *)persistentStoreDescriptions;
- (void)setPersistentStoreDescriptions:(NSArray *)descriptions;
- (void)loadPersistentStoresWithCompletionHandler:(void (^)(id, NSError *))block;
@end

#define CHECK(condition) do { checkpoint++; if (!(condition)) return checkpoint; } while (0)

static NSManagedObjectModel *model(void) {
    NSEntityDescription *author = [[[NSEntityDescription alloc] init] autorelease];
    author.name = @"Writer";
    author.managedObjectClassName = @"NSManagedObject";
    NSEntityDescription *document = [[[NSEntityDescription alloc] init] autorelease];
    document.name = @"Document";
    document.managedObjectClassName = @"NSManagedObject";
    NSRelationshipDescription *writer = [[[NSRelationshipDescription alloc] init] autorelease];
    writer.name = @"writer";
    writer.destinationEntity = author;
    writer.maxCount = 1;
    writer.deleteRule = NSNullifyDeleteRule;
    NSRelationshipDescription *documents = [[[NSRelationshipDescription alloc] init] autorelease];
    documents.name = @"documents";
    documents.destinationEntity = document;
    documents.maxCount = 0;
    documents.deleteRule = NSNullifyDeleteRule;
    writer.inverseRelationship = documents;
    documents.inverseRelationship = writer;
    document.properties = @[writer];
    author.properties = @[documents];
    NSManagedObjectModel *result = [[[NSManagedObjectModel alloc] init] autorelease];
    result.entities = @[author, document];
    return result;
}

int main(void) {
    int checkpoint = 70;
    @autoreleasepool {
        Class containerClass = NSClassFromString(@"NSPersistentContainer");
        if (!containerClass)
            return 46;
        NSManagedObjectModel *firstModel = model();
        NSManagedObjectModel *secondModel = model();
        id<ContainerContract> first = [[containerClass alloc] initWithName:@"First" managedObjectModel:firstModel];
        id<ContainerContract> second = [[containerClass alloc] initWithName:@"Second" managedObjectModel:secondModel];
        CHECK([first managedObjectModel] == firstModel && [second managedObjectModel] == secondModel);
        CHECK([first persistentStoreCoordinator] != [second persistentStoreCoordinator]);
        CHECK([[first viewContext] persistentStoreCoordinator] == [first persistentStoreCoordinator]);
        CHECK([first viewContext] == [first viewContext]);
        CHECK([[first viewContext] concurrencyType] == NSMainQueueConcurrencyType);
        NSURL *firstURL = [[[first persistentStoreDescriptions] objectAtIndex:0] URL];
        NSURL *secondURL = [[[second persistentStoreDescriptions] objectAtIndex:0] URL];
        CHECK(firstURL && secondURL && ![firstURL isEqual:secondURL]);
        NSPersistentStoreDescription *one = [[[NSPersistentStoreDescription alloc] initWithURL:firstURL] autorelease];
        NSPersistentStoreDescription *two = [[[NSPersistentStoreDescription alloc] initWithURL:secondURL] autorelease];
        one.type = NSInMemoryStoreType;
        two.type = NSInMemoryStoreType;
        one.readOnly = YES;
        CHECK([(NSNumber *)[[one options] objectForKey:NSReadOnlyPersistentStoreOption] boolValue]);
        [one setOption:@NO forKey:NSReadOnlyPersistentStoreOption];
        CHECK(!one.isReadOnly);
        [first setPersistentStoreDescriptions:@[one, two]];
        __block NSUInteger calls = 0;
        __block BOOL valid = YES;
        [first loadPersistentStoresWithCompletionHandler:^(id description, NSError *error) {
            calls++;
            valid &= !error && [NSThread isMainThread] && (description == one || description == two);
        }];
        CHECK(valid && calls == 2 && [[[first persistentStoreCoordinator] persistentStores] count] == 2);
        NSPersistentStoreDescription *bad = [[[NSPersistentStoreDescription alloc] initWithURL:firstURL] autorelease];
        bad.type = @"UnsupportedAuthoredStore";
        [second setPersistentStoreDescriptions:@[bad]];
        calls = 0;
        [second loadPersistentStoresWithCompletionHandler:^(id description, NSError *error) {
            calls++;
            valid &= error != nil && description == bad;
        }];
        CHECK(valid && calls == 1 && [[[second persistentStoreCoordinator] persistentStores] count] == 0);
        bad.type = @"XML";
        bad.URL = [NSURL URLWithString:@"https://invalid.example/store"];
        calls = 0;
        [second loadPersistentStoresWithCompletionHandler:^(id description, NSError *error) {
            calls++;
            valid &= error != nil;
        }];
        CHECK(valid && calls == 1);
        id<ContainerContract> missing = [[containerClass alloc] initWithName:@"AuthoredMissingModel"];
        calls = 0;
        [missing loadPersistentStoresWithCompletionHandler:^(id description, NSError *error) {
            calls++;
            valid &= error != nil;
        }];
        CHECK(valid && calls == 1);
        [missing release];
        [second release];
        [first release];
        puts("PASS_COREDATA_CONTAINER_STARTUP");
    }
    return 0;
}
