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

#import <CoreData/NSBatchDeleteRequest.h>
#import <CoreData/NSFetchRequest.h>
#import <Foundation/NSArray.h>
#import "NSBatchRequests-Private.h"

@implementation NSBatchDeleteRequest

@synthesize resultType = _resultType;

- (instancetype) initWithFetchRequest: (NSFetchRequest *) fetch {
    if ((self = [super init]) != nil)
        _fetchRequest = [fetch copy];
    return self;
}

// QUIRK: an empty (or nil) ID list raises NSInvalidArgumentException at initialisation. Not
// documented. Evidence: black-box observation on macOS 26.7.3 (tier 2).
// Test: tests/coredata-batch-requests.m (empty-ID-list check)
- (instancetype) initWithObjectIDs: (NSArray *) objects {
    if ([objects count] == 0) {
        [self release];
        [NSException raise: NSInvalidArgumentException
                    format: @"Must supply a non-zero number of objectIDs to request during "
                             "initialization"];
    }
    if ((self = [super init]) != nil)
        _objectIDs = [objects copy];
    return self;
}

- (NSPersistentStoreRequestType) requestType {
    return NSBatchDeleteRequestType;
}

- (NSFetchRequest *) fetchRequest {
    return [[_fetchRequest copy] autorelease];
}

- (NSArray *) _objectIDs {
    return _objectIDs;
}

- (id) copyWithZone: (NSZone *) zone {
    NSBatchDeleteRequest *copy = [super copyWithZone: zone];
    copy->_fetchRequest = [_fetchRequest copy];
    copy->_objectIDs = [_objectIDs copy];
    copy->_resultType = _resultType;
    return copy;
}

- (void) dealloc {
    [_fetchRequest release];
    [_objectIDs release];
    [super dealloc];
}

@end

@implementation NSBatchDeleteResult

@synthesize result = _result;
@synthesize resultType = _resultType;

- (instancetype) _initWithResult: (id) result type: (NSBatchDeleteRequestResultType) type {
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
