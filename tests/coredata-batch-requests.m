// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Lubos Dolezel
//
// NSPersistentStoreRequest, NSBatchUpdateRequest, NSBatchDeleteRequest and the entity-name API
// of NSFetchRequest: enum values (the public header values, confirmed on macOS 26.7.3), defaults,
// the request type and the argument checks. Runs on macOS and in Darling.
// Prints PASS when everything holds; the exit code is the number of failed checks.

#import <CoreData/CoreData.h>
#include <stdio.h>

static int failures;

#define CHECK(cond) do { if (!(cond)) { printf("FAIL line %d: %s\n", __LINE__, #cond); failures++; } } while (0)

int main(void)
{
    @autoreleasepool {
        CHECK(NSFetchRequestType == 1 && NSSaveRequestType == 2 && NSBatchInsertRequestType == 5 &&
              NSBatchUpdateRequestType == 6 && NSBatchDeleteRequestType == 7);
        CHECK(NSStatusOnlyResultType == 0 && NSUpdatedObjectIDsResultType == 1 && NSUpdatedObjectsCountResultType == 2);
        CHECK(NSBatchDeleteResultTypeStatusOnly == 0 && NSBatchDeleteResultTypeObjectIDs == 1 && NSBatchDeleteResultTypeCount == 2);

        // NSFetchRequest created with an entity name
        NSFetchRequest *fetch = [NSFetchRequest fetchRequestWithEntityName:@"Item"];
        CHECK([[fetch entityName] isEqualToString:@"Item"]);
        BOOL fetchRaised = NO;
        @try { (void)[fetch entity]; } @catch (NSException *e) { fetchRaised = YES; }
        CHECK(fetchRaised); // created from a name only
        CHECK([fetch isKindOfClass:[NSPersistentStoreRequest class]]);
        CHECK([fetch requestType] == NSFetchRequestType);
        CHECK([fetch includesPendingChanges] && [fetch includesPropertyValues] &&
              [fetch includesSubentities] && [fetch returnsObjectsAsFaults]);
        CHECK(![fetch returnsDistinctResults] && [fetch fetchLimit] == 0 && [fetch affectedStores] == nil);
        NSFetchRequest *fetchCopy = [fetch copy];
        CHECK([[fetchCopy entityName] isEqualToString:@"Item"]);

        // NSBatchUpdateRequest
        NSBatchUpdateRequest *update = [NSBatchUpdateRequest batchUpdateRequestWithEntityName:@"Item"];
        CHECK([[update entityName] isEqualToString:@"Item"]);
        CHECK([update requestType] == NSBatchUpdateRequestType);
        CHECK([update includesSubentities]);
        CHECK([update resultType] == NSStatusOnlyResultType);
        CHECK([update predicate] == nil && [update propertiesToUpdate] == nil && [update affectedStores] == nil);
        BOOL raised = NO;
        @try { (void)[update entity]; } @catch (NSException *e) { raised = YES; }
        CHECK(raised); // created from a name only

        [update setPredicate:[NSPredicate predicateWithFormat:@"TRUEPREDICATE"]];
        [update setPropertiesToUpdate:@{@"count": @5}];
        [update setResultType:NSUpdatedObjectsCountResultType];
        [update setIncludesSubentities:NO];

        // NSBatchDeleteRequest
        NSFetchRequest *toDelete = [NSFetchRequest fetchRequestWithEntityName:@"Item"];
        [toDelete setFetchLimit:3];
        NSBatchDeleteRequest *delete = [[NSBatchDeleteRequest alloc] initWithFetchRequest:toDelete];
        CHECK([delete requestType] == NSBatchDeleteRequestType);
        CHECK([delete resultType] == NSBatchDeleteResultTypeStatusOnly);
        CHECK([[delete fetchRequest] fetchLimit] == 3);
        CHECK([delete fetchRequest] != toDelete); // a copy
        [delete setResultType:NSBatchDeleteResultTypeCount];
        // QUIRK test: an empty ID list is refused at initialisation (observed on macOS 26.7.3).
        BOOL emptyRaised = NO;
        @try { (void)[[NSBatchDeleteRequest alloc] initWithObjectIDs:@[]]; }
        @catch (NSException *e) { emptyRaised = [[e name] isEqualToString:NSInvalidArgumentException]; }
        CHECK(emptyRaised);
    }
    if (!failures) printf("PASS\n");
    return failures;
}
