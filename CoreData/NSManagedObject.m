/* Copyright (c) 2008 Dan Knapp

Permission is hereby granted, free of charge, to any person obtaining a copy of
this software and associated documentation files (the "Software"), to deal in
the Software without restriction, including without limitation the rights to
use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
the Software, and to permit persons to whom the Software is furnished to do so,
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
#import "NSManagedObjectContext-Private.h"
#import "NSManagedObjectID-Private.h"
#import "NSManagedObjectMutableSet.h"
#import "NSManagedObjectSet.h"
#import "NSManagedObjectSetEnumerator.h"
#import <CoreData/NSAtomicStoreCacheNode.h>
#import <CoreData/NSAttributeDescription.h>
#import <CoreData/NSManagedObject.h>
#import <CoreData/NSManagedObjectModel.h>
#import <CoreData/NSPersistentStoreCoordinator.h>
#import <CoreData/NSFetchRequest.h>
#import "NSManagedObjectModel-Private.h"
#import "NSSQLitePersistentStore.h"
#import <CoreData/NSRelationshipDescription.h>
#import <Foundation/NSRaise.h>

NSString *const NSValidationKeyErrorKey = @"NSValidationErrorKey";
NSString *const NSValidationObjectErrorKey = @"NSValidationErrorObject";
NSString *const NSValidationPredicateErrorKey = @"NSValidationErrorPredicate";
NSString *const NSValidationValueErrorKey = @"NSValidationErrorValue";

@implementation NSManagedObject

+ (NSEntityDescription *)entity {
    return [NSManagedObjectModel _entityForManagedClass:self];
}

+ (NSFetchRequest *)fetchRequest {
    NSFetchRequest *request = [[[NSFetchRequest alloc] init] autorelease];
    [request setEntity:[self entity]];
    return request;
}

- (instancetype)initWithContext:(NSManagedObjectContext *)context {
    NSEntityDescription *match = nil;
    for (NSEntityDescription *entity in [[[context persistentStoreCoordinator] managedObjectModel] entities]) {
        if (NSClassFromString([entity managedObjectClassName]) == [self class]) {
            if (match) [NSException raise:NSInvalidArgumentException format:@"Multiple entities represent this managed class."];
            match = entity;
        }
    }
    if (!match) [NSException raise:NSInvalidArgumentException format:@"No entity represents this managed class in the context."];
    return [self initWithEntity:match insertIntoManagedObjectContext:context];
}

- init {
    NSLog(@"Error - can't initialize an NSManagedObject with -init");
    return nil;
}

- initWithObjectID: (NSManagedObjectID *) objectID
        managedObjectContext: (NSManagedObjectContext *) context
{
    NSEntityDescription *entity = [objectID entity];
    [entity _prepareAccessors];
    NSString *className = [entity managedObjectClassName];
    Class class = NSClassFromString(className);

    if (class == Nil) {
        NSLog(@"Unable to find class %@ specified by entity %@ in the runtime, "
              @"using NSManagedObject,objectID=%@",
              className, [entity name], objectID);

        class = [NSManagedObject class];
    }

    [super dealloc];
    self = [class allocWithZone: NULL];

    _objectID = [objectID copy];
    _context = context;
    _committedValues = nil;
    _changedValues = [[NSMutableDictionary alloc] init];
    _isFault = YES;
    if (![objectID isTemporaryID]) {
        [self _committedValues];
        if ([[objectID persistentStore] isKindOfClass:[NSSQLitePersistentStore class]])
            _storeVersion = [(NSSQLitePersistentStore *)[objectID persistentStore] _versionForObjectID:objectID];
    }
    return self;
}

- initWithEntity: (NSEntityDescription *) entity
        insertIntoManagedObjectContext: (NSManagedObjectContext *) context
{
    NSManagedObjectID *objectID =
            [[[NSManagedObjectID alloc] initWithEntity: entity] autorelease];

    if ((self = [self initWithObjectID: objectID
                  managedObjectContext: context]) == nil)
        return nil;

    NSDictionary *attributes = [entity attributesByName];
    NSEnumerator *state = [attributes keyEnumerator];
    NSString *key;

    while ((key = [state nextObject]) != nil) {
        id object = [attributes objectForKey: key];
        id value = [object defaultValue];

        if (value != nil)
            [self setPrimitiveValue: value forKey: key];
    }

    [context insertObject: self];

    return self;
}

- (void) dealloc {
    [self didTurnIntoFault];

    [_objectID release];
    [_changedValues release];
    [_committedValues release];
    [super dealloc];
}

- (NSUInteger) hash {
    return [_objectID hash];
}

- (BOOL) isEqual: otherX {
    if (![otherX isKindOfClass: [NSManagedObject class]])
        return NO;

    NSManagedObject *other = otherX;

    return [_objectID isEqual: other->_objectID];
}

- (NSEntityDescription *) entity {
    return [_objectID entity];
}

- (NSManagedObjectID *) objectID {
    return _objectID;
}

- self {
    return self;
}

- (NSManagedObjectContext *) managedObjectContext {
    return _context;
}

- (BOOL) isInserted {
    return _isInserted;
}

- (BOOL) isUpdated {
    return _isUpdated;
}

- (BOOL) isDeleted {
    return _isDeleted;
}

- (BOOL) isFault {
    return _isFault;
}

- (BOOL) hasFaultForRelationshipNamed: (NSString *) key {
    NSUnimplementedMethod();
    return NO;
}

- (void) awakeFromFetch {
    NSUnimplementedMethod();
}

- (void) awakeFromInsert {
    NSUnimplementedMethod();
}

- (NSDictionary *) changedValues {
    return _changedValues;
}

- (NSDictionary *) _committedValues {
    NSManagedObjectContext *parent = [_context parentContext];

    if (parent != nil) {
        // A child context starts from the values its parent has for the object (including the
        // parent's unsaved changes); an object inserted in the child itself has none.
        if (_committedValues == nil && !_isInserted) {
            NSDictionary *snapshot = [parent _snapshotForObjectID: [self objectID]];

            if (snapshot != nil) {
                NSMutableDictionary *values = [[NSMutableDictionary alloc] init];

                for (NSString *key in snapshot) {
                    id value = [snapshot objectForKey: key];

                    [values setObject: ([value isKindOfClass: [NSSet class]] ? [[value copy] autorelease] : value)
                               forKey: key];
                }
                _committedValues = values;
            }
        }
        return _committedValues;
    }
    if ([[self objectID] isTemporaryID])
        return nil;

    if (_committedValues == nil) {
        NSAtomicStoreCacheNode *node =
                [_context _cacheNodeForObjectID: [self objectID]];
        NSDictionary *propertyCache = [node propertyCache];
        NSMutableDictionary *storedValues = [[NSMutableDictionary alloc] init];

        NSArray *properties = [[self entity] properties];

        for (NSPropertyDescription *property in properties) {
            NSString *name = [property name];

            if ([property isKindOfClass: [NSAttributeDescription class]]) {
                id value = [propertyCache objectForKey: name];

                if (value != nil) {
                    [storedValues setObject: value forKey: name];
                }
            } else if ([property isKindOfClass: [NSRelationshipDescription
                                                        class]]) {
                NSRelationshipDescription *relationship =
                        (NSRelationshipDescription *) property;
                id indirectValue = [propertyCache objectForKey: name];

                if (indirectValue != nil) {
                    id value;

                    if (![relationship isToMany])
                        value = [indirectValue objectID];
                    else {
                        value = [NSMutableSet set];

                        for (NSAtomicStoreCacheNode *relNode in indirectValue) {
                            [value addObject: [relNode objectID]];
                        }
                    }

                    [storedValues setObject: value forKey: name];
                }
            }
        }

        [_committedValues release];
        _committedValues = storedValues;
    }
    return _committedValues;
}

- (NSDictionary *) committedValuesForKeys: (NSArray *) keys {
    if (keys == nil)
        return [self _committedValues];
    else {
        NSMutableDictionary *result = [NSMutableDictionary dictionary];

        for (NSString *key in keys) {
            id object = [[self _committedValues] objectForKey: key];

            if (object != nil) {
                [result setObject: object forKey: key];
            }
        }

        return result;
    }
}

- (void)_setInserted:(BOOL)inserted updated:(BOOL)updated deleted:(BOOL)deleted {
    _isInserted = inserted; _isUpdated = updated; _isDeleted = deleted;
}

- (long long)_storeVersion { return _storeVersion; }

- (void)_mergeCommittedValues {
    NSArray *keys = [[[self entity] propertiesByName] allKeys];
    for (NSString *key in keys) [self willChangeValueForKey:key];
    [_committedValues release]; _committedValues = nil;
    [self _committedValues];
    if ([[_objectID persistentStore] isKindOfClass:[NSSQLitePersistentStore class]])
        _storeVersion = [(NSSQLitePersistentStore *)[_objectID persistentStore] _versionForObjectID:_objectID];
    for (NSString *key in keys) [self didChangeValueForKey:key];
}

- (void)_discardPendingValues {
    [_changedValues removeAllObjects];
    _isInserted = _isUpdated = _isDeleted = NO;
}

- (void)_didCommit {
    [_changedValues removeAllObjects];
    [_committedValues release];
    _committedValues = nil;
    [self _committedValues];
    if ([[_objectID persistentStore] isKindOfClass:[NSSQLitePersistentStore class]])
        _storeVersion = [(NSSQLitePersistentStore *)[_objectID persistentStore] _versionForObjectID:_objectID];
    _isInserted = _isUpdated = NO;
    _isFault = NO;
    [self didSave];
}

- (void) didSave {
}

- (void) willTurnIntoFault {
    // do nothing per doc.s
}

- (void) didTurnIntoFault {
    // do nothing also?
}

- (void) willSave {
}

- valueForKey: (NSString *) key {
    if (!key)
        return [self valueForUndefinedKey: nil];

    NSPropertyDescription *property =
            [[self entity] _propertyForSelector: NSSelectorFromString(key)];
    NSString *propertyName = [property name];

    if ([property isKindOfClass: [NSAttributeDescription class]]) {
        [self willAccessValueForKey: propertyName];

        id result = [self primitiveValueForKey: propertyName];

        [self didAccessValueForKey: propertyName];

        return result;
    } else if ([property isKindOfClass: [NSRelationshipDescription class]]) {
        NSRelationshipDescription *relationship =
                (NSRelationshipDescription *) property;

        [self willAccessValueForKey: propertyName];

        id result = [self primitiveValueForKey: propertyName];

        if ([relationship isToMany] && !result)
            result = [NSSet set];
        if (result != nil) {
            if ([relationship isToMany])
                result = [[[NSManagedObjectSet alloc]
                        initWithManagedObjectContext: _context
                                                 set: result] autorelease];
            else
                result = [_context objectWithID: result];
        }

        [self didAccessValueForKey: propertyName];

        return result;
    }

    return [super valueForKey: key];
}

- (void) setValue: value forKey: (NSString *) key {
    NSPropertyDescription *property =
            [[self entity] _propertyForSelector: NSSelectorFromString(key)];
    NSString *propertyName = [property name];

    if ([property isKindOfClass: [NSAttributeDescription class]]) {
        [self willChangeValueForKey: propertyName];
        [self setPrimitiveValue: value forKey: propertyName];
        [self didChangeValueForKey: propertyName];
        return;
    } else if ([property isKindOfClass: [NSRelationshipDescription class]]) {
        NSRelationshipDescription *relationship = (NSRelationshipDescription *)property;
        NSRelationshipDescription *inverse = [relationship inverseRelationship];
        NSMutableSet *newIDs = [NSMutableSet set];
        NSSet *newObjects = [relationship isToMany] ? value : (value ? [NSSet setWithObject:value] : [NSSet set]);
        for (NSManagedObject *target in newObjects) {
            if (![target isKindOfClass:[NSManagedObject class]] || [target managedObjectContext] != _context || [target entity] != [relationship destinationEntity])
                [NSException raise:NSInvalidArgumentException format:@"A relationship requires objects in this context with the declared entity."];
            [newIDs addObject:[target objectID]];
        }
        id previous = [self primitiveValueForKey:propertyName];
        NSSet *oldIDs = [relationship isToMany] ? (previous ?: [NSSet set]) : (previous ? [NSSet setWithObject:previous] : [NSSet set]);
        oldIDs = [[oldIDs copy] autorelease];
        [self willChangeValueForKey:propertyName];
        [self setPrimitiveValue:([relationship isToMany] ? (id)newIDs : [newIDs anyObject]) forKey:propertyName];
        [self didChangeValueForKey:propertyName];
        if (inverse) {
            NSString *inverseName = [inverse name];
            NSMutableSet *allIDs = [NSMutableSet setWithSet:oldIDs];
            [allIDs unionSet:newIDs];
            for (NSManagedObjectID *targetID in allIDs) {
                BOOL added = [newIDs containsObject:targetID];
                NSManagedObject *target = [_context objectWithID:targetID];
                id oldInverse = [target primitiveValueForKey:inverseName];
                if (added && ![inverse isToMany] && oldInverse && oldInverse != [self objectID]) {
                    NSManagedObject *oldOwner = [_context objectWithID:oldInverse];
                    id oldOwnerValue = [oldOwner primitiveValueForKey:propertyName];
                    [oldOwner willChangeValueForKey:propertyName];
                    if ([relationship isToMany]) {
                        NSMutableSet *remaining = [NSMutableSet setWithSet:oldOwnerValue ?: [NSSet set]];
                        [remaining removeObject:targetID];
                        [oldOwner setPrimitiveValue:remaining forKey:propertyName];
                    } else [oldOwner setPrimitiveValue:nil forKey:propertyName];
                    [oldOwner didChangeValueForKey:propertyName];
                }
                [target willChangeValueForKey:inverseName];
                if ([inverse isToMany]) {
                    NSMutableSet *set = [NSMutableSet setWithSet:oldInverse ?: [NSSet set]];
                    if (added) [set addObject:[self objectID]]; else [set removeObject:[self objectID]];
                    [target setPrimitiveValue:set forKey:inverseName];
                } else if (added || oldInverse == [self objectID]) {
                    [target setPrimitiveValue:(added ? [self objectID] : nil) forKey:inverseName];
                }
                [target didChangeValueForKey:inverseName];
            }
        }
        return;
    }

    [super setValue: value forKey: key];
}

- (NSMutableSet *) mutableSetValueForKey: (NSString *) key {
    return [[[NSManagedObjectMutableSet alloc] initWithManagedObject: self
                                                                 key: key]
            autorelease];
}

- primitiveValueForKey: (NSString *) key {
    id result = [_changedValues objectForKey: key];

    if (result == nil)
        result = [[self _committedValues] objectForKey: key];

    return result == [NSNull null] ? nil : result;
}

- (void) setPrimitiveValue: value forKey: (NSString *) key {
    [_changedValues setObject:(value ?: [NSNull null]) forKey:key];
}

- (BOOL) validateValue: (id *) value
                forKey: (NSString *) key
                 error: (NSError **) error
{
    NSUnimplementedMethod();
    return YES;
}

- (BOOL) validateForDelete: (NSError **) error {
    NSUnimplementedMethod();
    return YES;
}

- (BOOL) validateForInsert: (NSError **) error {
    NSUnimplementedMethod();
    return YES;
}

- (BOOL) validateForUpdate: (NSError **) error {
    NSUnimplementedMethod();
    return YES;
}

+ (BOOL) automaticallyNotifiesObserversForKey: (NSString *) key {
    // FIXME: Doc.s for NSManagedObject state this returns YES for unmodeled
    // properties.

    return NO;
}

- (void) didAccessValueForKey: (NSString *) key {
}

- (void *) observationInfo {
    return _observationInfo;
}

- (void) setObservationInfo: (void *) value {
    _observationInfo = value;
}

- (void) willAccessValueForKey: (NSString *) key {
}

- (NSString *) description {
    NSMutableDictionary *values = [NSMutableDictionary
            dictionaryWithDictionary: [self _committedValues]];

    [values addEntriesFromDictionary: _changedValues];

    return [NSString
            stringWithFormat: @"<%@ %x:objectID=%@ entity name=%@, values=%@>",
                              [self class], self, _objectID, [self entity],
                              values];
}

@end
