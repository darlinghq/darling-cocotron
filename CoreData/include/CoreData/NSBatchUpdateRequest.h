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

#import <CoreData/NSPersistentStoreRequest.h>

@class NSDictionary, NSEntityDescription, NSPredicate, NSString;

typedef NS_ENUM(NSUInteger, NSBatchUpdateRequestResultType) {
    NSStatusOnlyResultType = 0,
    NSUpdatedObjectIDsResultType = 1,
    NSUpdatedObjectsCountResultType = 2,
};

// Describes an update of every object of an entity that matches a predicate.
@interface NSBatchUpdateRequest : NSPersistentStoreRequest {
    NSString *_entityName;
    NSEntityDescription *_entity;
    NSPredicate *_predicate;
    NSDictionary *_propertiesToUpdate;
    NSBatchUpdateRequestResultType _resultType;
    BOOL _includesSubentities;
}

+ (instancetype) batchUpdateRequestWithEntityName: (NSString *) entityName;
- (instancetype) initWithEntityName: (NSString *) entityName;
- (instancetype) initWithEntity: (NSEntityDescription *) entity;

@property(readonly, copy) NSString *entityName;
// Raises NSObjectInaccessibleException for a request created from an entity name only.
@property(readonly, retain) NSEntityDescription *entity;
@property(nonatomic, retain) NSPredicate *predicate;
@property(nonatomic, copy) NSDictionary *propertiesToUpdate;
@property(nonatomic) NSBatchUpdateRequestResultType resultType;
@property(nonatomic) BOOL includesSubentities;

@end

@interface NSBatchUpdateResult : NSPersistentStoreResult {
    id _result;
    NSBatchUpdateRequestResultType _resultType;
}

@property(readonly, retain) id result;
@property(readonly) NSBatchUpdateRequestResultType resultType;

@end
