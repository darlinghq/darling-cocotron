#import "NSSQLitePersistentStore.h"
#import "NSManagedObjectID-Private.h"
#import "NSManagedObject-Private.h"
#import <CoreData/NSMergePolicy.h>
#import <CoreData/CoreData.h>
#import <CoreData/CoreDataErrors.h>
#import <CoreFoundation/CFUUID.h>
#include <limits.h>
#include <math.h>
#include <sys/stat.h>

static BOOL storeError(NSError **error, NSInteger code) {
    if (error) *error = [NSError errorWithDomain:NSCocoaErrorDomain code:code userInfo:nil];
    return NO;
}

static NSString *columnString(sqlite3_stmt *statement, int column) {
    const void *bytes = sqlite3_column_blob(statement, column);
    int length = sqlite3_column_bytes(statement, column);
    if (!bytes && length) return nil;
    return [[[NSString alloc] initWithBytes:(bytes ?: "") length:length encoding:NSUTF8StringEncoding] autorelease];
}

static int bindString(sqlite3_stmt *statement, int column, NSString *string) {
    NSData *data = [string dataUsingEncoding:NSUTF8StringEncoding];
    if (!data || [data length] > INT_MAX) return SQLITE_MISMATCH;
    return sqlite3_bind_text(statement, column, [data length] ? [data bytes] : "", (int)[data length], SQLITE_TRANSIENT);
}

static NSString *newIdentifier(void) {
    CFUUIDRef uuid = CFUUIDCreate(NULL);
    NSString *result = [(NSString *)CFUUIDCreateString(NULL, uuid) autorelease];
    CFRelease(uuid);
    return result;
}

@implementation NSSQLitePersistentStore

+ (NSDictionary *)metadataForPersistentStoreWithURL:(NSURL *)url error:(NSError **)error {
    sqlite3 *database = NULL;
    sqlite3_stmt *statement = NULL;
    NSDictionary *metadata = nil;
    if ([url isFileURL] && sqlite3_open_v2([[url path] fileSystemRepresentation], &database, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, NULL) == SQLITE_OK &&
        sqlite3_prepare_v2(database, "SELECT format,version,uuid FROM darling_metadata", -1, &statement, NULL) == SQLITE_OK && sqlite3_step(statement) == SQLITE_ROW &&
        [columnString(statement, 0) isEqual:@"DarlingCoreData"] && sqlite3_column_int(statement, 1) == 1 && [columnString(statement, 2) length])
        metadata = [NSDictionary dictionaryWithObjectsAndKeys:NSSQLiteStoreType, NSStoreTypeKey, columnString(statement, 2), NSStoreUUIDKey, nil];
    sqlite3_finalize(statement);
    sqlite3_close(database);
    if (!metadata) storeError(error, NSPersistentStoreOpenError);
    return metadata;
}

+ (BOOL)setMetadata:(NSDictionary *)metadata forPersistentStoreWithURL:(NSURL *)url error:(NSError **)error {
    return storeError(error, NSPersistentStoreOperationError);
}

- (NSString *)type { return NSSQLiteStoreType; }

- (void)dealloc {
    sqlite3_close(_database);
    [_modelDescription release];
    [_selectedEntities release];
    [super dealloc];
}

- (BOOL)_execute:(const char *)sql {
    return sqlite3_exec(_database, sql, NULL, NULL, NULL) == SQLITE_OK;
}

- (sqlite3_stmt *)_prepare:(const char *)sql {
    sqlite3_stmt *statement = NULL;
    if (sqlite3_prepare_v2(_database, sql, -1, &statement, NULL) != SQLITE_OK) {
        sqlite3_finalize(statement);
        return NULL;
    }
    return statement;
}

- (BOOL)_describeModel:(NSError **)error {
    NSManagedObjectModel *model = [[self persistentStoreCoordinator] managedObjectModel];
    NSArray *entities = [model entitiesForConfiguration:[self configurationName]];
    if (!entities || ![entities count]) return storeError(error, NSPersistentStoreIncompatibleSchemaError);
    _selectedEntities = [entities copy];
    NSMutableArray *description = [NSMutableArray array];
    NSArray *names = [[[NSDictionary dictionaryWithObjects:entities forKeys:[entities valueForKey:@"name"]] allKeys] sortedArrayUsingSelector:@selector(compare:)];
    for (NSString *name in names) {
        NSEntityDescription *entity = [[model entitiesByName] objectForKey:name];
        if ([entity isAbstract] || [entity superentity] || [[entity subentities] count]) return storeError(error, NSPersistentStoreIncompatibleSchemaError);
        NSMutableArray *properties = [NSMutableArray array];
        for (NSString *key in [[[entity propertiesByName] allKeys] sortedArrayUsingSelector:@selector(compare:)]) {
            NSPropertyDescription *property = [[entity propertiesByName] objectForKey:key];
            NSMutableArray *item = [NSMutableArray arrayWithObjects:key, [NSNumber numberWithBool:[property isOptional]], [NSNumber numberWithBool:[property isTransient]], nil];
            if ([property isKindOfClass:[NSAttributeDescription class]]) {
                NSAttributeType type = [(NSAttributeDescription *)property attributeType];
                switch (type) {
                    case NSStringAttributeType: case NSInteger16AttributeType: case NSInteger32AttributeType: case NSInteger64AttributeType:
                    case NSBooleanAttributeType: case NSFloatAttributeType: case NSDoubleAttributeType: case NSDateAttributeType:
                    case NSBinaryDataAttributeType: case NSURIAttributeType: break;
                    default: return storeError(error, NSPersistentStoreIncompatibleSchemaError);
                }
                [item addObject:@"attribute"];
                [item addObject:[NSNumber numberWithUnsignedInteger:type]];
                id defaultValue = [(NSAttributeDescription *)property defaultValue];
                if ([defaultValue isKindOfClass:[NSURL class]]) defaultValue = [defaultValue absoluteString];
                [item addObject:defaultValue ?: @[]];
            } else if ([property isKindOfClass:[NSRelationshipDescription class]]) {
                NSRelationshipDescription *relationship = (NSRelationshipDescription *)property;
                NSRelationshipDescription *inverse = [relationship inverseRelationship];
                if (![property isOptional] || [property isTransient] || [relationship minCount] ||
                    [relationship deleteRule] != NSNullifyDeleteRule || !inverse ||
                    [inverse inverseRelationship] != relationship || ![entities containsObject:[relationship destinationEntity]] ||
                    [inverse destinationEntity] != entity || [relationship isToMany] == [inverse isToMany])
                    return storeError(error, NSPersistentStoreIncompatibleSchemaError);
                [item addObjectsFromArray:@[@"relationship", [[relationship destinationEntity] name], [inverse name], [NSNumber numberWithUnsignedInteger:[relationship maxCount]]]];
            } else return storeError(error, NSPersistentStoreIncompatibleSchemaError);
            [properties addObject:item];
        }
        [description addObject:@[name, [entity managedObjectClassName], properties]];
    }
    _modelDescription = [[NSPropertyListSerialization dataWithPropertyList:description format:NSPropertyListBinaryFormat_v1_0 options:0 error:error] retain];
    return _modelDescription != nil;
}

- (BOOL)_readCache:(NSError **)error {
    NSMutableDictionary *nodes = [NSMutableDictionary dictionary];
    NSMutableDictionary *caches = [NSMutableDictionary dictionary];
    NSManagedObjectModel *model = [[self persistentStoreCoordinator] managedObjectModel];
    sqlite3_stmt *statement = [self _prepare:"SELECT identifier,entity FROM darling_objects"];
    if (!statement) return storeError(error, NSPersistentStoreOpenError);
    int status;
    while ((status = sqlite3_step(statement)) == SQLITE_ROW) {
        NSString *reference = columnString(statement, 0);
        NSEntityDescription *entity = [[model entitiesByName] objectForKey:columnString(statement, 1)];
        if (![reference length] || ![_selectedEntities containsObject:entity]) { status = SQLITE_CORRUPT; break; }
        NSManagedObjectID *objectID = [self objectIDForEntity:entity referenceObject:reference];
        NSAtomicStoreCacheNode *node = [self cacheNodeForObjectID:objectID];
        if (!node) node = [[[NSAtomicStoreCacheNode alloc] initWithObjectID:objectID] autorelease];
        [nodes setObject:node forKey:reference];
        [caches setObject:[NSMutableDictionary dictionary] forKey:reference];
    }
    sqlite3_finalize(statement);
    if (status != SQLITE_DONE) return storeError(error, NSPersistentStoreOpenError);
    statement = [self _prepare:"SELECT object,key,kind,integer_value,real_value,bytes_value FROM darling_values"];
    if (!statement) return storeError(error, NSPersistentStoreOpenError);
    while ((status = sqlite3_step(statement)) == SQLITE_ROW) {
        NSString *reference = columnString(statement, 0), *key = columnString(statement, 1);
        NSAtomicStoreCacheNode *node = [nodes objectForKey:reference];
        NSAttributeDescription *attribute = [[[[node objectID] entity] attributesByName] objectForKey:key];
        NSAttributeType type = sqlite3_column_int(statement, 2);
        id value = nil;
        if (!attribute || [attribute attributeType] != type || [attribute isTransient]) { status = SQLITE_CORRUPT; break; }
        switch (type) {
            case NSInteger16AttributeType: case NSInteger32AttributeType: case NSInteger64AttributeType:
                value = [NSNumber numberWithLongLong:sqlite3_column_int64(statement, 3)]; break;
            case NSBooleanAttributeType: value = [NSNumber numberWithBool:sqlite3_column_int64(statement, 3) != 0]; break;
            case NSFloatAttributeType: value = [NSNumber numberWithFloat:sqlite3_column_double(statement, 4)]; break;
            case NSDoubleAttributeType: value = [NSNumber numberWithDouble:sqlite3_column_double(statement, 4)]; break;
            case NSDateAttributeType: value = [NSDate dateWithTimeIntervalSinceReferenceDate:sqlite3_column_double(statement, 4)]; break;
            case NSBinaryDataAttributeType: value = [NSData dataWithBytes:sqlite3_column_blob(statement, 5) length:sqlite3_column_bytes(statement, 5)]; break;
            case NSStringAttributeType: value = columnString(statement, 5); break;
            case NSURIAttributeType: value = [NSURL URLWithString:columnString(statement, 5)]; break;
            default: break;
        }
        if (!value) { status = SQLITE_CORRUPT; break; }
        [[caches objectForKey:reference] setObject:value forKey:key];
    }
    sqlite3_finalize(statement);
    if (status != SQLITE_DONE) return storeError(error, NSPersistentStoreOpenError);
    statement = [self _prepare:"SELECT source,key,target FROM darling_edges"];
    if (!statement) return storeError(error, NSPersistentStoreOpenError);
    while ((status = sqlite3_step(statement)) == SQLITE_ROW) {
        NSString *source = columnString(statement, 0), *key = columnString(statement, 1);
        NSAtomicStoreCacheNode *node = [nodes objectForKey:source], *target = [nodes objectForKey:columnString(statement, 2)];
        NSRelationshipDescription *relationship = [[[[node objectID] entity] relationshipsByName] objectForKey:key];
        if (!node || !target || !relationship || [relationship destinationEntity] != [[target objectID] entity]) { status = SQLITE_CORRUPT; break; }
        NSMutableDictionary *cache = [caches objectForKey:source];
        if ([relationship isToMany]) {
            NSMutableSet *set = [cache objectForKey:key];
            if (!set) { set = [NSMutableSet set]; [cache setObject:set forKey:key]; }
            [set addObject:target];
        } else {
            if ([cache objectForKey:key]) { status = SQLITE_CORRUPT; break; }
            [cache setObject:target forKey:key];
        }
    }
    sqlite3_finalize(statement);
    if (status != SQLITE_DONE) return storeError(error, NSPersistentStoreOpenError);
    for (NSString *reference in nodes) [[nodes objectForKey:reference] setPropertyCache:[caches objectForKey:reference]];
    [_cacheNodes removeAllObjects];
    [_objectIDToCacheNode removeAllObjects];
    [self addCacheNodes:[NSSet setWithArray:[nodes allValues]]];
    return YES;
}

- (BOOL)load:(NSError **)error {
    if (![self _describeModel:error]) return NO;
    if (![[self URL] isFileURL]) return storeError(error, NSPersistentStoreOpenError);
    _isReadOnly = [[[self options] objectForKey:NSReadOnlyPersistentStoreOption] boolValue];
    NSString *path = [[self URL] path];
    struct stat metadata;
    BOOL exists = stat([path fileSystemRepresentation], &metadata) == 0;
    if ((exists && !S_ISREG(metadata.st_mode)) || (_isReadOnly && !exists)) return storeError(error, NSPersistentStoreOpenError);
    int flags = (_isReadOnly ? SQLITE_OPEN_READONLY : SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE) | SQLITE_OPEN_FULLMUTEX;
    if (sqlite3_open_v2([path fileSystemRepresentation], &_database, flags, NULL) != SQLITE_OK) return storeError(error, NSPersistentStoreOpenError);
    if (![self _execute:"PRAGMA foreign_keys=ON"]) return storeError(error, NSPersistentStoreOpenError);
    if (!exists) {
        if (![self _execute:"BEGIN IMMEDIATE"] ||
            ![self _execute:"CREATE TABLE darling_metadata(format TEXT NOT NULL,version INTEGER NOT NULL,uuid TEXT NOT NULL,model BLOB NOT NULL,revision INTEGER NOT NULL); CREATE TABLE darling_objects(identifier TEXT PRIMARY KEY,entity TEXT NOT NULL,revision INTEGER NOT NULL); CREATE TABLE darling_values(object TEXT NOT NULL REFERENCES darling_objects(identifier) ON DELETE CASCADE,key TEXT NOT NULL,kind INTEGER NOT NULL,integer_value INTEGER,real_value REAL,bytes_value BLOB,PRIMARY KEY(object,key)); CREATE TABLE darling_edges(source TEXT NOT NULL REFERENCES darling_objects(identifier) ON DELETE CASCADE,key TEXT NOT NULL,target TEXT NOT NULL REFERENCES darling_objects(identifier) ON DELETE CASCADE,PRIMARY KEY(source,key,target))"]) {
            [self _execute:"ROLLBACK"]; return storeError(error, NSPersistentStoreOpenError);
        }
        sqlite3_stmt *statement = [self _prepare:"INSERT INTO darling_metadata VALUES('DarlingCoreData',1,?,?,0)"];
        BOOL success = statement && bindString(statement, 1, [self identifier]) == SQLITE_OK &&
            sqlite3_bind_blob(statement, 2, [_modelDescription bytes], (int)[_modelDescription length], SQLITE_TRANSIENT) == SQLITE_OK && sqlite3_step(statement) == SQLITE_DONE;
        sqlite3_finalize(statement);
        if (!success || ![self _execute:"COMMIT"]) { [self _execute:"ROLLBACK"]; return storeError(error, NSPersistentStoreOpenError); }
    }
    sqlite3_stmt *statement = [self _prepare:"SELECT format,version,uuid,model,revision FROM darling_metadata"];
    if (!statement) return storeError(error, NSPersistentStoreIncompatibleSchemaError);
    BOOL valid = sqlite3_step(statement) == SQLITE_ROW && [columnString(statement, 0) isEqual:@"DarlingCoreData"] && sqlite3_column_int(statement, 1) == 1;
    NSString *uuid = valid ? [[columnString(statement, 2) copy] autorelease] : nil;
    NSData *description = valid ? [NSData dataWithBytes:sqlite3_column_blob(statement, 3) length:sqlite3_column_bytes(statement, 3)] : nil;
    _revision = valid ? sqlite3_column_int64(statement, 4) : 0;
    valid = valid && [uuid length] && [description isEqual:_modelDescription] && sqlite3_step(statement) == SQLITE_DONE;
    sqlite3_finalize(statement);
    if (!valid) return storeError(error, NSPersistentStoreIncompatibleSchemaError);
    [self setIdentifier:uuid];
    [self setMetadata:@{NSStoreTypeKey:NSSQLiteStoreType, NSStoreUUIDKey:uuid}];
    return [self _readCache:error];
}

- newReferenceObjectForManagedObject:(NSManagedObject *)object { return [newIdentifier() copy]; }

- (long long)_versionForObjectID:(NSManagedObjectID *)objectID {
    @synchronized(self) {
        sqlite3_stmt *statement = [self _prepare:"SELECT revision FROM darling_objects WHERE identifier=?"];
        long long version = -1;
        if (statement && bindString(statement, 1, [objectID referenceObject]) == SQLITE_OK && sqlite3_step(statement) == SQLITE_ROW)
            version = sqlite3_column_int64(statement, 0);
        sqlite3_finalize(statement);
        return version;
    }
}

- (BOOL)_bindValue:(id)value attribute:(NSAttributeDescription *)attribute statement:(sqlite3_stmt *)statement {
    NSAttributeType type = [attribute attributeType];
    sqlite3_bind_int(statement, 3, type);
    if (!value) return [attribute isOptional];
    long long integer;
    double real;
    NSData *bytes = nil;
    switch (type) {
        case NSInteger16AttributeType: case NSInteger32AttributeType: case NSInteger64AttributeType: case NSBooleanAttributeType:
            if (![value isKindOfClass:[NSNumber class]]) return NO;
            integer = [value longLongValue];
            if ((type == NSInteger16AttributeType && (integer < INT16_MIN || integer > INT16_MAX)) ||
                (type == NSInteger32AttributeType && (integer < INT32_MIN || integer > INT32_MAX)) ||
                (type == NSBooleanAttributeType && integer != 0 && integer != 1)) return NO;
            return sqlite3_bind_int64(statement, 4, integer) == SQLITE_OK;
        case NSFloatAttributeType: case NSDoubleAttributeType:
            if (![value isKindOfClass:[NSNumber class]]) return NO;
            real = type == NSFloatAttributeType ? [value floatValue] : [value doubleValue];
            if (!isfinite(real)) return NO;
            return sqlite3_bind_double(statement, 5, real) == SQLITE_OK;
        case NSDateAttributeType:
            if (![value isKindOfClass:[NSDate class]] || !isfinite(real = [value timeIntervalSinceReferenceDate])) return NO;
            return sqlite3_bind_double(statement, 5, real) == SQLITE_OK;
        case NSStringAttributeType:
            if (![value isKindOfClass:[NSString class]]) return NO;
            bytes = [value dataUsingEncoding:NSUTF8StringEncoding]; break;
        case NSURIAttributeType:
            if (![value isKindOfClass:[NSURL class]] || ![[value scheme] length]) return NO;
            bytes = [[value absoluteString] dataUsingEncoding:NSUTF8StringEncoding]; break;
        case NSBinaryDataAttributeType:
            if (![value isKindOfClass:[NSData class]]) return NO;
            bytes = value; break;
        default: return NO;
    }
    return bytes && [bytes length] <= INT_MAX && sqlite3_bind_blob(statement, 6, [bytes length] ? [bytes bytes] : "", (int)[bytes length], SQLITE_TRANSIENT) == SQLITE_OK;
}

- (BOOL)_writeObject:(NSManagedObject *)object inserted:(BOOL)inserted {
    NSString *reference = [[object objectID] referenceObject];
    sqlite3_stmt *statement = [self _prepare:inserted ? "INSERT INTO darling_objects VALUES(?,?,?)" : "SELECT entity,revision FROM darling_objects WHERE identifier=?"];
    BOOL success = statement && bindString(statement, 1, reference) == SQLITE_OK;
    if (inserted) success = success && bindString(statement, 2, [[object entity] name]) == SQLITE_OK && sqlite3_bind_int64(statement, 3, _revision + 1) == SQLITE_OK && sqlite3_step(statement) == SQLITE_DONE;
    else success = success && sqlite3_step(statement) == SQLITE_ROW && [columnString(statement, 0) isEqual:[[object entity] name]];
    BOOL objectTrump = [[object managedObjectContext] mergePolicy] == NSMergeByPropertyObjectTrumpMergePolicy;
    if (success && !inserted && !objectTrump && sqlite3_column_int64(statement, 1) != [object _storeVersion]) success = NO;
    sqlite3_finalize(statement);
    if (!success) return NO;
    if (!inserted) {
        statement = [self _prepare:"UPDATE darling_objects SET revision=? WHERE identifier=?"];
        success = statement && sqlite3_bind_int64(statement, 1, _revision + 1) == SQLITE_OK && bindString(statement, 2, reference) == SQLITE_OK && sqlite3_step(statement) == SQLITE_DONE;
        sqlite3_finalize(statement);
        if (!success) return NO;
    }
    const char *deletions[] = {"DELETE FROM darling_values WHERE object=?", "DELETE FROM darling_edges WHERE source=?"};
    for (NSUInteger index = 0; index < 2; index++) {
        statement = [self _prepare:deletions[index]];
        success = statement && bindString(statement, 1, reference) == SQLITE_OK && sqlite3_step(statement) == SQLITE_DONE;
        sqlite3_finalize(statement);
        if (!success) return NO;
    }
    for (NSAttributeDescription *attribute in [[[object entity] attributesByName] allValues]) {
        if ([attribute isTransient]) continue;
        NSString *key = [attribute name];
        id value = !inserted && objectTrump && ![[object changedValues] objectForKey:key] ? [[self cacheNodeForObjectID:[object objectID]] valueForKey:key] : [object primitiveValueForKey:key];
        if (!value && [attribute isOptional]) continue;
        statement = [self _prepare:"INSERT INTO darling_values VALUES(?,?,?,?,?,?)"];
        success = statement && bindString(statement, 1, reference) == SQLITE_OK && bindString(statement, 2, [attribute name]) == SQLITE_OK && [self _bindValue:value attribute:attribute statement:statement] && sqlite3_step(statement) == SQLITE_DONE;
        sqlite3_finalize(statement);
        if (!success) return NO;
    }
    for (NSRelationshipDescription *relationship in [[[object entity] relationshipsByName] allValues]) {
        NSString *key = [relationship name];
        id value = [object primitiveValueForKey:key];
        if (!inserted && objectTrump && ![[object changedValues] objectForKey:key]) {
            id cacheValue = [[self cacheNodeForObjectID:[object objectID]] valueForKey:key];
            if ([relationship isToMany]) {
                NSMutableSet *ids = [NSMutableSet set];
                for (NSAtomicStoreCacheNode *node in cacheValue) [ids addObject:[node objectID]];
                value = ids;
            } else value = [cacheValue objectID];
        }
        NSSet *targets = [relationship isToMany] ? value : (value ? [NSSet setWithObject:value] : [NSSet set]);
        for (NSManagedObjectID *target in targets) {
            if ([target isTemporaryID] || [target persistentStore] != self || [target entity] != [relationship destinationEntity]) return NO;
            statement = [self _prepare:"INSERT INTO darling_edges VALUES(?,?,?)"];
            success = statement && bindString(statement, 1, reference) == SQLITE_OK && bindString(statement, 2, [relationship name]) == SQLITE_OK && bindString(statement, 3, [target referenceObject]) == SQLITE_OK && sqlite3_step(statement) == SQLITE_DONE;
            sqlite3_finalize(statement);
            if (!success) return NO;
        }
    }
    return YES;
}

- (BOOL)_commitInserted:(NSSet *)inserted updated:(NSSet *)updated deleted:(NSSet *)deleted error:(NSError **)error {
    @synchronized(self) {
        for (NSManagedObject *object in updated) {
            id policy = [[object managedObjectContext] mergePolicy];
            if (policy != NSErrorMergePolicy && policy != NSMergeByPropertyObjectTrumpMergePolicy)
                return storeError(error, NSPersistentStoreOperationError);
        }
        if (_isReadOnly || ![self _execute:"BEGIN IMMEDIATE"]) return storeError(error, NSPersistentStoreSaveError);
        sqlite3_stmt *statement = [self _prepare:"UPDATE darling_metadata SET revision=revision+1 WHERE revision=?"];
        BOOL success = statement && sqlite3_bind_int64(statement, 1, _revision) == SQLITE_OK && sqlite3_step(statement) == SQLITE_DONE && sqlite3_changes(_database) == 1;
        sqlite3_finalize(statement);
        // All new IDs must exist before inserting references between new objects.
        if (success) [self _execute:"PRAGMA defer_foreign_keys=ON"];
        for (NSManagedObject *object in inserted) {
            if ([deleted containsObject:object]) continue;
            if (success) success = [self _writeObject:object inserted:YES];
        }
        for (NSManagedObject *object in updated) {
            if ([inserted containsObject:object] || [deleted containsObject:object]) continue;
            if (success) success = [self _writeObject:object inserted:NO];
        }
        for (NSManagedObject *object in deleted) {
            if ([inserted containsObject:object]) continue;
            statement = success ? [self _prepare:"DELETE FROM darling_objects WHERE identifier=?"] : NULL;
            if (success) success = statement && bindString(statement, 1, [[object objectID] referenceObject]) == SQLITE_OK && sqlite3_step(statement) == SQLITE_DONE;
            sqlite3_finalize(statement);
        }
        if (!success || ![self _execute:"COMMIT"]) {
            [self _execute:"ROLLBACK"];
            return storeError(error, NSPersistentStoreSaveError);
        }
        _revision++;
        return [self _readCache:error];
    }
}

- (BOOL)save:(NSError **)error { return storeError(error, NSPersistentStoreOperationError); }
@end
