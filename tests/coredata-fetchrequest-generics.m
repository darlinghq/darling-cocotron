// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Lubos Dolezel
//
// CoreData declarations: NSFetchRequest takes a result type parameter, NSFetchRequestResultType is a
// proper enum, NSManagedObject and NSManagedObjectID adopt NSFetchRequestResult, and the error keys
// NSAffectedStoresErrorKey and NSAffectedObjectsErrorKey are declared and defined.
// Prints PASS when everything holds; the exit code is the number of failed checks.

#import <CoreData/CoreData.h>
#import <objc/runtime.h>
#include <stdio.h>

static int failures;

#define CHECK(cond) do { if (!(cond)) { printf("FAIL line %d: %s\n", __LINE__, #cond); failures++; } } while (0)

// Compile-time check of the generic spelling: a typed request returned from a helper.
static NSFetchRequest<NSManagedObject *> *make_request(void)
{
    NSFetchRequest<NSManagedObject *> *request = [[NSFetchRequest alloc] init];
    [request setFetchLimit:5];
    return request;
}

int main(void)
{
    @autoreleasepool {
        CHECK([NSAffectedStoresErrorKey isEqualToString:@"NSAffectedStoresErrorKey"]);
        CHECK([NSAffectedObjectsErrorKey isEqualToString:@"NSAffectedObjectsErrorKey"]);

        CHECK(NSManagedObjectResultType == 0 && NSManagedObjectIDResultType == 1 && NSDictionaryResultType == 2);
        CHECK(sizeof(NSFetchRequestResultType) == sizeof(NSUInteger));

        CHECK(class_conformsToProtocol([NSManagedObject class], @protocol(NSFetchRequestResult)));
        CHECK(class_conformsToProtocol([NSManagedObjectID class], @protocol(NSFetchRequestResult)));

        NSFetchRequest<NSManagedObject *> *request = make_request();
        [request setResultType:NSManagedObjectIDResultType];
        CHECK([request fetchLimit] == 5);
        CHECK([request resultType] == NSManagedObjectIDResultType);
        NSFetchRequest *copy = [request copy];
        CHECK([copy fetchLimit] == 5 && [copy resultType] == NSManagedObjectIDResultType);
    }
    if (!failures) printf("PASS\n");
    return failures;
}
