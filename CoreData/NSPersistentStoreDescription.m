#import <CoreData/NSPersistentStoreDescription.h>
#import <CoreData/NSPersistentStoreCoordinator.h>

@implementation NSPersistentStoreDescription

@synthesize URL = _URL;
@synthesize type = _type;
@synthesize configuration = _configuration;
@synthesize shouldAddStoreAsynchronously = _shouldAddStoreAsynchronously;

+ (instancetype)persistentStoreDescriptionWithURL:(NSURL *)URL {
    return [[[self alloc] initWithURL:URL] autorelease];
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _URL = [[NSURL fileURLWithPath:@"/dev/null"] retain];
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

- (NSTimeInterval)timeout {
    NSNumber *value = [_options objectForKey:NSPersistentStoreTimeoutOption];
    return value ? [value doubleValue] : 240;
}

- (void)setTimeout:(NSTimeInterval)value {
    [self setOption:[NSNumber numberWithDouble:value] forKey:NSPersistentStoreTimeoutOption];
}

- (NSDictionary *)sqlitePragmas {
    NSDictionary *pragmas = [_options objectForKey:NSSQLitePragmasOption];
    return pragmas ? [[pragmas copy] autorelease] : [NSDictionary dictionary];
}

- (void)setValue:(NSObject *)value forPragmaNamed:(NSString *)name {
    NSMutableDictionary *pragmas = [[[_options objectForKey:NSSQLitePragmasOption] mutableCopy] autorelease];
    if (!pragmas)
        pragmas = [NSMutableDictionary dictionary];
    if (value)
        [pragmas setObject:value forKey:name];
    else
        [pragmas removeObjectForKey:name];
    [self setOption:pragmas forKey:NSSQLitePragmasOption];
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

- (id)copyWithZone:(NSZone *)zone {
    NSPersistentStoreDescription *copy = [[[self class] allocWithZone:zone] initWithURL:_URL];
    copy.type = _type;
    copy.configuration = _configuration;
    copy.shouldAddStoreAsynchronously = _shouldAddStoreAsynchronously;
    [copy->_options setDictionary:_options];
    return copy;
}

static BOOL SameObject(id a, id b) {
    return a == b || [a isEqual:b];
}

- (BOOL)isEqual:(id)other {
    if (other == self)
        return YES;
    if (![other isKindOfClass:[NSPersistentStoreDescription class]])
        return NO;
    NSPersistentStoreDescription *description = other;
    return SameObject(_URL, description->_URL) && SameObject(_type, description->_type) &&
           SameObject(_configuration, description->_configuration) &&
           SameObject(_options, description->_options) &&
           _shouldAddStoreAsynchronously == description->_shouldAddStoreAsynchronously;
}

- (NSUInteger)hash {
    return [_URL hash] ^ [_type hash] ^ [_configuration hash] ^ [_options hash];
}

- (void)dealloc {
    [_URL release];
    [_type release];
    [_configuration release];
    [_options release];
    [super dealloc];
}

@end
