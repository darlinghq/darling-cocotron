// SPDX-License-Identifier: GPL-3.0-or-later
//
// NSPropertyDescription userInfo, validationPredicates, validationWarnings, setUserInfo: and
// setValidationPredicates:withValidationWarnings:, from the documented contract:
// https://developer.apple.com/documentation/coredata/nspropertydescription
// https://developer.apple.com/documentation/coredata/nspropertydescription/setvalidationpredicates(_:withvalidationwarnings:)
// Documented: the setters store what they are given, the two arrays pair up by index and should
// be the same length, and both setters raise after a persistent store coordinator has started
// using the model the property belongs to. Lines marked GUESS pin choices the pages leave open
// (they are not observed on macOS). Prints PASS when everything holds; the exit code is the
// number of failed checks.

#import <CoreData/CoreData.h>
#include <stdio.h>

static int failures;
#define CHECK(c) do { if (!(c)) { printf("FAIL line %d: %s\n", __LINE__, #c); failures++; } } while (0)

static NSString *raiseName(void (^block)(void)) {
    @try { block(); } @catch (NSException *e) { return [e name]; }
    return nil;
}

int main(void) {
    @autoreleasepool {
        NSAttributeDescription *attribute = [[[NSAttributeDescription alloc] init] autorelease];
        [attribute setName:@"title"];

        /* nothing set yet */
        CHECK([attribute userInfo] == nil);
        /* GUESS: unset arrays read as empty, not nil (the public header declares them non-null) */
        CHECK([attribute validationPredicates] != nil && [attribute validationWarnings] != nil);
        CHECK([[attribute validationPredicates] count] == 0 && [[attribute validationWarnings] count] == 0);

        /* userInfo round trip, and clearing it */
        NSDictionary *info = [NSDictionary dictionaryWithObject:@"v" forKey:@"k"];
        [attribute setUserInfo:info];
        CHECK([[attribute userInfo] isEqual:info]);
        [attribute setUserInfo:nil];
        CHECK([attribute userInfo] == nil);

        /* predicates and warnings are stored index for index */
        NSArray *predicates = [NSArray arrayWithObjects:
            [NSPredicate predicateWithFormat:@"length > 0"], [NSPredicate predicateWithFormat:@"length < 10"], nil];
        NSArray *warnings = [NSArray arrayWithObjects:@"too short", @"too long", nil];
        [attribute setValidationPredicates:predicates withValidationWarnings:warnings];
        CHECK([[attribute validationPredicates] isEqual:predicates]);
        CHECK([[attribute validationWarnings] isEqual:warnings]);

        /* GUESS: the arrays are snapshotted, so a later change by the caller leaves the pairing intact */
        NSMutableArray *mutablePredicates = [[predicates mutableCopy] autorelease];
        NSMutableArray *mutableWarnings = [[warnings mutableCopy] autorelease];
        [attribute setValidationPredicates:mutablePredicates withValidationWarnings:mutableWarnings];
        [mutablePredicates removeAllObjects];
        CHECK([[attribute validationPredicates] count] == 2 && [[attribute validationWarnings] count] == 2);

        /* GUESS: unequal lengths raise NSInvalidArgumentException and keep the old values */
        CHECK([raiseName(^{ [attribute setValidationPredicates:predicates
                                        withValidationWarnings:[NSArray arrayWithObject:@"only one"]]; })
              isEqual:NSInvalidArgumentException]);
        CHECK([raiseName(^{ [attribute setValidationPredicates:nil withValidationWarnings:warnings]; })
              isEqual:NSInvalidArgumentException]);
        CHECK([[attribute validationPredicates] count] == 2);

        /* clearing both */
        [attribute setValidationPredicates:nil withValidationWarnings:nil];
        CHECK([[attribute validationPredicates] count] == 0 && [[attribute validationWarnings] count] == 0);
        [attribute setValidationPredicates:predicates withValidationWarnings:warnings];

        /* the same accessors on a relationship, the other documented concrete subclass */
        NSRelationshipDescription *relationship = [[[NSRelationshipDescription alloc] init] autorelease];
        [relationship setName:@"owner"];
        [relationship setUserInfo:info];
        CHECK([[relationship userInfo] isEqual:info] && [attribute userInfo] == nil);

        /* once the model is used by a coordinator, both setters raise and nothing changes */
        NSEntityDescription *entity = [[[NSEntityDescription alloc] init] autorelease];
        [entity setName:@"Doc"];
        [entity setProperties:[NSArray arrayWithObject:attribute]];
        NSManagedObjectModel *model = [[[NSManagedObjectModel alloc] init] autorelease];
        [model setEntities:[NSArray arrayWithObject:entity]];
        [attribute setUserInfo:info];    /* still editable: the model is not yet in use */
        CHECK([[attribute userInfo] isEqual:info]);
        NSPersistentStoreCoordinator *coordinator =
            [[[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:model] autorelease];
        (void)coordinator;
        CHECK(raiseName(^{ [attribute setUserInfo:nil]; }) != nil);
        CHECK(raiseName(^{ [attribute setValidationPredicates:nil withValidationWarnings:nil]; }) != nil);
        CHECK([[attribute userInfo] isEqual:info]);
        CHECK([[attribute validationPredicates] isEqual:predicates] && [[attribute validationWarnings] isEqual:warnings]);
    }
    if (!failures) printf("PASS\n");
    return failures;
}
