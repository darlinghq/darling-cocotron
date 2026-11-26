// SPDX-License-Identifier: GPL-3.0-or-later
//
// Validation predicates of a property description applied by NSManagedObject validation, from:
// https://developer.apple.com/documentation/coredata/nspropertydescription/setvalidationpredicates(_:withvalidationwarnings:)
// Documented: the predicates and the warnings at the same index are the validation rules and the
// error messages of the property. The page and the public NSPropertyDescription.h describe them
// as evaluated against the managed objects; on macOS 26.7.3 and 10.14.4 (black-box observation, probe
// p797) a predicate is evaluated with the value being validated as its subject (SELF), for attributes and
// for relationships (the related object, or the set of a to-many one). Also observed: a nil value skips
// the predicates (so a required attribute without a value gives only the missing-value error), a failing
// predicate is reported with NSManagedObjectValidationError, its warning as the localized description and
// the predicate under NSValidationPredicateErrorKey, a value failing several predicates gives a
// multiple-errors error with one error per failed predicate, and a predicate failing together with a
// validate<Key>:error: method gives several errors.
// Prints PASS when everything holds; the exit code is the number of failed checks.

#import <Foundation/Foundation.h>
#import <CoreData/CoreData.h>
#include <stdio.h>

static int failures;
#define CHECK(...) do { if (!(__VA_ARGS__)) { printf("FAIL line %d: %s\n", __LINE__, #__VA_ARGS__); failures++; } } while (0)

@interface HookAccount : NSManagedObject
@end

@implementation HookAccount
- (BOOL)validateTag:(id *)value error:(NSError **)error {
    if ([*value isEqual:@"hook-bad"]) {
        if (error)
            *error = [NSError errorWithDomain:@"TestDomain" code:4242 userInfo:nil];
        return NO;
    }
    return YES;
}
@end

int main(void) {
    @autoreleasepool {
        NSEntityDescription *entity = [[NSEntityDescription alloc] init];
        entity.name = @"Account";
        entity.managedObjectClassName = @"HookAccount";
        NSAttributeDescription *code = [[NSAttributeDescription alloc] init];
        code.name = @"code";
        code.attributeType = NSStringAttributeType;
        code.optional = YES;
        NSPredicate *longEnough = [NSPredicate predicateWithFormat:@"length >= 3"];
        NSPredicate *letters = [NSPredicate predicateWithFormat:@"SELF MATCHES %@", @"[a-z]+"];
        [code setValidationPredicates:@[longEnough, letters]
               withValidationWarnings:@[@"too short", @"letters only"]];
        NSAttributeDescription *percent = [[NSAttributeDescription alloc] init];
        percent.name = @"percent";
        percent.attributeType = NSInteger32AttributeType;
        percent.optional = YES;
        [percent setValidationPredicates:@[[NSPredicate predicateWithFormat:@"SELF >= 0 AND SELF <= 100"]]
                  withValidationWarnings:@[@"between 0 and 100"]];
        NSAttributeDescription *required = [[NSAttributeDescription alloc] init];
        required.name = @"required";
        required.attributeType = NSStringAttributeType;
        required.optional = NO;
        [required setValidationPredicates:@[longEnough] withValidationWarnings:@[@"required too short"]];
        NSAttributeDescription *tag = [[NSAttributeDescription alloc] init];
        tag.name = @"tag";
        tag.attributeType = NSStringAttributeType;
        tag.optional = YES;
        [tag setValidationPredicates:@[[NSPredicate predicateWithFormat:@"length >= 10"]]
              withValidationWarnings:@[@"tag too short"]];
        NSRelationshipDescription *peer = [[NSRelationshipDescription alloc] init];
        peer.name = @"peer";
        peer.destinationEntity = entity;
        peer.optional = YES;
        peer.maxCount = 1;
        [peer setValidationPredicates:@[[NSPredicate predicateWithValue:NO]] withValidationWarnings:@[@"never"]];
        entity.properties = @[code, percent, required, tag, peer];
        NSManagedObjectModel *model = [[NSManagedObjectModel alloc] init];
        model.entities = @[entity];

        NSPersistentStoreCoordinator *psc = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:model];
        CHECK([psc addPersistentStoreWithType:NSInMemoryStoreType configuration:nil URL:nil options:nil error:NULL] != nil);
        NSManagedObjectContext *context = [[NSManagedObjectContext alloc] init];
        context.persistentStoreCoordinator = psc;
        NSManagedObject *account = [NSEntityDescription insertNewObjectForEntityForName:@"Account" inManagedObjectContext:context];

        /* the value is the predicates' subject (macOS 26.7.3, 10.14.4) */
        id value = @"abc";
        NSError *error = nil;
        CHECK([account validateValue:&value forKey:@"code" error:&error]);
        CHECK(error == nil);

        value = @"ab";
        CHECK(![account validateValue:&value forKey:@"code" error:&error]);
        CHECK([[error domain] isEqualToString:NSCocoaErrorDomain]);
        CHECK([error code] == NSManagedObjectValidationError);
        CHECK([[error localizedDescription] isEqualToString:@"too short"]);
        CHECK([[[error userInfo] objectForKey:NSValidationPredicateErrorKey] isEqual:longEnough]);
        CHECK([[[error userInfo] objectForKey:NSValidationKeyErrorKey] isEqual:@"code"]);
        CHECK([[[error userInfo] objectForKey:NSValidationValueErrorKey] isEqual:@"ab"]);

        /* both predicates fail: a multiple-errors error with one error per predicate (macOS 26.7.3, 10.14.4) */
        value = @"A1";
        CHECK(![account validateValue:&value forKey:@"code" error:&error]);
        CHECK([error code] == NSValidationMultipleErrorsError);
        NSArray *both = [[error userInfo] objectForKey:NSDetailedErrorsKey];
        CHECK([both count] == 2);
        CHECK([[[[both objectAtIndex:0] userInfo] objectForKey:NSValidationPredicateErrorKey] isEqual:longEnough]);
        CHECK([[[[both objectAtIndex:1] userInfo] objectForKey:NSValidationPredicateErrorKey] isEqual:letters]);
        value = @"ABC";
        CHECK(![account validateValue:&value forKey:@"code" error:&error]);
        CHECK([[error localizedDescription] isEqualToString:@"letters only"]);
        CHECK([[[error userInfo] objectForKey:NSValidationPredicateErrorKey] isEqual:letters]);

        value = @150;
        CHECK(![account validateValue:&value forKey:@"percent" error:&error]);
        CHECK([[error localizedDescription] isEqualToString:@"between 0 and 100"]);
        value = @100;
        CHECK([account validateValue:&value forKey:@"percent" error:&error]);

        /* nil skips the predicates (the property is optional) */
        value = nil;
        CHECK([account validateValue:&value forKey:@"code" error:&error]);

        /* nil skips the predicates, so a required attribute without a value gives only the
           missing-value error */
        error = nil;
        CHECK(![account validateValue:&value forKey:@"required" error:&error]);
        CHECK([error code] == NSValidationMissingMandatoryPropertyError);
        CHECK([[[error userInfo] objectForKey:NSDetailedErrorsKey] count] == 0);

        /* a failing validate<Key>:error: and a failing predicate are several errors */
        value = @"hook-bad";
        error = nil;
        CHECK(![account validateValue:&value forKey:@"tag" error:&error]);
        CHECK([error code] == NSValidationMultipleErrorsError);
        NSArray *detailed = [[error userInfo] objectForKey:NSDetailedErrorsKey];
        CHECK([detailed count] == 2);
        NSMutableSet *codes = [NSMutableSet set];
        for (NSError *each in detailed)
            [codes addObject:@([each code])];
        CHECK([codes isEqual:[NSSet setWithObjects:@4242, @(NSManagedObjectValidationError), nil]]);
        value = @"long-enough-tag";
        CHECK([account validateValue:&value forKey:@"tag" error:&error]);

        /* the predicates of a relationship are applied to the related object (this one never holds) */
        value = nil;
        CHECK([account validateValue:&value forKey:@"peer" error:&error]);
        value = account;
        error = nil;
        CHECK(![account validateValue:&value forKey:@"peer" error:&error]);
        CHECK([error code] == NSManagedObjectValidationError);

        /* the predicates take part in validateForUpdate: */
        [account setValue:@"abc" forKey:@"required"];
        [account setValue:@"ab" forKey:@"code"];
        error = nil;
        CHECK(![account validateForUpdate:&error]);
        CHECK([error code] == NSManagedObjectValidationError);
        CHECK([[[error userInfo] objectForKey:NSValidationKeyErrorKey] isEqual:@"code"]);
        [account setValue:@"abc" forKey:@"code"];
        CHECK([account validateForUpdate:&error]);
    }
    if (failures == 0)
        printf("PASS\n");
    return failures;
}
