// SPDX-License-Identifier: GPL-3.0-or-later
//
// NSManagedObject validation, from the documented contract:
// https://developer.apple.com/documentation/coredata/nsmanagedobject/validatevalue(_:forkey:)
// https://developer.apple.com/documentation/coredata/nsmanagedobject/validateforupdate()
// https://developer.apple.com/documentation/coredata/nsmanagedobject/validatefordelete()
// https://developer.apple.com/documentation/coredata/nsrelationshipdescription/maxcount
// The error codes and user info keys are those of the public CoreDataErrors.h.
//
// The expectations marked "observed" are what macOS 10.14.4 and 26.7.3 do (they agree), found with
// black-box probes (mac-probes val1.m, val2.m, val3.m of batch11b): the validate<Key>:error: method of the
// object is invoked first and always (also for nil), may replace the value, and the model checks then see
// that value; a failure of both is reported as several errors; the class of an attribute value is not
// checked; the count limits behave as for min/max counts below; the texts of the errors are the macOS ones;
// validateForDelete: fails for every relationship with a rule other than "no action" that has a destination
// object (QUIRK, observed: the documentation names only the deny rule).
// Prints PASS when everything holds; the exit code is the number of failed checks.

#import <Foundation/Foundation.h>
#import <CoreData/CoreData.h>
#include <stdio.h>

static int failures;
#define CHECK(...) do { if (!(__VA_ARGS__)) { printf("FAIL line %d: %s\n", __LINE__, #__VA_ARGS__); failures++; } } while (0)

static int hookCalls;
static int hookMode;   /* 0 accept, 1 reject with an own error, 2 replace the value, 3 replace by nil */

@interface ValidatingBox : NSManagedObject
@end

@implementation ValidatingBox
- (BOOL)validateLabel:(id *)value error:(NSError **)error {
    hookCalls++;
    if (hookMode == 1 || [*value isEqual:@"forbidden"]) {
        if (error)
            *error = [NSError errorWithDomain:@"TestDomain" code:4242 userInfo:nil];
        return NO;
    }
    if (hookMode == 2)
        *value = @"changed";
    if (hookMode == 3)
        *value = nil;
    return YES;
}
@end

static NSManagedObjectModel *makeModel(void) {
    NSEntityDescription *person = [[NSEntityDescription alloc] init];
    person.name = @"Person";
    person.managedObjectClassName = @"NSManagedObject";
    NSAttributeDescription *personName = [[NSAttributeDescription alloc] init];
    personName.name = @"name";
    personName.attributeType = NSStringAttributeType;
    personName.optional = YES;
    person.properties = @[personName];

    NSEntityDescription *box = [[NSEntityDescription alloc] init];
    box.name = @"Box";
    box.managedObjectClassName = @"ValidatingBox";
    NSAttributeDescription *label = [[NSAttributeDescription alloc] init];
    label.name = @"label";
    label.attributeType = NSStringAttributeType;
    label.optional = NO;
    NSAttributeDescription *size = [[NSAttributeDescription alloc] init];
    size.name = @"size";
    size.attributeType = NSInteger32AttributeType;
    size.optional = YES;
    NSRelationshipDescription *owner = [[NSRelationshipDescription alloc] init];
    owner.name = @"owner";
    owner.destinationEntity = person;
    owner.optional = NO;
    owner.maxCount = 1;
    owner.deleteRule = NSNoActionDeleteRule;
    NSRelationshipDescription *things = [[NSRelationshipDescription alloc] init];
    things.name = @"things";
    things.destinationEntity = person;
    things.optional = YES;
    things.maxCount = 2;
    things.minCount = 1;
    things.deleteRule = NSDenyDeleteRule;
    NSRelationshipDescription *needed = [[NSRelationshipDescription alloc] init];
    needed.name = @"needed";
    needed.destinationEntity = person;
    needed.optional = NO;
    needed.minCount = 2;
    needed.maxCount = 3;
    needed.deleteRule = NSNoActionDeleteRule;
    NSRelationshipDescription *nulls = [[NSRelationshipDescription alloc] init];
    nulls.name = @"nulls";
    nulls.destinationEntity = person;
    nulls.optional = YES;
    nulls.deleteRule = NSNullifyDeleteRule;
    box.properties = @[label, size, owner, things, needed, nulls];

    NSManagedObjectModel *model = [[NSManagedObjectModel alloc] init];
    model.entities = @[person, box];
    return model;
}

static NSManagedObject *newPerson(NSManagedObjectContext *context) {
    return [NSEntityDescription insertNewObjectForEntityForName:@"Person" inManagedObjectContext:context];
}

static NSArray *detailedKeys(NSError *error) {
    NSMutableArray *keys = [NSMutableArray array];
    for (NSError *each in [[error userInfo] objectForKey:NSDetailedErrorsKey])
        [keys addObject:[[each userInfo] objectForKey:NSValidationKeyErrorKey] ?: @"-"];
    [keys sortUsingSelector:@selector(compare:)];
    return keys;
}

int main(void) {
    @autoreleasepool {
        NSPersistentStoreCoordinator *psc =
            [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:makeModel()];
        CHECK([psc addPersistentStoreWithType:NSInMemoryStoreType configuration:nil URL:nil options:nil error:NULL] != nil);
        NSManagedObjectContext *context = [[NSManagedObjectContext alloc] init];
        context.persistentStoreCoordinator = psc;

        NSManagedObject *box = [NSEntityDescription insertNewObjectForEntityForName:@"Box" inManagedObjectContext:context];
        CHECK([box isKindOfClass:[ValidatingBox class]]);

        /* a required property without a value fails with the mandatory-property code; the object's own
           validate method is asked first, whatever the value (observed) */
        id nothing = nil;
        NSError *error = nil;
        CHECK(![box validateValue:&nothing forKey:@"label" error:&error]);
        CHECK([[error domain] isEqualToString:NSCocoaErrorDomain]);
        CHECK([error code] == NSValidationMissingMandatoryPropertyError);
        CHECK([[[error userInfo] objectForKey:NSValidationKeyErrorKey] isEqual:@"label"]);
        CHECK([[error userInfo] objectForKey:NSValidationObjectErrorKey] == box);
        CHECK([[error localizedDescription] isEqualToString:@"%{PROPERTY}@ is a required value."]);
        CHECK(hookCalls == 1);
        CHECK(![box validateValue:&nothing forKey:@"label" error:NULL]);
        CHECK(hookCalls == 2);

        /* an optional property accepts nil, and there is no validate method for it */
        error = nil;
        CHECK([box validateValue:&nothing forKey:@"size" error:&error]);
        CHECK(error == nil);

        /* a value passes and the validate method is invoked; its own error comes back as it is */
        id good = @"fine";
        hookCalls = 0;
        CHECK([box validateValue:&good forKey:@"label" error:&error]);
        CHECK(hookCalls == 1);
        id bad = @"forbidden";
        error = nil;
        CHECK(![box validateValue:&bad forKey:@"label" error:&error]);
        CHECK(hookCalls == 2);
        CHECK([[error domain] isEqualToString:@"TestDomain"] && [error code] == 4242);

        /* the validate method rejecting nil and the model rejecting it too: several errors */
        hookMode = 1;
        error = nil;
        CHECK(![box validateValue:&nothing forKey:@"label" error:&error]);
        CHECK([error code] == NSValidationMultipleErrorsError);
        CHECK([[[error userInfo] objectForKey:NSDetailedErrorsKey] count] == 2);
        CHECK([[error localizedDescription] isEqualToString:@"Multiple validation errors occurred."]);
        hookMode = 0;

        /* the validate method may replace the value, and the model checks see the replacement */
        hookMode = 2;
        id replaced = nil;
        error = nil;
        CHECK([box validateValue:&replaced forKey:@"label" error:&error]);
        CHECK([replaced isEqual:@"changed"]);
        hookMode = 3;
        replaced = @"something";
        CHECK(![box validateValue:&replaced forKey:@"label" error:&error]);
        CHECK([error code] == NSValidationMissingMandatoryPropertyError);
        hookMode = 0;

        /* the class of an attribute value is not checked, and the value is not converted (observed) */
        id number = @5;
        id text = @"5";
        error = nil;
        CHECK([box validateValue:&text forKey:@"size" error:&error]);
        CHECK([text isEqual:@"5"] && [text isKindOfClass:[NSString class]]);
        CHECK([box validateValue:&number forKey:@"size" error:&error]);

        /* a key that is not a modeled property has no model checks and passes */
        CHECK([box validateValue:&number forKey:@"unmodeled" error:&error]);

        /* relationships: a missing required destination, the count limits */
        error = nil;
        CHECK(![box validateValue:&nothing forKey:@"owner" error:&error]);
        CHECK([error code] == NSValidationMissingMandatoryPropertyError);
        NSManagedObject *p1 = newPerson(context), *p2 = newPerson(context), *p3 = newPerson(context);
        NSSet *three = [NSSet setWithObjects:p1, p2, p3, nil];
        id value = three;
        CHECK(![box validateValue:&value forKey:@"things" error:&error]);
        CHECK([error code] == NSValidationRelationshipExceedsMaximumCountError);
        CHECK([[error userInfo] objectForKey:NSValidationValueErrorKey] == three);
        CHECK([[error localizedDescription] isEqualToString:@"Too many items in %{PROPERTY}@."]);
        value = [NSSet setWithObject:p1];
        CHECK([box validateValue:&value forKey:@"things" error:&error]);
        /* optional and empty: the limits (minCount 1) are not enforced */
        value = [NSSet set];
        CHECK([box validateValue:&value forKey:@"things" error:&error]);
        value = nil;
        CHECK([box validateValue:&value forKey:@"things" error:&error]);
        /* not optional (2 to 3): empty and too few fail, in range passes */
        value = [NSSet set];
        error = nil;
        CHECK(![box validateValue:&value forKey:@"needed" error:&error]);
        CHECK([error code] == NSValidationRelationshipLacksMinimumCountError);
        CHECK([[error localizedDescription] isEqualToString:@"Too few items in %{PROPERTY}@."]);
        value = [NSSet setWithObject:p1];
        CHECK(![box validateValue:&value forKey:@"needed" error:&error]);
        value = [NSSet setWithObjects:p1, p2, nil];
        CHECK([box validateValue:&value forKey:@"needed" error:&error]);

        /* validateForUpdate: validates every property; several failures are collected, and the validate
           method of each property is asked (observed) */
        hookCalls = 0;
        error = nil;
        CHECK(![box validateForUpdate:&error]);
        CHECK([error code] == NSValidationMultipleErrorsError);
        CHECK(detailedKeys(error).count == 3);
        CHECK([detailedKeys(error) isEqual:(@[@"label", @"needed", @"owner"])]);
        CHECK(hookCalls == 1);
        /* NULL: validation aborts after the first failure but still reports it */
        CHECK(![box validateForUpdate:NULL]);
        error = nil;
        CHECK(![box validateForInsert:&error]);
        CHECK([error code] == NSValidationMultipleErrorsError);
        CHECK([detailedKeys(error) isEqual:(@[@"label", @"needed", @"owner"])]);

        /* one failure is returned as it is (not wrapped in a multiple-errors error) */
        [box setValue:@"labelled" forKey:@"label"];
        [box setValue:[NSSet setWithObjects:p1, p2, nil] forKey:@"needed"];
        error = nil;
        CHECK(![box validateForUpdate:&error]);
        CHECK([error code] == NSValidationMissingMandatoryPropertyError);
        CHECK([[[error userInfo] objectForKey:NSValidationKeyErrorKey] isEqual:@"owner"]);

        /* a valid object passes update and insert alike */
        [box setValue:p1 forKey:@"owner"];
        error = nil;
        CHECK([box validateForUpdate:&error]);
        CHECK([box validateForInsert:&error]);
        CHECK(error == nil);
        [box setValue:nil forKey:@"owner"];
        error = nil;
        CHECK(![box validateForInsert:&error]);
        CHECK([error code] == NSValidationMissingMandatoryPropertyError);
        [box setValue:p1 forKey:@"owner"];

        /* the validate method failing is the error of update too */
        [box setValue:@"forbidden" forKey:@"label"];
        error = nil;
        CHECK(![box validateForUpdate:&error]);
        CHECK([[error domain] isEqualToString:@"TestDomain"]);
        [box setValue:@"labelled" forKey:@"label"];

        /* QUIRK (observed on macOS 10.14.4 and 26.7.3): validateForDelete: fails for every relationship whose
           delete rule is not "no action" and that has a destination object, with the denied-delete code;
           "no action" (owner, needed) passes. */
        error = nil;
        CHECK([box validateForDelete:&error]);
        [box setValue:[NSSet setWithObject:p2] forKey:@"things"];
        CHECK(![box validateForDelete:&error]);
        CHECK([error code] == NSValidationRelationshipDeniedDeleteError);
        CHECK([[[error userInfo] objectForKey:NSValidationKeyErrorKey] isEqual:@"things"]);
        CHECK([[error localizedDescription] isEqualToString:@"Items cannot be deleted from %{PROPERTY}@."]);
        CHECK(![box validateForDelete:NULL]);
        [box setValue:[NSSet set] forKey:@"things"];
        CHECK([box validateForDelete:&error]);
        [box setValue:[NSSet setWithObject:p3] forKey:@"nulls"];
        error = nil;
        CHECK(![box validateForDelete:&error]);
        CHECK([error code] == NSValidationRelationshipDeniedDeleteError);
        CHECK([[[error userInfo] objectForKey:NSValidationKeyErrorKey] isEqual:@"nulls"]);
        [box setValue:[NSSet setWithObject:p2] forKey:@"things"];
        error = nil;
        CHECK(![box validateForDelete:&error]);
        CHECK([error code] == NSValidationMultipleErrorsError);
        CHECK([detailedKeys(error) isEqual:(@[@"nulls", @"things"])]);
    }
    if (failures == 0)
        printf("PASS\n");
    return failures;
}
