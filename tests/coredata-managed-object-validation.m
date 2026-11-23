// SPDX-License-Identifier: GPL-3.0-or-later
//
// NSManagedObject validation, from the documented contract:
// https://developer.apple.com/documentation/coredata/nsmanagedobject/validatevalue(_:forkey:)
// https://developer.apple.com/documentation/coredata/nsmanagedobject/validateforupdate()
// https://developer.apple.com/documentation/coredata/nsmanagedobject/validatefordelete()
// https://developer.apple.com/documentation/coredata/nsrelationshipdescription/maxcount
// The error codes and user info keys are those of the public CoreDataErrors.h.
// Documented and pinned without a marker: a required property without a value fails, the
// validate<Key>:error: method of the object is invoked after the basic checks, validateForUpdate:
// validates every property, several errors are collected under NSDetailedErrorsKey (a NULL error
// stops at the first failure), a relationship with the deny delete rule that still has a
// destination blocks a delete, the count limits apply to an optional relationship only when it is
// not empty. Lines marked GUESS pin what the pages leave open (they are not observed on macOS):
// that a value of the wrong class for an attribute type fails with NSManagedObjectValidationError,
// that validateForInsert: validates the way validateForUpdate: does, that one failure is returned
// as it is rather than wrapped, that the basic checks run before the validate<Key> method is
// asked, and that an unmodeled key passes. Prints PASS when everything holds; the exit code is the number of failed checks.

#import <Foundation/Foundation.h>
#import <CoreData/CoreData.h>
#include <stdio.h>

static int failures;
#define CHECK(...) do { if (!(__VA_ARGS__)) { printf("FAIL line %d: %s\n", __LINE__, #__VA_ARGS__); failures++; } } while (0)

static int hookCalls;

@interface ValidatingBox : NSManagedObject
@end

@implementation ValidatingBox
- (BOOL)validateLabel:(id *)value error:(NSError **)error {
    hookCalls++;
    if ([*value isEqual:@"forbidden"]) {
        if (error)
            *error = [NSError errorWithDomain:@"TestDomain" code:4242 userInfo:nil];
        return NO;
    }
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
    NSRelationshipDescription *things = [[NSRelationshipDescription alloc] init];
    things.name = @"things";
    things.destinationEntity = person;
    things.optional = YES;
    things.maxCount = 2;
    things.minCount = 1;
    things.deleteRule = NSDenyDeleteRule;
    box.properties = @[label, size, owner, things];

    NSManagedObjectModel *model = [[NSManagedObjectModel alloc] init];
    model.entities = @[person, box];
    return model;
}

static NSManagedObject *newPerson(NSManagedObjectContext *context) {
    return [NSEntityDescription insertNewObjectForEntityForName:@"Person" inManagedObjectContext:context];
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

        /* a required property without a value fails with the mandatory-property code */
        id nothing = nil;
        NSError *error = nil;
        CHECK(![box validateValue:&nothing forKey:@"label" error:&error]);
        CHECK([[error domain] isEqualToString:NSCocoaErrorDomain]);
        CHECK([error code] == NSValidationMissingMandatoryPropertyError);
        CHECK([[[error userInfo] objectForKey:NSValidationKeyErrorKey] isEqual:@"label"]);
        CHECK([[error userInfo] objectForKey:NSValidationObjectErrorKey] == box);
        /* GUESS: the basic check runs first, so the validateLabel: method is not asked */
        CHECK(hookCalls == 0);
        CHECK(![box validateValue:&nothing forKey:@"label" error:NULL]);

        /* an optional property accepts nil */
        error = nil;
        CHECK([box validateValue:&nothing forKey:@"size" error:&error]);
        CHECK(error == nil);

        /* a value of the right class passes and validate<Key>:error: is invoked */
        id good = @"fine";
        CHECK([box validateValue:&good forKey:@"label" error:&error]);
        CHECK(hookCalls == 1);
        id bad = @"forbidden";
        error = nil;
        CHECK(![box validateValue:&bad forKey:@"label" error:&error]);
        CHECK(hookCalls == 2);
        CHECK([[error domain] isEqualToString:@"TestDomain"] && [error code] == 4242);

        /* GUESS: a number for a string attribute is a generic validation error */
        id number = @5;
        error = nil;
        CHECK(![box validateValue:&number forKey:@"label" error:&error]);
        CHECK([error code] == NSManagedObjectValidationError);
        id text = @"5";
        CHECK(![box validateValue:&text forKey:@"size" error:&error]);
        CHECK([error code] == NSManagedObjectValidationError);
        CHECK([box validateValue:&number forKey:@"size" error:&error]);

        /* GUESS: a key that is not a modeled property has no basic checks and passes */
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
        value = [NSSet setWithObject:p1];
        CHECK([box validateValue:&value forKey:@"things" error:&error]);
        /* optional and empty: the limits (minCount 1) are not enforced */
        value = [NSSet set];
        CHECK([box validateValue:&value forKey:@"things" error:&error]);
        NSRelationshipDescription *things = [[[box entity] relationshipsByName] objectForKey:@"things"];
        CHECK([things minCount] == 1);

        /* validateForUpdate: validates every property; several failures are collected */
        error = nil;
        CHECK(![box validateForUpdate:&error]);
        CHECK([error code] == NSValidationMultipleErrorsError);
        NSArray *detailed = [[error userInfo] objectForKey:NSDetailedErrorsKey];
        CHECK([detailed count] == 2);
        NSMutableSet *keys = [NSMutableSet set];
        for (NSError *each in detailed)
            [keys addObject:[[each userInfo] objectForKey:NSValidationKeyErrorKey]];
        CHECK([keys isEqual:[NSSet setWithObjects:@"label", @"owner", nil]]);
        /* NULL: validation aborts after the first failure but still reports it */
        CHECK(![box validateForUpdate:NULL]);

        /* one failure is returned as it is (GUESS: not wrapped in a multiple-errors error) */
        [box setValue:@"labelled" forKey:@"label"];
        error = nil;
        CHECK(![box validateForUpdate:&error]);
        CHECK([error code] == NSValidationMissingMandatoryPropertyError);
        CHECK([[[error userInfo] objectForKey:NSValidationKeyErrorKey] isEqual:@"owner"]);

        /* a valid object passes update and (GUESS: same checks) insert */
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

        /* validateForDelete: the deny rule blocks a delete while there are destinations */
        error = nil;
        CHECK([box validateForDelete:&error]);
        [box setValue:[NSSet setWithObject:p2] forKey:@"things"];
        CHECK(![box validateForDelete:&error]);
        CHECK([error code] == NSValidationRelationshipDeniedDeleteError);
        CHECK([[[error userInfo] objectForKey:NSValidationKeyErrorKey] isEqual:@"things"]);
        CHECK(![box validateForDelete:NULL]);
    }
    if (failures == 0)
        printf("PASS\n");
    return failures;
}
