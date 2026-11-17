/*
 This file is part of Darling.

 Copyright (C) 2026 Lubos Dolezel

 Darling is free software: you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation, either version 3 of the License, or
 (at your option) any later version.

 Darling is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU General Public License for more details.

 You should have received a copy of the GNU General Public License
 along with Darling.  If not, see <http://www.gnu.org/licenses/>.
*/

#import <CoreData/NSBatchUpdateRequest.h>
#import <CoreData/NSEntityDescription.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSException.h>
#import <Foundation/NSPredicate.h>
#import <Foundation/NSString.h>
#import "NSBatchRequests-Private.h"

@implementation NSBatchUpdateRequest

@synthesize entityName = _entityName;
@synthesize predicate = _predicate;
@synthesize propertiesToUpdate = _propertiesToUpdate;
@synthesize resultType = _resultType;
@synthesize includesSubentities = _includesSubentities;

+ (instancetype) batchUpdateRequestWithEntityName: (NSString *) entityName {
    return [[[self alloc] initWithEntityName: entityName] autorelease];
}

- (instancetype) initWithEntityName: (NSString *) entityName {
    if ((self = [super init]) != nil) {
        _entityName = [entityName copy];
        _includesSubentities = YES;
    }
    return self;
}

- (instancetype) initWithEntity: (NSEntityDescription *) entity {
    if ((self = [self initWithEntityName: [entity name]]) != nil)
        _entity = [entity retain];
    return self;
}

// QUIRK: -entity on a request created from an entity name raises NSObjectInaccessibleException.
// Not documented. Evidence: black-box observation on macOS 26.7.3 (tier 2).
// Test: tests/coredata-batch-requests.m (raised check)
- (NSEntityDescription *) entity {
    if (_entity == nil)
        [NSException raise: @"NSObjectInaccessibleException"
                    format: @"This batch update request was created with a string name (%@) and "
                            "cannot respond to -entity until used by an NSManagedObjectContext",
                            _entityName];
    return _entity;
}

- (NSPersistentStoreRequestType) requestType {
    return NSBatchUpdateRequestType;
}

- (id) copyWithZone: (NSZone *) zone {
    NSBatchUpdateRequest *copy = [super copyWithZone: zone];
    copy->_entityName = [_entityName copy];
    copy->_entity = [_entity retain];
    copy->_predicate = [_predicate retain];
    copy->_propertiesToUpdate = [_propertiesToUpdate copy];
    copy->_resultType = _resultType;
    copy->_includesSubentities = _includesSubentities;
    return copy;
}

- (void) dealloc {
    [_entityName release];
    [_entity release];
    [_predicate release];
    [_propertiesToUpdate release];
    [super dealloc];
}

// The execution path reads the entity without the exception raised for name-only requests.
- (NSEntityDescription *) _entityIfKnown {
    return _entity;
}

@end

@implementation NSBatchUpdateResult

@synthesize result = _result;
@synthesize resultType = _resultType;

- (instancetype) _initWithResult: (id) result type: (NSBatchUpdateRequestResultType) type {
    if ((self = [super init]) != nil) {
        _result = [result retain];
        _resultType = type;
    }
    return self;
}

- (void) dealloc {
    [_result release];
    [super dealloc];
}

@end
