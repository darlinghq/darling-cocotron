#import <CoreData/NSPersistentContainer.h>
#import <CoreData/NSPersistentStoreDescription.h>
#import <CoreData/NSPersistentStoreCoordinator.h>
#import <CoreData/NSManagedObjectContext.h>
#import <CoreData/NSManagedObjectModel.h>
#import <CoreData/CoreDataErrors.h>
#import <dispatch/dispatch.h>

@implementation NSPersistentContainer

@synthesize name = _name;
@synthesize managedObjectModel = _managedObjectModel;
@synthesize persistentStoreCoordinator = _persistentStoreCoordinator;
@synthesize viewContext = _viewContext;
@synthesize persistentStoreDescriptions = _persistentStoreDescriptions;

+ (NSURL *)defaultDirectoryURL {
    NSURL *support = [[[NSFileManager defaultManager] URLsForDirectory:NSApplicationSupportDirectory
                                                             inDomains:NSUserDomainMask] firstObject];
    return [support URLByAppendingPathComponent:[[NSProcessInfo processInfo] processName]];
}

+ (instancetype)persistentContainerWithName:(NSString *)name {
    return [[[self alloc] initWithName:name] autorelease];
}

+ (instancetype)persistentContainerWithName:(NSString *)name managedObjectModel:(NSManagedObjectModel *)model {
    return [[[self alloc] initWithName:name managedObjectModel:model] autorelease];
}

- (instancetype)initWithName:(NSString *)name {
    NSBundle *bundle = [NSBundle mainBundle];
    NSURL *modelURL = [bundle URLForResource:name withExtension:@"mom"];
    if (!modelURL) {
        NSURL *directory = [bundle URLForResource:name withExtension:@"momd"];
        NSArray *contents = directory ? [[NSFileManager defaultManager]
            contentsOfDirectoryAtURL:directory includingPropertiesForKeys:nil options:0 error:NULL] : nil;
        NSMutableArray *models = [NSMutableArray array];
        for (NSURL *URL in contents)
            if ([[URL pathExtension] isEqual:@"mom"])
                [models addObject:URL];
        if ([models count] == 1)
            modelURL = [models objectAtIndex:0];
    }
    NSManagedObjectModel *model = nil;
    if (modelURL) {
        @try {
            model = [[NSManagedObjectModel alloc] initWithContentsOfURL:modelURL];
            if (![model isKindOfClass:[NSManagedObjectModel class]]) {
                [model release];
                model = nil;
            }
        } @catch (NSException *exception) {
            model = nil;
        }
    }
    if (!model) {
        NSLog(@"CoreData: error: Failed to load model named %@", name);
        [self release];
        return nil;
    }
    self = [self initWithName:name managedObjectModel:model];
    [model release];
    return self;
}

- (instancetype)initWithName:(NSString *)name managedObjectModel:(NSManagedObjectModel *)model {
    self = [super init];
    if (self) {
        _name = [name copy];
        _managedObjectModel = [model retain];
        _persistentStoreCoordinator = [[NSPersistentStoreCoordinator alloc]
            initWithManagedObjectModel:model];
        _viewContext = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSMainQueueConcurrencyType];
        [_viewContext setPersistentStoreCoordinator:_persistentStoreCoordinator];
        NSURL *URL = [[[self class] defaultDirectoryURL]
            URLByAppendingPathComponent:[name stringByAppendingPathExtension:@"sqlite"]];
        NSPersistentStoreDescription *description = [[NSPersistentStoreDescription alloc] initWithURL:URL];
        _persistentStoreDescriptions = [[NSArray alloc] initWithObjects:description, nil];
        [description release];
    }
    return self;
}

- (void)loadDescription:(NSPersistentStoreDescription *)description
            completion:(void (^)(NSPersistentStoreDescription *, NSError *))block {
    NSError *error = nil;
    NSURL *URL = description.URL;
    if (![description.type isEqual:NSInMemoryStoreType] && !description.isReadOnly && [URL isFileURL])
        [[NSFileManager defaultManager] createDirectoryAtURL:[URL URLByDeletingLastPathComponent]
                                 withIntermediateDirectories:YES attributes:nil error:NULL];
    NSDictionary *options = description.options;
    [_persistentStoreCoordinator lock];
    @try {
        [_persistentStoreCoordinator addPersistentStoreWithType:description.type
            configuration:description.configuration URL:URL options:options error:&error];
    } @finally {
        [_persistentStoreCoordinator unlock];
    }
    block([[description copy] autorelease], error);
}

- (void)loadPersistentStoresWithCompletionHandler:(void (^)(NSPersistentStoreDescription *, NSError *))block {
    if (!block)
        [NSException raise:NSInvalidArgumentException format:@"A persistent store completion handler is required"];
    block = [[block copy] autorelease];
    for (NSPersistentStoreDescription *description in [[_persistentStoreDescriptions copy] autorelease]) {
        if (description.shouldAddStoreAsynchronously)
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                @autoreleasepool {
                    [self loadDescription:description completion:^(NSPersistentStoreDescription *loaded, NSError *error) {
                        dispatch_async(dispatch_get_main_queue(), ^{ block(loaded, error); });
                    }];
                }
            });
        else
            [self loadDescription:description completion:block];
    }
}

- (NSManagedObjectContext *)newBackgroundContext {
    NSManagedObjectContext *context = [[NSManagedObjectContext alloc]
        initWithConcurrencyType:NSPrivateQueueConcurrencyType];
    [context setPersistentStoreCoordinator:_persistentStoreCoordinator];
    return context;
}

- (void)performBackgroundTask:(void (^)(NSManagedObjectContext *))block {
    NSManagedObjectContext *context = [self newBackgroundContext];
    [context performBlock:^{ block(context); }];
    [context release];
}

- (void)dealloc {
    [_name release];
    [_managedObjectModel release];
    [_persistentStoreCoordinator release];
    [_viewContext release];
    [_persistentStoreDescriptions release];
    [super dealloc];
}

@end
