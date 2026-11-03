/* Copyright(c)2008 Dan Knapp

Permission is hereby granted, free of charge, to any person obtaining a copy of
this software and associated documentation files(the "Software"), to deal in the
Software without restriction, including without limitation the rights to use,
copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the
Software, and to permit persons to whom the Software is furnished to do so,
subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */
#import "NSEntityDescription-Private.h"
#import "NSSQLitePersistentStore.h"
#import <CoreData/NSMergePolicy.h>
#import <Foundation/NSComparisonPredicate.h>
#import <Foundation/NSExpression.h>
#import "NSManagedObject-Private.h"
#import "NSManagedObjectID-Private.h"
#import "NSPersistentStoreCoordinator-Private.h"
#import <CoreData/CoreDataErrors.h>
#import <CoreData/NSAtomicStore.h>
#import <CoreData/NSAttributeDescription.h>
#import <CoreData/NSRelationshipDescription.h>
#import <CoreData/NSEntityDescription.h>
#import <CoreData/NSFetchRequest.h>
#import <CoreData/NSManagedObject.h>
#import <CoreData/NSManagedObjectContext.h>
#import <CoreData/NSManagedObjectModel.h>
#import <CoreData/NSPersistentStore.h>
#import <Foundation/NSRaise.h>
#import <Foundation/NSUndoManager.h>

NSString *const NSManagedObjectContextObjectsDidChangeNotification = @"NSManagedObjectContextObjectsDidChangeNotification";
NSString *const NSManagedObjectContextWillSaveNotification =
        @"NSManagedObjectContextWillSaveNotification";
NSString *const NSManagedObjectContextDidSaveNotification =
        @"NSManagedObjectContextDidSaveNotification";

NSString *const NSInsertedObjectsKey = @"NSInsertedObjectsKey";
NSString *const NSUpdatedObjectsKey = @"NSUpdatedObjectsKey";
NSString *const NSDeletedObjectsKey = @"NSDeletedObjectsKey";
NSString *const NSRefreshedObjectsKey = @"NSRefreshedObjectsKey";
NSString *const NSInvalidatedObjectsKey = @"NSInvalidatedObjectsKey";
NSString *const NSInvalidatedAllObjectsKey = @"NSInvalidatedAllObjectsKey";

@interface NSAtomicStore (private)
- (void) _uniqueObjectID: (NSManagedObjectID *) objectID;
@end

static char ContextQueueKey;

@implementation NSManagedObjectContext

- init {
    return [self initWithConcurrencyType:NSConfinementConcurrencyType];
}

- (instancetype)initWithConcurrencyType:(NSManagedObjectContextConcurrencyType)type {
    self = [super init];
    if (!self)
        return nil;
    if (type > NSMainQueueConcurrencyType) {
        [self release];
        [NSException raise:NSInvalidArgumentException format:@"Invalid context concurrency type"];
        return nil;
    }
    _concurrencyType = type;
    if (type == NSPrivateQueueConcurrencyType) {
        _contextQueue = dispatch_queue_create("org.darling.CoreData.context", DISPATCH_QUEUE_SERIAL);
        dispatch_queue_set_specific(_contextQueue, &ContextQueueKey, self, NULL);
    } else if (type == NSMainQueueConcurrencyType) {
        _contextQueue = dispatch_get_main_queue();
        dispatch_retain(_contextQueue);
    }
    [NSMergePolicy class];
    _mergePolicy = [NSErrorMergePolicy retain];
    _pendingInserted = [NSMutableSet new];
    _pendingUpdated = [NSMutableSet new];
    _pendingDeleted = [NSMutableSet new];
    _lock = [[NSLock alloc] init];
    _storeCoordinator = nil;
    _undoManager = [[NSUndoManager alloc] init];
    _registeredObjects = [[NSMutableSet alloc] init];
    _insertedObjects = [[NSMutableSet alloc] init];
    _updatedObjects = [[NSMutableSet alloc] init];
    _deletedObjects = [[NSMutableSet alloc] init];

    _objectIdToObject = NSCreateMapTable(NSObjectMapKeyCallBacks,
                                         NSObjectMapValueCallBacks, 0);
    _requestedProcessPendingChanges = NO;
    return self;
}

- (NSManagedObjectContextConcurrencyType)concurrencyType {
    return _concurrencyType;
}

- (BOOL)_isOnContextQueue {
    return (_concurrencyType == NSMainQueueConcurrencyType && [NSThread isMainThread]) ||
           dispatch_get_specific(&ContextQueueKey) == self;
}

- (void)performBlock:(void (^)(void))block {
    if (!_contextQueue)
        [NSException raise:NSInvalidArgumentException format:@"A queue-based context is required"];
    dispatch_async(_contextQueue, ^{
        @autoreleasepool {
            block();
            [self processPendingChanges];
        }
    });
}

- (void)performBlockAndWait:(void (^)(void))block {
    if (!_contextQueue)
        [NSException raise:NSInvalidArgumentException format:@"A queue-based context is required"];
    void (^work)(void) = ^{
        @autoreleasepool {
            block();
            [self processPendingChanges];
        }
    };
    if ([self _isOnContextQueue])
        work();
    else
        dispatch_sync(_contextQueue, work);
}

- (void) dealloc {
    if (_contextQueue)
        dispatch_release(_contextQueue);
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_storeCoordinator release];
    [_undoManager release];
    [_registeredObjects release];
    [_insertedObjects release];
    [_updatedObjects release];
    [_deletedObjects release];
    [_pendingInserted release];
    [_pendingUpdated release];
    [_pendingDeleted release];
    [_mergePolicy release];
    [_lock release];
    NSFreeMapTable(_objectIdToObject);
    [super dealloc];
}

- (NSPersistentStoreCoordinator *) persistentStoreCoordinator {
    return _storeCoordinator;
}

- (NSUndoManager *) undoManager {
    return _undoManager;
}

- (BOOL) retainsRegisteredObjects {
    return _retainsRegisteredObjects;
}

- (BOOL) propagatesDeletesAtEndOfEvent {
    return _propagatesDeletesAtEndOfEvent;
}

- (NSTimeInterval) stalenessInterval {
    return _stalenessInterval;
}

- mergePolicy {
    return _mergePolicy;
}

- (BOOL)automaticallyMergesChangesFromParent { return _automaticallyMergesChangesFromParent; }
- (void)setAutomaticallyMergesChangesFromParent:(BOOL)value { _automaticallyMergesChangesFromParent = value; }

- (void)_siblingDidSave:(NSNotification *)notification {
    NSManagedObjectContext *source = [notification object];
    if (source == self || !_automaticallyMergesChangesFromParent || [source persistentStoreCoordinator] != _storeCoordinator) return;
    NSMutableDictionary *identifiers = [NSMutableDictionary dictionary];
    for (NSString *key in @[NSInsertedObjectsKey, NSUpdatedObjectsKey, NSDeletedObjectsKey]) {
        NSMutableArray *ids = [NSMutableArray array];
        for (NSManagedObject *object in [[notification userInfo] objectForKey:key]) [ids addObject:[object objectID]];
        [identifiers setObject:ids forKey:key];
    }
    void (^merge)(void) = ^{
        _mergingChanges = YES;
        @try {
            for (NSManagedObjectID *objectID in [identifiers objectForKey:NSUpdatedObjectsKey]) {
                NSManagedObject *object = [self objectRegisteredForID:objectID];
                if (object && ![_deletedObjects containsObject:object]) {
                    [object _mergeCommittedValues];
                    [_pendingUpdated addObject:object];
                }
            }
            for (NSManagedObjectID *objectID in [identifiers objectForKey:NSInsertedObjectsKey]) {
                NSManagedObject *object = [self objectWithID:objectID];
                [_pendingInserted addObject:object];
            }
            for (NSManagedObjectID *objectID in [identifiers objectForKey:NSDeletedObjectsKey]) {
                NSManagedObject *object = [self objectRegisteredForID:objectID];
                if (object && ![_updatedObjects containsObject:object]) {
                    [_pendingDeleted addObject:object];
                    [object _setInserted:NO updated:NO deleted:YES];
                    for (NSString *key in [[[object entity] propertiesByName] allKeys])
                        [object removeObserver:self forKeyPath:key];
                    [_registeredObjects removeObject:object];
                    NSMapRemove(_objectIdToObject, [object objectID]);
                }
            }
        } @finally { _mergingChanges = NO; }
        [self processPendingChanges];
    };
    if (_contextQueue) [self performBlock:merge]; else merge();
}

- (void) persistentStoresDidChange: (NSNotification *) note {
    NSArray *stores =
            [[note userInfo] objectForKey: NSRemovedPersistentStoresKey];

    for (NSPersistentStore *store in stores) {
        NSArray *allObjects = NSAllMapTableValues(_objectIdToObject);

        for (NSManagedObject *check in allObjects) {
            NSManagedObjectID *objectID = [check objectID];

            if ([objectID persistentStore] == store) {

                NSEntityDescription *entity = [check entity];
                NSArray *properties = [[entity propertiesByName] allKeys];

                for (NSString *key in properties)
                    [check removeObserver: self forKeyPath: key];

                [_registeredObjects removeObject: check];
                [_insertedObjects removeObject: check];
                [_updatedObjects removeObject: check];
                [_deletedObjects removeObject: check];
                NSMapRemove(_objectIdToObject, objectID);
            }
        }
    }
}

- (void) setPersistentStoreCoordinator: (NSPersistentStoreCoordinator *) value {
    if (_contextQueue && ![self _isOnContextQueue]) {
        [self performBlockAndWait:^{ [self setPersistentStoreCoordinator:value]; }];
        return;
    }
    if (_storeCoordinator != nil) {
        [[NSNotificationCenter defaultCenter]
                removeObserver: self
                          name: NSPersistentStoreCoordinatorStoresDidChangeNotification
                        object: _storeCoordinator];
    }

    value = [value retain];
    [_storeCoordinator release];
    _storeCoordinator = value;
    [[NSNotificationCenter defaultCenter] removeObserver:self name:NSManagedObjectContextDidSaveNotification object:nil];
    if (value) [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_siblingDidSave:) name:NSManagedObjectContextDidSaveNotification object:nil];

    if (_storeCoordinator != nil) {
        [[NSNotificationCenter defaultCenter]
                addObserver: self
                   selector: @selector(persistentStoresDidChange:)
                       name: NSPersistentStoreCoordinatorStoresDidChangeNotification
                     object: _storeCoordinator];
    }
}

- (void) setUndoManager: (NSUndoManager *) value {
    if (_contextQueue && ![self _isOnContextQueue]) {
        [self performBlockAndWait:^{ [self setUndoManager:value]; }];
        return;
    }
    value = [value retain];
    [_undoManager release];
    _undoManager = value;
}

- (void) setRetainsRegisteredObjects: (BOOL) value {
    if (_contextQueue && ![self _isOnContextQueue]) {
        [self performBlockAndWait:^{ [self setRetainsRegisteredObjects:value]; }];
        return;
    }
    _retainsRegisteredObjects = value;
    // FIXME: actually release/retain if needed
    NSUnimplementedMethod();
}

- (void) setPropagatesDeletesAtEndOfEvent: (BOOL) value {
    if (_contextQueue && ![self _isOnContextQueue]) {
        [self performBlockAndWait:^{ [self setPropagatesDeletesAtEndOfEvent:value]; }];
        return;
    }
    _propagatesDeletesAtEndOfEvent = value;
}

- (void) setStalenessInterval: (NSTimeInterval) value {
    if (_contextQueue && ![self _isOnContextQueue]) {
        [self performBlockAndWait:^{ [self setStalenessInterval:value]; }];
        return;
    }
    _stalenessInterval = value;
}

- (void) setMergePolicy: value {
    if (_contextQueue && ![self _isOnContextQueue]) {
        [self performBlockAndWait:^{ [self setMergePolicy:value]; }];
        return;
    }
    value = [value retain];
    [_mergePolicy release];
    _mergePolicy = value;
}

- (NSSet *) registeredObjects {
    return _registeredObjects;
}

- (NSSet *) insertedObjects {
    return _insertedObjects;
}

- (NSSet *) updatedObjects {
    return _updatedObjects;
}

- (NSSet *) deletedObjects {
    return _deletedObjects;
}

- (void) _setHasChanges: (BOOL) value {
    _hasChanges = value;
}

- (BOOL) hasChanges {
    return _hasChanges;
}

- (void) lock {
    [_lock lock];
}

- (void) unlock {
    [_lock unlock];
}

- (BOOL) tryLock {
    return [_lock tryLock];
}

- (void) undo {
    NSUnimplementedMethod();
}

- (void) redo {
    NSUnimplementedMethod();
}

- (void) reset {
    NSUnimplementedMethod();
}

- (void)rollback {
    for (NSManagedObject *object in _registeredObjects) [object _discardPendingValues];
    for (NSManagedObject *object in _insertedObjects) {
        for (NSString *key in [[[object entity] propertiesByName] allKeys]) [object removeObserver:self forKeyPath:key];
        [_registeredObjects removeObject:object];
        NSMapRemove(_objectIdToObject, [object objectID]);
    }
    [_insertedObjects removeAllObjects]; [_updatedObjects removeAllObjects]; [_deletedObjects removeAllObjects];
    [_pendingInserted removeAllObjects]; [_pendingUpdated removeAllObjects]; [_pendingDeleted removeAllObjects];
    _hasChanges = NO;
}

- (NSAtomicStoreCacheNode *) _cacheNodeForObjectID:
        (NSManagedObjectID *) objectID
{
    NSAtomicStore *store = (NSAtomicStore *) [_storeCoordinator
            _persistentStoreForObjectID: objectID];

    return [store cacheNodeForObjectID: objectID];
}

- (NSManagedObject *) objectRegisteredForID: (NSManagedObjectID *) objectID {
    return NSMapGet(_objectIdToObject, objectID);
}

- (void) _registerObject: (NSManagedObject *) object {
    [_registeredObjects addObject: object];
    NSMapInsert(_objectIdToObject, [object objectID], object);

    NSEntityDescription *entity = [object entity];
    NSDictionary *propsByName = [entity propertiesByName];
    NSArray *properties = [propsByName allKeys];

    for (NSString *key in properties) {
        [object addObserver: self
                 forKeyPath: key
                    options: NSKeyValueObservingOptionNew |
                             NSKeyValueObservingOptionOld
                    context: nil];
    }
}

- (NSManagedObject *) objectWithID: (NSManagedObjectID *) objectID {
    NSManagedObject *result = NSMapGet(_objectIdToObject, objectID);

    if (result == nil) {
        result = [[[NSManagedObject alloc] initWithObjectID: objectID
                                       managedObjectContext: self] autorelease];
        NSMapInsert(_objectIdToObject, objectID, result);
        [self _registerObject: result];
    }

    return result;
}

- (NSArray *) executeFetchRequest: (NSFetchRequest *) fetchRequest
                            error: (NSError **) error
{
    NSEntityDescription *requestedEntity = [fetchRequest entity];
    if (!requestedEntity) requestedEntity = [[[_storeCoordinator managedObjectModel] entitiesByName] objectForKey:[fetchRequest entityName]];
    BOOL supported = requestedEntity && [[[_storeCoordinator managedObjectModel] entities] containsObject:requestedEntity] &&
        [fetchRequest resultType] == NSManagedObjectResultType && ![fetchRequest fetchOffset] && ![fetchRequest fetchBatchSize] &&
        [fetchRequest includesPendingChanges] && ![fetchRequest returnsDistinctResults] && ![[fetchRequest propertiesToFetch] count] && ![[fetchRequest relationshipKeyPathsForPrefetching] count];
    NSPredicate *predicate = [fetchRequest predicate];
    if (predicate) {
        supported = supported && [predicate isKindOfClass:[NSComparisonPredicate class]];
        if (supported) {
            NSComparisonPredicate *comparison = (NSComparisonPredicate *)predicate;
            NSExpression *left = [comparison leftExpression], *right = [comparison rightExpression];
            supported = [comparison predicateOperatorType] == NSEqualToPredicateOperatorType && [comparison comparisonPredicateModifier] == NSDirectPredicateModifier && ![comparison options] &&
                [left expressionType] == NSKeyPathExpressionType && [right expressionType] == NSConstantValueExpressionType &&
                [[[requestedEntity attributesByName] objectForKey:[left keyPath]] attributeType] == NSStringAttributeType && [[right constantValue] isKindOfClass:[NSString class]];
        }
    }
    for (NSSortDescriptor *descriptor in [fetchRequest sortDescriptors]) {
        NSAttributeDescription *attribute = [[requestedEntity attributesByName] objectForKey:[descriptor key]];
        supported = supported && attribute && ([attribute attributeType] == NSStringAttributeType || [attribute attributeType] == NSDateAttributeType) &&
            [descriptor selector] == @selector(compare:);
    }
    if (!supported) {
        if (error) *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSPersistentStoreOperationError userInfo:nil];
        return nil;
    }
    NSArray *affectedStores = [fetchRequest affectedStores];

    if (affectedStores == nil)
        affectedStores = [_storeCoordinator persistentStores];

    NSMutableSet *resultSet = [NSMutableSet set];

    for (NSManagedObject *check in _registeredObjects) {
        NSEntityDescription *entity = [check entity];

        if ([entity _isKindOfEntity: requestedEntity]) {
            if (![_deletedObjects containsObject: check]) {
                if ([affectedStores count] == 0 ||
                    [[check objectID] persistentStore] == nil ||
                    [affectedStores containsObject: [[check objectID]
                                                            persistentStore]]) {
                    [resultSet addObject: check];
                }
            }
        }
    }

    for (NSManagedObject *check in _insertedObjects) {
        NSEntityDescription *entity = [check entity];

        if ([entity _isKindOfEntity: requestedEntity]) {
            if (![_deletedObjects containsObject: check]) {
                if ([affectedStores count] == 0 ||
                    [[check objectID] persistentStore] == nil ||
                    [affectedStores containsObject: [[check objectID]
                                                            persistentStore]]) {
                    [resultSet addObject: check];
                }
            }
        }
    }

    for (NSAtomicStore *store in affectedStores) {
        NSSet *nodes = [store cacheNodes];

        for (NSAtomicStoreCacheNode *node in nodes) {
            NSManagedObjectID *checkID = [node objectID];
            NSEntityDescription *entity = [checkID entity];

            if ([entity _isKindOfEntity: requestedEntity]) {
                NSManagedObject *check = [self objectWithID: checkID];

                if (![_deletedObjects containsObject: check]) {
                    [resultSet addObject: check];
                }
            }
        }
    }

    NSMutableArray *result =
            [NSMutableArray arrayWithArray: [resultSet allObjects]];

    NSPredicate *p = [fetchRequest predicate];

    if (p != nil) {
        [result filterUsingPredicate: p];
    }

    [result sortUsingDescriptors: [fetchRequest sortDescriptors]];

    NSUInteger fetchLimit = [fetchRequest fetchLimit];
    if (fetchLimit > 0 && [result count] > fetchLimit) {
        [result removeObjectsInRange: NSMakeRange(fetchLimit, [result count] - fetchLimit)];
    }

    return result;
}

- (NSUInteger) countForFetchRequest: (NSFetchRequest *) request
                              error: (NSError **) error
{
    NSArray *result = [self executeFetchRequest:request error:error];
    return result ? [result count] : NSNotFound;
}

- (void) insertObject: (NSManagedObject *) object {
    NSPersistentStore *store =
            [_storeCoordinator _persistentStoreForObject: object];

    [[object objectID] setStoreIdentifier: [store identifier]];
    [[object objectID] setPersistentStore: store];

    [_insertedObjects addObject: object];
    [object _setInserted:YES updated:NO deleted:NO];
    _hasChanges = YES;
    [_pendingInserted addObject:object];
    [self _registerObject:object];
    [self _requestProcessPendingChanges];
}

- (void) deleteObject: (NSManagedObject *) object {
    if ([object managedObjectContext] != self)
        [NSException raise:NSInvalidArgumentException format:@"The object belongs to another context."];
    for (NSRelationshipDescription *relationship in [[[object entity] relationshipsByName] allValues]) {
        if ([relationship deleteRule] != NSNullifyDeleteRule)
            [NSException raise:NSInvalidArgumentException format:@"Unsupported delete rule."];
        [object setValue:([relationship isToMany] ? (id)[NSSet set] : nil) forKey:[relationship name]];
    }
    [_deletedObjects addObject:object];
    [_pendingDeleted addObject:object];
    [_pendingUpdated removeObject:object];
    [object _setInserted:[_insertedObjects containsObject:object] updated:NO deleted:YES];
    _hasChanges = YES;
    [self _requestProcessPendingChanges];
}

- (void) assignObject: object toPersistentStore: (NSPersistentStore *) store {
    [object retain];

    NSMapRemove(_objectIdToObject, [object objectID]);

    [[object objectID] setStoreIdentifier: [store identifier]];

    [[object objectID] setPersistentStore: store];

    NSMapInsert(_objectIdToObject, [object objectID], object);
    [object release];
}

- (void) detectConflictsForObject: (NSManagedObject *) object {
    // NOT NEEDED
    NSUnimplementedMethod();
}

- (void) refreshObject: (NSManagedObject *) object mergeChanges: (BOOL) flag {
    // NEEDED
    NSUnimplementedMethod();
}

- (void) _requestProcessPendingChanges {
    if (!_requestedProcessPendingChanges) {
        if (_contextQueue) {
            _requestedProcessPendingChanges = YES;
            dispatch_async(_contextQueue, ^{ [self _processPendingChangesForRequest]; });
            return;
        }
        NSRunLoop *runLoop = [NSRunLoop mainRunLoop];
        [runLoop performSelector: @selector(_processPendingChangesForRequest)
                          target: self
                        argument: nil
                           order: 0
                           modes: [NSArray arrayWithObject:
                                                   NSRunLoopCommonModes]];
        _requestedProcessPendingChanges = YES;
    }
}

- (void) _processPendingChanges {
    _requestedProcessPendingChanges = NO;
    if ([_pendingInserted count] || [_pendingUpdated count] || [_pendingDeleted count]) {
        NSDictionary *changes = @{NSInsertedObjectsKey:[NSSet setWithSet:_pendingInserted], NSUpdatedObjectsKey:[NSSet setWithSet:_pendingUpdated], NSDeletedObjectsKey:[NSSet setWithSet:_pendingDeleted]};
        [_pendingInserted removeAllObjects]; [_pendingUpdated removeAllObjects]; [_pendingDeleted removeAllObjects];
        [[NSNotificationCenter defaultCenter] postNotificationName:NSManagedObjectContextObjectsDidChangeNotification object:self userInfo:changes];
    }
}

- (void) processPendingChanges {
    if (_requestedProcessPendingChanges && !_contextQueue) {
        [[NSRunLoop mainRunLoop] cancelPerformSelector: @selector
                                 (_processPendingChangesForRequest)
                                                target: self
                                              argument: nil];
    }

    [self _processPendingChanges];
}

- (void) _processPendingChangesForRequest {
    if (_requestedProcessPendingChanges)
        [self _processPendingChanges];
}

- (void) observeValueForKeyPath: (NSString *) keyPath
                       ofObject: (id) object
                         change: (NSDictionary *) change
                        context: (void *) context
{
    if (!_mergingChanges && NSMapGet(_objectIdToObject, [object objectID]) == object && ![_deletedObjects containsObject:object]) {
        if (![_insertedObjects containsObject:object]) {
            [_updatedObjects addObject:object];
            [object _setInserted:NO updated:YES deleted:NO];
        }
        if (![_pendingInserted containsObject:object])
            [_pendingUpdated addObject:object];
        _hasChanges = YES;
        [self _requestProcessPendingChanges];
    }
}

- (BOOL) obtainPermanentIDsForObjects: (NSArray *) objects
                                error: (NSError **) error
{

    for (NSManagedObject *check in objects) {
        NSManagedObjectID *checkID = [check objectID];

        if ([checkID isTemporaryID]) {
            NSAtomicStore *store = (NSAtomicStore *) [checkID persistentStore];

            NSMapRemove(_objectIdToObject, checkID);

            if (!store) {
                NSMapInsert(_objectIdToObject, checkID, check);
                if (error) *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSPersistentStoreIncompleteSaveError userInfo:nil];
                return NO;
            }

            id referenceObject =
                    [store newReferenceObjectForManagedObject: check];

            [checkID setReferenceObject:referenceObject];
            [referenceObject release];

            [store _uniqueObjectID: checkID];

            NSMapInsert(_objectIdToObject, checkID, check);
        }
    }

    return YES;
}

- (BOOL)save:(NSError **)error {
    [[NSNotificationCenter defaultCenter] postNotificationName:NSManagedObjectContextWillSaveNotification object:self];
    [self processPendingChanges];
    NSMutableSet *inserted = [NSMutableSet setWithSet:_insertedObjects];
    [inserted minusSet:_deletedObjects];
    if (![self obtainPermanentIDsForObjects:[inserted allObjects] error:error]) return NO;
    NSDictionary *changes = @{NSInsertedObjectsKey:[NSSet setWithSet:inserted], NSUpdatedObjectsKey:[NSSet setWithSet:_updatedObjects], NSDeletedObjectsKey:[NSSet setWithSet:_deletedObjects]};
    BOOL success = YES;
    [_storeCoordinator lock];
    @try {
        for (NSAtomicStore *store in [_storeCoordinator persistentStores]) {
            NSMutableSet *storeInserted = [NSMutableSet set], *storeUpdated = [NSMutableSet set], *storeDeleted = [NSMutableSet set];
            for (NSManagedObject *object in inserted) if ([[object objectID] persistentStore] == store) [storeInserted addObject:object];
            for (NSManagedObject *object in _updatedObjects) if ([[object objectID] persistentStore] == store) [storeUpdated addObject:object];
            for (NSManagedObject *object in _deletedObjects)
                if ([[object objectID] persistentStore] == store && ![_insertedObjects containsObject:object])
                    [storeDeleted addObject:object];
            if (![storeInserted count] && ![storeUpdated count] && ![storeDeleted count]) continue;
            if ([store isKindOfClass:[NSSQLitePersistentStore class]]) {
                success = [(NSSQLitePersistentStore *)store _commitInserted:storeInserted updated:storeUpdated deleted:storeDeleted error:error];
            } else {
                for (NSManagedObject *object in storeDeleted) {
                    NSAtomicStoreCacheNode *node = [store cacheNodeForObjectID:[object objectID]];
                    if (node) [store willRemoveCacheNodes:[NSSet setWithObject:node]];
                }
                for (NSManagedObject *object in storeInserted) {
                    NSAtomicStoreCacheNode *node = [store newCacheNodeForManagedObject:object];
                    [store addCacheNodes:[NSSet setWithObject:node]];
                    [node release];
                }
                for (NSManagedObject *object in storeUpdated) if (![storeDeleted containsObject:object]) [store updateCacheNode:[store cacheNodeForObjectID:[object objectID]] fromManagedObject:object];
                success = [store save:error];
            }
            if (!success) break;
        }
        if (success) {
            for (NSManagedObject *object in _registeredObjects) {
                if ([_deletedObjects containsObject:object]) continue;
                if ([inserted containsObject:object] || [_updatedObjects containsObject:object]) [object _didCommit];
            }
            for (NSManagedObject *object in _deletedObjects) {
                NSMapRemove(_objectIdToObject, [object objectID]);
                [_registeredObjects removeObject:object];
            }
            [_insertedObjects removeAllObjects]; [_updatedObjects removeAllObjects]; [_deletedObjects removeAllObjects];
            _hasChanges = NO;
        }
    } @finally { [_storeCoordinator unlock]; }
    if (!success) return NO;
    [[NSNotificationCenter defaultCenter] postNotificationName:NSManagedObjectContextDidSaveNotification object:self userInfo:changes];
    return YES;
}

- (void) mergeChangesFromContextDidSaveNotification:
        (NSNotification *) notification
{
    NSUnimplementedMethod();
}

- (BOOL) commitEditing {
    NSUnimplementedMethod();
    return NO;
}

- (void) commitEditingWithDelegate: (id) delegate
                 didCommitSelector: (SEL) didCommitSelector
                       contextInfo: (void *) contextInfo
{
    NSUnimplementedMethod();
}

- (void) discardEditing {
    NSUnimplementedMethod();
}

- (void) objectDidBeginEditing: (id) editor {
    NSUnimplementedMethod();
}

- (void) objectDidEndEditing: (id) editor {
    NSUnimplementedMethod();
}

@end
