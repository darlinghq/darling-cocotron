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
#import <CoreData/NSAttributeDescription.h>
#import <CoreData/NSManagedObject.h>
#import <CoreData/NSManagedObjectContext.h>
#import <CoreData/NSManagedObjectModel.h>
#import <CoreData/NSPersistentStoreCoordinator.h>
#import <CoreData/NSPropertyDescription.h>
#import <CoreData/NSRelationshipDescription.h>
#import <Foundation/NSKeyedUnarchiver.h>
#import <Foundation/NSRaise.h>
#import <ctype.h>
#import "NSEntityDescription-Private.h"
#import "NSPropertyDescription-Private.h"
#import "NSManagedObjectModel-Private.h"
#import <objc/objc-class.h>
#import <stdint.h>
#import <string.h>

@implementation NSEntityDescription

- init {
    self = [super init];
    if (self) {
        _properties = [[NSMutableDictionary alloc] init];
        _subentities = [[NSMutableDictionary alloc] init];
        _selectorPropertyMap = [[NSMutableDictionary alloc] init];
    }
    return self;
}

- (void)_setManagedObjectModel:(NSManagedObjectModel *)model {
    _model = model;
}

- (void)_setInUse {
    _hasBeenInstantiated = YES;
}

- (void)_renameProperty:(NSPropertyDescription *)property from:(NSString *)oldName to:(NSString *)newName {
    NSPropertyDescription *existing = [_properties objectForKey:newName];
    if (existing && existing != property)
        [NSException raise:NSInvalidArgumentException format:@"Property names must be unique within an entity."];
    [_properties setObject:property forKey:newName];
    if (oldName && ![oldName isEqual:newName])
        [_properties removeObjectForKey:oldName];
}

static id getValue(id self, SEL selector) {
    NSPropertyDescription *property =
            [[self entity] _propertyForSelector: selector];
    id result = [self valueForKey: [property name]];
    return result;
}

static void setValue(id self, SEL selector, id newValue) {
    NSPropertyDescription *property =
            [[self entity] _propertyForSelector: selector];
    [self setValue: newValue forKey: [property name]];
}

static void addObject(id self, SEL selector, id value) {
    NSPropertyDescription *property =
            [[self entity] _propertyForSelector: selector];
    NSMutableSet *set = [self mutableSetValueForKey: [property name]];

    [set addObject: value];
}

static void removeObject(id self, SEL selector, id value) {
    NSPropertyDescription *property =
            [[self entity] _propertyForSelector: selector];
    NSMutableSet *set = [self mutableSetValueForKey: [property name]];
    [set removeObject: value];
}

static void addObjectSet(id self, SEL selector, NSSet *values) {
    NSPropertyDescription *property =
            [[self entity] _propertyForSelector: selector];
    NSMutableSet *set = [self mutableSetValueForKey: [property name]];
    [set unionSet: values];
}

static void removeObjectSet(id self, SEL selector, NSSet *values) {
    NSPropertyDescription *property =
            [[self entity] _propertyForSelector: selector];
    NSMutableSet *set = [self mutableSetValueForKey: [property name]];
    [set minusSet: values];
}

id keyObjectForSelector(SEL selector) {
    return [NSNumber numberWithInteger: (NSInteger) selector];
}

static BOOL isGeneratedManagedAccessor(IMP implementation);

static void appendMethodToList(Class class, NSString *selectorName, IMP imp,
                               const char *types, SEL *selectorp)
{

    SEL selector = NSSelectorFromString(selectorName);

    Method existing = class_getInstanceMethod(class, selector);
    if (!existing || isGeneratedManagedAccessor(method_getImplementation(existing)))
        class_addMethod(class, selector, imp, types);

    *selectorp = selector;
}

#define SCALAR_ACCESSORS(SUFFIX, TYPE, GET, BOX) \
static TYPE get##SUFFIX(id object, SEL selector) { return [[object valueForKey:[[[object entity] _propertyForSelector:selector] name]] GET]; } \
static void set##SUFFIX(id object, SEL selector, TYPE value) { [object setValue:[NSNumber BOX:value] forKey:[[[object entity] _propertyForSelector:selector] name]]; }
SCALAR_ACCESSORS(Char, signed char, charValue, numberWithChar)
SCALAR_ACCESSORS(Bool, _Bool, boolValue, numberWithBool)
SCALAR_ACCESSORS(Short, short, shortValue, numberWithShort)
SCALAR_ACCESSORS(Int, int, intValue, numberWithInt)
SCALAR_ACCESSORS(Long, long, longValue, numberWithLong)
SCALAR_ACCESSORS(LongLong, long long, longLongValue, numberWithLongLong)
SCALAR_ACCESSORS(Float, float, floatValue, numberWithFloat)
SCALAR_ACCESSORS(Double, double, doubleValue, numberWithDouble)
#undef SCALAR_ACCESSORS

static BOOL isGeneratedManagedAccessor(IMP implementation) {
    const IMP generated[] = {
        (IMP)getValue, (IMP)setValue, (IMP)addObject, (IMP)removeObject,
        (IMP)addObjectSet, (IMP)removeObjectSet,
        (IMP)getChar, (IMP)setChar, (IMP)getBool, (IMP)setBool,
        (IMP)getShort, (IMP)setShort, (IMP)getInt, (IMP)setInt,
        (IMP)getLong, (IMP)setLong, (IMP)getLongLong, (IMP)setLongLong,
        (IMP)getFloat, (IMP)setFloat, (IMP)getDouble, (IMP)setDouble
    };
    for (NSUInteger index = 0; index < sizeof(generated) / sizeof(generated[0]); index++)
        if (implementation == generated[index]) return YES;
    return NO;
}

- (void)_prepareAccessors {
    Class managedClass = NSClassFromString([self managedObjectClassName]);
    if (!managedClass || ![managedClass isSubclassOfClass:[NSManagedObject class]])
        [NSException raise:NSInvalidArgumentException format:@"The managed class must exist and inherit NSManagedObject."];
    @synchronized(managedClass) {
        for (NSPropertyDescription *property in [self properties]) {
            NSString *name = [property name];
            NSString *upper = [[[name substringToIndex:1] uppercaseString] stringByAppendingString:[name substringFromIndex:1]];
            NSString *getter = name;
            NSString *setter = [NSString stringWithFormat:@"set%@:", upper];
            BOOL readonly = NO;
            char type = '@';
            objc_property_t declaration = class_getProperty(managedClass, [name UTF8String]);
            if (declaration) {
                NSString *attributes = [NSString stringWithUTF8String:property_getAttributes(declaration)];
                for (NSString *attribute in [attributes componentsSeparatedByString:@","]) {
                    if ([attribute hasPrefix:@"T"] && [attribute length] > 1) type = [attribute characterAtIndex:1];
                    else if ([attribute hasPrefix:@"G"]) getter = [attribute substringFromIndex:1];
                    else if ([attribute hasPrefix:@"S"]) setter = [attribute substringFromIndex:1];
                    else if ([attribute isEqual:@"R"]) readonly = YES;
                }
            }
            IMP get = NULL, set = NULL;
            const char *encoding = NULL;
#define ACCESSOR_CASE(CODE, SUFFIX, TYPE) case CODE: get = (IMP)get##SUFFIX; set = (IMP)set##SUFFIX; encoding = @encode(TYPE); break
            switch (type) {
                case '@': get = (IMP)getValue; set = (IMP)setValue; encoding = @encode(id); break;
                ACCESSOR_CASE('c', Char, signed char);
                ACCESSOR_CASE('B', Bool, _Bool);
                ACCESSOR_CASE('s', Short, short);
                ACCESSOR_CASE('i', Int, int);
                ACCESSOR_CASE('l', Long, long);
                ACCESSOR_CASE('q', LongLong, long long);
                ACCESSOR_CASE('f', Float, float);
                ACCESSOR_CASE('d', Double, double);
                default: [NSException raise:NSInvalidArgumentException format:@"Unsupported managed property ABI."];
            }
#undef ACCESSOR_CASE
            NSString *getTypes = [NSString stringWithFormat:@"%s@:", encoding];
            NSString *setTypes = [NSString stringWithFormat:@"v@:%s", encoding];
            SEL selector;
            appendMethodToList(managedClass, getter, get, [getTypes UTF8String], &selector);
            [_selectorPropertyMap setObject:property forKey:keyObjectForSelector(selector)];
            if (!readonly) {
                appendMethodToList(managedClass, setter, set, [setTypes UTF8String], &selector);
                [_selectorPropertyMap setObject:property forKey:keyObjectForSelector(selector)];
            }
            if ([property isKindOfClass:[NSRelationshipDescription class]] && [(NSRelationshipDescription *)property isToMany]) {
                NSArray *selectors = @[[NSString stringWithFormat:@"add%@Object:", upper], [NSString stringWithFormat:@"remove%@Object:", upper], [NSString stringWithFormat:@"add%@:", upper], [NSString stringWithFormat:@"remove%@:", upper]];
                IMP implementations[] = {(IMP)addObject, (IMP)removeObject, (IMP)addObjectSet, (IMP)removeObjectSet};
                for (NSUInteger index = 0; index < [selectors count]; index++) {
                    appendMethodToList(managedClass, [selectors objectAtIndex:index], implementations[index], "v@:@", &selector);
                    [_selectorPropertyMap setObject:property forKey:keyObjectForSelector(selector)];
                }
            }
        }
    }
}

- initWithCoder: (NSCoder *) coder {
    if (![coder allowsKeyedCoding]) {
        [NSException raise: NSInvalidArgumentException
                    format: @"%@ can not initWithCoder:%@", [self class],
                            [coder class]];
        return nil;
    }

    _className = [[coder decodeObjectForKey: @"NSClassNameForEntity"] retain];
    _name = [[coder decodeObjectForKey: @"NSEntityName"] retain];
    _model = [coder decodeObjectForKey: @"NSManagedObjectModel"];
    _properties = [[coder decodeObjectForKey: @"NSProperties"] mutableCopy];
    _subentities = [[coder decodeObjectForKey: @"NSSubentities"] retain];
    _superentity = [[coder decodeObjectForKey: @"NSSuperentity"] retain];
    _userInfo = [[coder decodeObjectForKey: @"NSUserInfo"] retain];
    _versionHashModifier =
            [[coder decodeObjectForKey: @"NSVersionHashModifier"] retain];

    _selectorPropertyMap = [[NSMutableDictionary alloc] init];

    _hasBeenInstantiated = NO;

    return self;
}

- copyWithZone: (NSZone *) zone {
    NSEntityDescription *copy = [[NSEntityDescription allocWithZone: zone] init];
    copy->_name = [_name copyWithZone: zone];
    copy->_className = [_className copyWithZone: zone];
    copy->_isAbstract = _isAbstract;
    copy->_userInfo = [_userInfo copyWithZone: zone];
    copy->_versionHashModifier = [_versionHashModifier copyWithZone: zone];
    copy->_properties = [_properties mutableCopyWithZone: zone];
    copy->_subentities = [_subentities mutableCopyWithZone: zone];
    copy->_superentity = _superentity;
    copy->_model = _model;
    copy->_selectorPropertyMap = [_selectorPropertyMap mutableCopyWithZone: zone];
    copy->_hasBeenInstantiated = _hasBeenInstantiated;
    return copy;
}

- (NSString *) description {
    return [NSString stringWithFormat: @"<NSEntityDescription %@>", _name];
}

- (NSPropertyDescription *) _propertyForSelector: (SEL) selector {
    id keyObject = keyObjectForSelector(selector);
    NSEntityDescription *entity;

    for (entity = self; entity; entity = [entity superentity]) {
        NSPropertyDescription *result =
                [entity->_selectorPropertyMap objectForKey: keyObject];

        if (result)
            return result;
    }
    return nil;
}

- (BOOL) _hasBeenInstantiated {
    return _hasBeenInstantiated;
}



+ (NSEntityDescription *) entityForName: (NSString *) entityName
                 inManagedObjectContext: (NSManagedObjectContext *) context
{
    NSDictionary *entities = [[[context persistentStoreCoordinator]
            managedObjectModel] entitiesByName];

    return [entities objectForKey: entityName];
}

+ insertNewObjectForEntityForName: (NSString *) entityName
           inManagedObjectContext: (NSManagedObjectContext *) context
{
    NSEntityDescription *entity = [self entityForName: entityName
                               inManagedObjectContext: context];
    NSString *className = [entity managedObjectClassName];
    Class class = Nil;

    if (className)
        class = NSClassFromString(className);
    if (class == Nil) {
        class = [NSManagedObject class];
    }

    if (!entity)
        [NSException raise:NSInvalidArgumentException format:@"The entity is not in the context model."];
    return [[[class alloc] initWithEntity: entity
            insertIntoManagedObjectContext: context] autorelease];
}

- (NSManagedObjectModel *) managedObjectModel {
    return _model;
}

- (NSString *) name {
    return _name;
}

- (BOOL) isAbstract {
    return _isAbstract;
}

- (NSString *) managedObjectClassName {
    // should probably init _className like this but initWithCoder logic needs
    // to be changed
    if (_className == nil)
        return @"NSManagedObject";

    return _className;
}

- (NSArray *) properties {
    return [_properties allValues];
}

- (NSArray *) subentities {
    // the order the entities were given in -setSubentities:, as on macOS; a model decoded from a
    // file has no recorded order
    return _subentityOrder ? [[_subentityOrder copy] autorelease] : [_subentities allValues];
}

- (NSDictionary *) userInfo {
    return _userInfo;
}

- (void) setName: (NSString *) value {
    if (_hasBeenInstantiated)
        [NSException raise:NSInvalidArgumentException format:@"The managed object model is in use."];

    NSString *name = [value copy];
    // A name another sub-entity of the same super-entity already has is refused with
    // NSInternalInconsistencyException (observed on macOS 10.14.4 and 26.7.3).
    NSEntityDescription *sibling = _superentity ? [_superentity->_subentities objectForKey:name] : nil;
    if (sibling && sibling != self) {
        [name release];
        [NSException raise:NSInternalInconsistencyException format:@"Sub-entity names must be unique within an entity."];
    }
    @try {
        [_model _renameEntity:self from:_name to:name];
    } @catch (id exception) {
        [name release];
        @throw;
    }
    // subentitiesByName is keyed by the sub-entity names, so the super-entity follows a rename.
    if (_superentity) {
        NSMutableDictionary *rekeyed = [_superentity->_subentities mutableCopy];
        if (_name)
            [rekeyed removeObjectForKey:_name];
        if (name)    // setName:nil was accepted before sub-entities existed; keep it working
            [rekeyed setObject:self forKey:name];
        [_superentity->_subentities release];
        _superentity->_subentities = rekeyed;
    }
    [_name release];
    _name = name;
}

- (void) setAbstract: (BOOL) value {
    if (_hasBeenInstantiated)
        [NSException raise:NSInvalidArgumentException format:@"The managed object model is in use."];

    _isAbstract = value;
}

- (void) setManagedObjectClassName: (NSString *) value {
    if (_hasBeenInstantiated)
        [NSException raise:NSInvalidArgumentException format:@"The managed object model is in use."];

    value = [value copy];
    [_className release];
    _className = value;
}

- (void) setProperties: (NSArray *) value {
    if (_hasBeenInstantiated)
        [NSException raise:NSInvalidArgumentException format:@"The managed object model is in use."];
    NSMutableDictionary *properties = [NSMutableDictionary dictionary];
    for (NSPropertyDescription *property in value) {
        if (![property isKindOfClass:[NSPropertyDescription class]] || ![[property name] length] ||
            ([property entity] && [property entity] != self) || [properties objectForKey:[property name]])
            [NSException raise:NSInvalidArgumentException format:@"Invalid or duplicate entity property."];
        [properties setObject:property forKey:[property name]];
    }
    for (NSPropertyDescription *property in [_properties allValues])
        if ([properties objectForKey:[property name]] != property)
            [property _setEntity:nil];
    for (NSPropertyDescription *property in [properties allValues])
        [property _setEntity:self];
    [_properties release];
    _properties = [properties retain];
}

- (void) setSubentities: (NSArray *) value {
    // Observed on macOS 10.14.4 and 26.7.3 (black-box, tier 2; probe 3 of the cristim batch10b
    // evidence): once the model is in use, a list holding the receiver itself, an entity
    // without a name, two entities with the same name or an entity that already has another
    // superentity raises NSInternalInconsistencyException; an element that is not an entity
    // raises NSInvalidArgumentException; nil changes nothing; an entity of another model is
    // accepted; the entities replaced by a new list lose their superentity; -subentities keeps the
    // order of the list. A list that makes an ancestor a sub-entity (a cycle) is accepted by
    // macOS; it is refused here (NSInternalInconsistencyException) because the hierarchy is
    // walked upwards by other code, and no valid model has one.
    // Test: coredata-entity-description-subentities.
    if (_hasBeenInstantiated)
        [NSException raise:NSInternalInconsistencyException format:@"The managed object model is in use."];
    if (value == nil)
        return;

    NSMutableDictionary *subentities = [NSMutableDictionary dictionary];
    NSMutableArray *order = [NSMutableArray array];
    for (NSEntityDescription *entity in value) {
        if (![entity isKindOfClass:[NSEntityDescription class]])
            [NSException raise:NSInvalidArgumentException format:@"Sub-entities must be entity descriptions."];
        BOOL isAncestor = NO;
        for (NSEntityDescription *ancestor = self; ancestor; ancestor = ancestor->_superentity)
            if (ancestor == entity)
                isAncestor = YES;
        if (![[entity name] length] || isAncestor || (entity->_superentity && entity->_superentity != self) ||
            [subentities objectForKey:[entity name]])
            [NSException raise:NSInternalInconsistencyException format:@"Invalid or duplicate sub-entity."];
        [subentities setObject:entity forKey:[entity name]];
        [order addObject:entity];
    }
    for (NSEntityDescription *entity in [_subentities allValues])
        if ([subentities objectForKey:[entity name]] != entity)
            entity->_superentity = nil;
    for (NSEntityDescription *entity in order)
        entity->_superentity = self;
    [_subentities release];
    _subentities = [subentities retain];
    [_subentityOrder release];
    _subentityOrder = [order retain];
}

- (void) setUserInfo: (NSDictionary *) value {
    if (_hasBeenInstantiated)
        [NSException raise:NSInvalidArgumentException format:@"The managed object model is in use."];

    value = [value copy];
    [_userInfo release];
    _userInfo = value;
}

- (NSEntityDescription *) superentity {
    return _superentity;
}

- (NSDictionary *) subentitiesByName {
    return [NSDictionary dictionaryWithDictionary:_subentities];
}

- (NSDictionary *) attributesByName {
    NSMutableDictionary *result = [NSMutableDictionary dictionary];

    for (NSPropertyDescription *check in [_properties allValues]) {
        if ([check isKindOfClass: [NSAttributeDescription class]]) {
            [result setObject: check forKey: [check name]];
        }
    }

    return result;
}

- (NSDictionary *) propertiesByName {
    return _properties;
}

- (NSDictionary *) relationshipsByName {
    NSMutableDictionary *result = [NSMutableDictionary dictionary];

    for (NSPropertyDescription *check in [_properties allValues]) {
        if ([check isKindOfClass: [NSRelationshipDescription class]])
            [result setObject: check forKey: [check name]];
    }

    return result;
}

- (NSArray *) relationshipsWithDestinationEntity: (NSEntityDescription *) entity
{
    NSMutableArray *result = [NSMutableArray array];

    for (NSPropertyDescription *check in [_properties allValues]) {
        if ([check isKindOfClass: [NSRelationshipDescription class]]) {
            if ([[check entity] isEqual: entity])
                [result addObject: check];
        }
    }

    return result;
}

- (BOOL) _isKindOfEntity: (NSEntityDescription *) other {
    NSEntityDescription *check = self;

    for (; check != nil; check = check->_superentity)
        if (check == other || [[check name] isEqualToString: [other name]])
            return YES;

    return NO;
}

@end
