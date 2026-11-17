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

@class NSArray, NSFetchRequest;

typedef NS_ENUM(NSUInteger, NSBatchDeleteRequestResultType) {
    NSBatchDeleteResultTypeStatusOnly = 0,
    NSBatchDeleteResultTypeObjectIDs = 1,
    NSBatchDeleteResultTypeCount = 2,
};

// Describes the deletion of the objects a fetch request matches, or of the objects with the
// given IDs.
@interface NSBatchDeleteRequest : NSPersistentStoreRequest {
    NSFetchRequest *_fetchRequest;
    NSArray *_objectIDs;
    NSBatchDeleteRequestResultType _resultType;
}

- (instancetype) initWithFetchRequest: (NSFetchRequest *) fetch;
- (instancetype) initWithObjectIDs: (NSArray *) objects;

@property(nonatomic) NSBatchDeleteRequestResultType resultType;
@property(readonly, copy) NSFetchRequest *fetchRequest;

@end

@interface NSBatchDeleteResult : NSPersistentStoreResult {
    id _result;
    NSBatchDeleteRequestResultType _resultType;
}

@property(readonly, retain) id result;
@property(readonly) NSBatchDeleteRequestResultType resultType;

@end
