#import <Foundation/Foundation.h>
#import <CoreData/CoreData.h>
#import <dispatch/dispatch.h>
#include <stdio.h>
#include <stdint.h>

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

static NSManagedObjectModel *model(int *stage) {
    *stage = 61;
    NSEntityDescription *author = [[[NSEntityDescription alloc] init] autorelease];
    *stage = 62;
    author.name = @"Writer";
    *stage = 63;
    author.managedObjectClassName = @"NSManagedObject";
    *stage = 64;
    NSEntityDescription *document = [[[NSEntityDescription alloc] init] autorelease];
    *stage = 65;
    document.name = @"Document";
    *stage = 66;
    document.managedObjectClassName = @"NSManagedObject";
    *stage = 67;
    NSRelationshipDescription *writer = [[[NSRelationshipDescription alloc] init] autorelease];
    *stage = 68;
    writer.name = @"writer";
    *stage = 69;
    writer.destinationEntity = author;
    *stage = 70;
    writer.maxCount = 1;
    *stage = 71;
    writer.deleteRule = NSNullifyDeleteRule;
    *stage = 72;
    NSRelationshipDescription *documents = [[[NSRelationshipDescription alloc] init] autorelease];
    *stage = 73;
    documents.name = @"documents";
    *stage = 74;
    documents.destinationEntity = document;
    *stage = 75;
    documents.maxCount = 0;
    *stage = 76;
    documents.deleteRule = NSNullifyDeleteRule;
    *stage = 77;
    writer.inverseRelationship = documents;
    *stage = 78;
    documents.inverseRelationship = writer;
    *stage = 83;
    NSAttributeDescription *label = [[[NSAttributeDescription alloc] init] autorelease];
    NSMutableString *name = [NSMutableString stringWithString:@"label"];
    label.name = name;
    [name appendString:@"-changed"];
    label.attributeType = NSStringAttributeType;
    label.optional = YES;
    label.transient = NO;
    NSMutableString *taskDefault = [NSMutableString stringWithString:@"seed"];
    label.defaultValue = taskDefault;
    [taskDefault appendString:@"-changed"];
    *stage = 84;
    NSAttributeDescription *date = [[[NSAttributeDescription alloc] init] autorelease];
    date.name = @"date";
    date.attributeType = NSDateAttributeType;
    date.optional = YES;
    date.transient = NO;
    *stage = 85;
    NSAttributeDescription *flag = [[[NSAttributeDescription alloc] init] autorelease];
    flag.name = @"enabled";
    flag.attributeType = NSBooleanAttributeType;
    flag.optional = YES;
    flag.transient = NO;
    *stage = 86;
    writer.optional = YES;
    writer.transient = NO;
    documents.optional = YES;
    documents.transient = NO;
    writer.minCount = 0;
    NSUInteger wide = (NSUInteger)UINT32_MAX + 7;
    writer.maxCount = wide;
    if (writer.maxCount != wide)
        [NSException raise:NSInternalInconsistencyException format:@"Authored cardinality round trip failed"];
    writer.maxCount = 1;
    if (writer.isToMany || !documents.isToMany)
        [NSException raise:NSInternalInconsistencyException format:@"Authored relationship cardinality failed"];
    *stage = 79;
    document.properties = @[writer, label, date, flag];
    *stage = 80;
    author.properties = @[documents];
    *stage = 81;
    NSManagedObjectModel *result = [[[NSManagedObjectModel alloc] init] autorelease];
    *stage = 82;
    result.entities = @[author, document];
    return result;
}

int main(void) {
    int checkpoint = 70;
    @try {
    @autoreleasepool {
        Class containerClass = NSClassFromString(@"NSPersistentContainer");
        if (!containerClass)
            return 46;
        checkpoint = 60;
        NSManagedObjectModel *firstModel = model(&checkpoint);
        NSManagedObjectModel *secondModel = model(&checkpoint);
        checkpoint = 70;
        NSEntityDescription *document = [[firstModel entitiesByName] objectForKey:@"Document"];
        NSAttributeDescription *label = [[document propertiesByName] objectForKey:@"label"];
        CHECK([[firstModel entities] count] == 2 && [[firstModel entitiesByName] count] == 2);
        CHECK(document.managedObjectModel == firstModel && label.entity == document);
        CHECK([label.name isEqual:@"label"] && [label.defaultValue isEqual:@"seed-changed"]);
        CHECK(label.isOptional && !label.isTransient && [[document attributesByName] count] == 3);
        label.name = @"caption";
        document.name = @"Record";
        CHECK([[document propertiesByName] objectForKey:@"label"] == nil &&
              [[document propertiesByName] objectForKey:@"caption"] == label);
        CHECK([[firstModel entitiesByName] objectForKey:@"Document"] == nil &&
              [[firstModel entitiesByName] objectForKey:@"Record"] == document);
        NSAttributeDescription *duplicate = [[[NSAttributeDescription alloc] init] autorelease];
        duplicate.name = @"caption";
        BOOL rejectedConfiguration = NO;
        @try { document.properties = @[label, duplicate]; }
        @catch (NSException *exception) { rejectedConfiguration = YES; }
        CHECK(rejectedConfiguration && [[document properties] count] == 4);
        rejectedConfiguration = NO;
        NSEntityDescription *author = [[firstModel entitiesByName] objectForKey:@"Writer"];
        @try { author.properties = @[label]; }
        @catch (NSException *exception) { rejectedConfiguration = YES; }
        CHECK(rejectedConfiguration && [[author properties] count] == 1);
        id<ContainerContract> first = [[containerClass alloc] initWithName:@"First" managedObjectModel:firstModel];
        id<ContainerContract> second = [[containerClass alloc] initWithName:@"Second" managedObjectModel:secondModel];
        CHECK([first managedObjectModel] == firstModel && [second managedObjectModel] == secondModel);
        CHECK([first persistentStoreCoordinator] != [second persistentStoreCoordinator]);
        CHECK([[first viewContext] persistentStoreCoordinator] == [first persistentStoreCoordinator]);
        CHECK([first viewContext] == [first viewContext]);
        CHECK([[first viewContext] concurrencyType] == NSMainQueueConcurrencyType);
        BOOL rejectedMutation = NO;
        @try { label.name = @"forbidden"; }
        @catch (NSException *exception) { rejectedMutation = YES; }
        CHECK(rejectedMutation && [label.name isEqual:@"caption"]);
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
    } @catch (NSException *exception) {
        return checkpoint + 100;
    }
    return 0;
}
