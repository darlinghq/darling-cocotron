// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Lubos Dolezel
//
// QUIRK test: the string values of CoreData's context notification names and change-set keys,
// as observed on macOS 26.7.3 (and macOS 10.14.4 for the notification names, the inserted/updated
// object keys and the object-ID keys). The headers declare only the symbols. Runs on macOS and in
// Darling. Prints PASS when everything holds; the exit code is the number of failed checks.

#import <CoreData/CoreData.h>
#include <stdio.h>

static int failures;

#define CHECK_STR(sym, expected) do { \
    if (![(sym) isEqualToString:(expected)]) { printf("FAIL %s = %s\n", #sym, [(sym) UTF8String]); failures++; } \
} while (0)

int main(void)
{
    @autoreleasepool {
        CHECK_STR(NSManagedObjectContextWillSaveNotification, @"NSManagingContextWillSaveChangesNotification");
        CHECK_STR(NSManagedObjectContextDidSaveNotification, @"NSManagingContextDidSaveChangesNotification");
        CHECK_STR(NSManagedObjectContextObjectsDidChangeNotification, @"NSObjectsChangedInManagingContextNotification");
        CHECK_STR(NSManagedObjectContextDidSaveObjectIDsNotification, @"NSManagedObjectContextDidSaveObjectIDsNotification");
        CHECK_STR(NSManagedObjectContextDidMergeChangesObjectIDsNotification, @"NSManagedObjectContextDidMergeChangesObjectIDsNotification");

        CHECK_STR(NSInsertedObjectsKey, @"inserted");
        CHECK_STR(NSUpdatedObjectsKey, @"updated");
        CHECK_STR(NSDeletedObjectsKey, @"deleted");
        CHECK_STR(NSRefreshedObjectsKey, @"refreshed");
        CHECK_STR(NSInvalidatedObjectsKey, @"invalidated");
        CHECK_STR(NSInvalidatedAllObjectsKey, @"invalidatedAll");

        CHECK_STR(NSInsertedObjectIDsKey, @"inserted_objectIDs");
        CHECK_STR(NSUpdatedObjectIDsKey, @"updated_objectIDs");
        CHECK_STR(NSDeletedObjectIDsKey, @"deleted_objectIDs");
        CHECK_STR(NSRefreshedObjectIDsKey, @"refreshed_objectIDs");
        CHECK_STR(NSInvalidatedObjectIDsKey, @"invalidated_objectIDs");
    }
    if (!failures) printf("PASS\n");
    return failures;
}
