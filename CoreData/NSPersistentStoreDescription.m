#import <CoreData/NSPersistentStoreDescription.h>
#import <CoreData/NSPersistentStoreCoordinator.h>

@implementation NSPersistentStoreDescription

@synthesize URL = _URL;
@synthesize type = _type;
@synthesize configuration = _configuration;
@synthesize shouldAddStoreAsynchronously = _shouldAddStoreAsynchronously;

- (instancetype)init {
    self = [super init];
    if (self) {
        _type = [NSSQLiteStoreType copy];
        _options = [[NSMutableDictionary alloc] init];
        self.shouldMigrateStoreAutomatically = YES;
        self.shouldInferMappingModelAutomatically = YES;
    }
    return self;
}

- (instancetype)initWithURL:(NSURL *)URL {
    self = [self init];
    if (self)
        self.URL = URL;
    return self;
}

- (BOOL)isReadOnly {
    return [[_options objectForKey:NSReadOnlyPersistentStoreOption] boolValue];
}

- (void)setReadOnly:(BOOL)value {
    [self setOption:[NSNumber numberWithBool:value] forKey:NSReadOnlyPersistentStoreOption];
}

- (BOOL)shouldMigrateStoreAutomatically {
    return [[_options objectForKey:NSMigratePersistentStoresAutomaticallyOption] boolValue];
}

- (void)setShouldMigrateStoreAutomatically:(BOOL)value {
    [self setOption:[NSNumber numberWithBool:value] forKey:NSMigratePersistentStoresAutomaticallyOption];
}

- (BOOL)shouldInferMappingModelAutomatically {
    return [[_options objectForKey:NSInferMappingModelAutomaticallyOption] boolValue];
}

- (void)setShouldInferMappingModelAutomatically:(BOOL)value {
    [self setOption:[NSNumber numberWithBool:value] forKey:NSInferMappingModelAutomaticallyOption];
}

- (NSDictionary *)options {
    return [[_options copy] autorelease];
}

- (void)setOption:(NSObject *)option forKey:(NSString *)key {
    if (option)
        [_options setObject:option forKey:key];
    else
        [_options removeObjectForKey:key];
}

- (void)dealloc {
    [_URL release];
    [_type release];
    [_configuration release];
    [_options release];
    [super dealloc];
}

@end
