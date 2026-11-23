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
#import <CoreData/CoreDataErrors.h>
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

// The text of the validation errors: the descriptions macOS gives each code (observed on macOS 10.14.4
// and 26.7.3, which agree), with the property placeholder left in the text as there.
static NSString *DarlingValidationDescription(NSInteger code) {
    switch (code) {
    case NSValidationMissingMandatoryPropertyError:
        return @"%{PROPERTY}@ is a required value.";
    case NSValidationRelationshipLacksMinimumCountError:
        return @"Too few items in %{PROPERTY}@.";
    case NSValidationRelationshipExceedsMaximumCountError:
        return @"Too many items in %{PROPERTY}@.";
    case NSValidationRelationshipDeniedDeleteError:
        return @"Items cannot be deleted from %{PROPERTY}@.";
    case NSValidationMultipleErrorsError:
        return @"Multiple validation errors occurred.";
    default:
        return nil;
    }
}

// An error of a validation failure of one property: the key, the object and, when there is one, the
// offending value, as macOS puts them in the user info.
static NSError *DarlingValidationError(NSInteger code, NSManagedObject *object, NSString *key, id value) {
    NSMutableDictionary *info = [NSMutableDictionary dictionary];
    NSString *description = DarlingValidationDescription(code);

    if (description != nil)
        [info setObject: description forKey: NSLocalizedDescriptionKey];
    [info setObject: object forKey: NSValidationObjectErrorKey];
    if (key != nil)
        [info setObject: key forKey: NSValidationKeyErrorKey];
    if (value != nil && value != [NSNull null])
        [info setObject: value forKey: NSValidationValueErrorKey];
    return [NSError errorWithDomain: NSCocoaErrorDomain code: code userInfo: info];
}

// One failure is returned as it is; several are collected under NSDetailedErrorsKey in an error of
// the "multiple errors" code (observed on both Macs, also for a validate<Key>:error: failure that
// comes together with a failed model check). A NULL error output asks the callers' loops to stop
// at the first failure, which they do themselves.
static BOOL DarlingReportErrors(NSArray *errors, NSError **error) {
    if ([errors count] == 0)
        return YES;
    if (error != NULL) {
        if ([errors count] == 1)
            *error = [errors objectAtIndex: 0];
        else
            *error = [NSError errorWithDomain: NSCocoaErrorDomain
                                         code: NSValidationMultipleErrorsError
                                     userInfo: [NSDictionary dictionaryWithObjectsAndKeys:
                                                                     errors, NSDetailedErrorsKey,
                                                                     DarlingValidationDescription(NSValidationMultipleErrorsError),
                                                                     NSLocalizedDescriptionKey, nil]];
    }
    return NO;
}

// The checks the property description itself settles: a missing value for a non-optional property
// (attribute, to-one or to-many relationship) and the count limits of a to-many relationship.
// Returns nil when the value is acceptable. macOS does not check the class of an attribute value
// here: a string for a number attribute passes and stays a string (observed on both Macs).
static NSError *DarlingBasicValidationFailure(NSManagedObject *object, NSPropertyDescription *property, id value) {
    NSString *key = [property name];

    if ([property isKindOfClass: [NSAttributeDescription class]]) {
        if ((value == nil || value == [NSNull null]) && ![property isOptional])
            return DarlingValidationError(NSValidationMissingMandatoryPropertyError, object, key, nil);
        return nil;
    }

    if ([property isKindOfClass: [NSRelationshipDescription class]]) {
        NSRelationshipDescription *relationship = (NSRelationshipDescription *) property;

        if (![relationship isToMany])
            return (value == nil && ![relationship isOptional])
                    ? DarlingValidationError(NSValidationMissingMandatoryPropertyError, object, key, nil)
                    : nil;

        NSUInteger count = [value respondsToSelector: @selector(count)] ? [value count] : 0;

        // An optional relationship that is empty skips the limits; a non-optional one is checked,
        // and a missing set counts as empty (macOS gives the same results for min and max counts).
        if (count == 0 && [relationship isOptional])
            return nil;
        if (count < [relationship minCount])
            return DarlingValidationError(NSValidationRelationshipLacksMinimumCountError, object, key, value);
        if ([relationship maxCount] > 0 && count > [relationship maxCount])
            return DarlingValidationError(NSValidationRelationshipExceedsMaximumCountError, object, key, value);
    }
    return nil;
}

// validateForInsert: and validateForUpdate: validate every property through the object's own
// validateValue:forKey:error:, so overrides take part (macOS gives the same results for both).
static BOOL DarlingValidateAllProperties(NSManagedObject *object, NSError **error) {
    NSMutableArray *errors = [NSMutableArray array];
    NSDictionary *properties = [[object entity] propertiesByName];

    for (NSString *key in [[properties allKeys] sortedArrayUsingSelector: @selector(compare:)]) {
        id value = [object valueForKey: key];
        NSError *failure = nil;

        if (![object validateValue: &value forKey: key error: &failure]) {
            [errors addObject: failure != nil ? failure
                                              : DarlingValidationError(NSManagedObjectValidationError, object, key, value)];
            if (error == NULL)
                break;
        }
    }
    return DarlingReportErrors(errors, error);
}

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

// An unsaved inserted object that is refreshed without merging: its values and its insertion go.
- (void)_discardInsertedValues {
    NSArray *keys = [[[self entity] propertiesByName] allKeys];
    for (NSString *key in keys) [self willChangeValueForKey:key];
    [_changedValues removeAllObjects];
    _isInserted = _isUpdated = _isDeleted = NO;
    for (NSString *key in keys) [self didChangeValueForKey:key];
}

- (void)_mergeCommittedValues {
    [self _reloadCommittedValuesDiscardingChanges:NO];
}

// Reloads the committed values from the store's cache, optionally dropping the object's own
// changes (and its updated and deleted state) in the same observed step.
- (void)_reloadCommittedValuesDiscardingChanges:(BOOL)discard {
    NSArray *keys = [[[self entity] propertiesByName] allKeys];
    for (NSString *key in keys) [self willChangeValueForKey:key];
    if (discard) {
        [_changedValues removeAllObjects];
        _isUpdated = _isDeleted = NO;
    }
    [_committedValues release]; _committedValues = nil;
    [self _committedValues];
    if ([[_objectID persistentStore] isKindOfClass:[NSSQLitePersistentStore class]])
        _storeVersion = [(NSSQLitePersistentStore *)[_objectID persistentStore] _versionForObjectID:_objectID];
    for (NSString *key in keys) [self didChangeValueForKey:key];
}

// A value that an undo set back to the committed one is no change any more.
- (void)_dropChangedValuesEqualToCommitted {
    NSDictionary *committed = [self _committedValues];

    for (NSString *key in [_changedValues allKeys]) {
        id changed = [_changedValues objectForKey:key];
        id stored = [committed objectForKey:key];

        if (changed == stored || (stored != nil && [changed isEqual:stored]) || (stored == nil && changed == [NSNull null]))
            [_changedValues removeObjectForKey:key];
    }
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
    NSMutableArray *errors = [NSMutableArray array];

    // The documented hook: a method validate<Key>:error: of the object is invoked when there is one.
    // It is invoked first and always, whatever the model says (also for nil), and may replace the
    // value; the model checks then see that value, and a failure of both is reported as several
    // errors (observed on macOS 10.14.4 and 26.7.3).
    if ([key length] > 0) {
        SEL hook = NSSelectorFromString([NSString stringWithFormat: @"validate%@%@:error:",
                                                  [[key substringToIndex: 1] uppercaseString],
                                                  [key substringFromIndex: 1]]);

        if ([self respondsToSelector: hook]) {
            BOOL (*validator)(id, SEL, id *, NSError **) = (BOOL (*)(id, SEL, id *, NSError **)) [self methodForSelector: hook];
            NSError *hookError = nil;

            if (!validator(self, hook, value, &hookError))
                [errors addObject: hookError != nil ? hookError
                                                    : DarlingValidationError(NSManagedObjectValidationError, self, key, *value)];
        }
    }

    NSPropertyDescription *property = [[[self entity] propertiesByName] objectForKey: key];

    if (property != nil) {
        NSError *failure = DarlingBasicValidationFailure(self, property, *value);

        if (failure != nil)
            [errors addObject: failure];
    }
    return DarlingReportErrors(errors, error);
}

- (BOOL) validateForInsert: (NSError **) error {
    return DarlingValidateAllProperties(self, error);
}

- (BOOL) validateForUpdate: (NSError **) error {
    return DarlingValidateAllProperties(self, error);
}

// QUIRK: every relationship whose delete rule is not "no action" and that has a destination object
// fails the check, with NSValidationRelationshipDeniedDeleteError, not just deny rules: on macOS a
// direct call of validateForDelete: on an object with a nullify, cascade or deny relationship that
// is not empty fails alike, with a to-one or to-many relationship, with or without an inverse; only
// the no-action rule passes. The documentation speaks of the deny rule only. Evidence: black-box
// observation on macOS 10.14.4 and 26.7.3 (tier 2), probes val2.m and val3.m of batch11b. Test:
// tests/coredata-managed-object-validation.m, "delete rules (QUIRK)".
- (BOOL) validateForDelete: (NSError **) error {
    NSMutableArray *errors = [NSMutableArray array];

    NSDictionary *relationships = [[self entity] relationshipsByName];

    for (NSString *name in [[relationships allKeys] sortedArrayUsingSelector: @selector(compare:)]) {
        NSRelationshipDescription *relationship = [relationships objectForKey: name];

        if ([relationship deleteRule] == NSNoActionDeleteRule)
            continue;

        id value = [self primitiveValueForKey: [relationship name]];
        BOOL hasDestination = [relationship isToMany] ? [value count] > 0 : value != nil;

        if (hasDestination) {
            [errors addObject: DarlingValidationError(NSValidationRelationshipDeniedDeleteError, self,
                                                      [relationship name], value)];
            if (error == NULL)
                break;
        }
    }
    return DarlingReportErrors(errors, error);
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
