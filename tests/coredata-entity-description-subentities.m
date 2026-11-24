// SPDX-License-Identifier: GPL-3.0-or-later
//
// NSEntityDescription setSubentities:, subentities, subentitiesByName and superentity, from the
// documented contract:
// https://developer.apple.com/documentation/coredata/nsentitydescription
// https://developer.apple.com/documentation/coredata/nsentitydescription/subentities
// https://developer.apple.com/documentation/coredata/nsentitydescription/subentitiesbyname
// Documented: the sub-entities are NSEntityDescription instances, subentitiesByName is keyed by
// sub-entity name, the entity hierarchy is built top-down (an entity's super-entity is set by
// listing it among its super-entity's sub-entities, and a root entity's superentity is nil), and
// the model can no longer be changed once a persistent store coordinator works with it. Lines
// marked OBSERVED pin behaviour the pages leave open, as observed on macOS 10.14.4 and 26.7.3 (the
// exception names and the order). Prints PASS when everything holds; the exit code is the number
// of failed checks.

#import <CoreData/CoreData.h>
#include <stdio.h>

static int failures;
#define CHECK(...) do { if (!(__VA_ARGS__)) { printf("FAIL line %d: %s\n", __LINE__, #__VA_ARGS__); failures++; } } while (0)

static NSString *raiseName(void (^block)(void)) {
    @try { block(); } @catch (NSException *e) { return [e name]; }
    return nil;
}

static NSEntityDescription *entityNamed(NSString *name) {
    NSEntityDescription *entity = [[[NSEntityDescription alloc] init] autorelease];
    [entity setName:name];
    return entity;
}

int main(void) {
    @autoreleasepool {
        NSEntityDescription *animal = entityNamed(@"Animal");
        NSEntityDescription *dog = entityNamed(@"Dog");
        NSEntityDescription *cat = entityNamed(@"Cat");
        NSEntityDescription *puppy = entityNamed(@"Puppy");

        CHECK([[animal subentities] count] == 0 && [[animal subentitiesByName] count] == 0);
        CHECK([animal superentity] == nil);

        /* building top-down sets the superentity and fills both accessors */
        [animal setSubentities:[NSArray arrayWithObjects:cat, dog, nil]];
        CHECK([[animal subentities] isEqual:[NSArray arrayWithObjects:cat, dog, nil]]);   /* OBSERVED: the order of the list */
        CHECK([[animal subentitiesByName] objectForKey:@"Dog"] == dog);
        CHECK([[animal subentitiesByName] objectForKey:@"Cat"] == cat);
        CHECK([[animal subentitiesByName] count] == 2);
        CHECK([dog superentity] == animal && [cat superentity] == animal);
        CHECK([animal superentity] == nil);

        /* a second level */
        [dog setSubentities:[NSArray arrayWithObject:puppy]];
        CHECK([puppy superentity] == dog && [dog superentity] == animal);

        /* OBSERVED: replacing the list drops the superentity of the entities that are no longer listed */
        [animal setSubentities:[NSArray arrayWithObject:dog]];
        CHECK([[animal subentitiesByName] count] == 1 && [cat superentity] == nil && [dog superentity] == animal);
        /* setting the same entity again is fine */
        [animal setSubentities:[NSArray arrayWithObject:dog]];
        CHECK([dog superentity] == animal);
        /* OBSERVED: nil changes nothing */
        [animal setSubentities:nil];
        CHECK([[animal subentities] count] == 1 && [dog superentity] == animal);
        [animal setSubentities:[NSArray array]];
        CHECK([[animal subentities] count] == 0 && [dog superentity] == nil);
        CHECK([puppy superentity] == dog);   /* the lower level is untouched */

        /* OBSERVED: invalid lists raise and change nothing */
        [animal setSubentities:[NSArray arrayWithObject:dog]];
        /* a fresh receiver for each case: macOS leaves the receiver and the entities half changed after a refused list, so nothing is checked about the state after a refusal except the exception */
        NSEntityDescription *other1 = entityNamed(@"Other1");
        CHECK([raiseName(^{ [other1 setSubentities:[NSArray arrayWithObject:dog]]; }) isEqual:NSInternalInconsistencyException]);   /* already has a superentity */
        CHECK([dog superentity] == animal && [[other1 subentities] count] == 0);
        NSEntityDescription *other2 = entityNamed(@"Other2");
        CHECK([raiseName(^{ [other2 setSubentities:[NSArray arrayWithObject:other2]]; }) isEqual:NSInternalInconsistencyException]);  /* itself */
        NSEntityDescription *other3 = entityNamed(@"Other3");
        CHECK([raiseName(^{ [other3 setSubentities:[NSArray arrayWithObject:@"Dog"]]; }) isEqual:NSInvalidArgumentException]);       /* not an entity */
        NSEntityDescription *twin = entityNamed(@"Cat");
        NSEntityDescription *twin2 = entityNamed(@"Cat");
        NSEntityDescription *other4 = entityNamed(@"Other4");
        CHECK([raiseName(^{ [other4 setSubentities:[NSArray arrayWithObjects:twin, twin2, nil]]; }) isEqual:NSInternalInconsistencyException]); /* same name */
        NSEntityDescription *unnamed = [[[NSEntityDescription alloc] init] autorelease];
        NSEntityDescription *other5 = entityNamed(@"Other5");
        CHECK([raiseName(^{ [other5 setSubentities:[NSArray arrayWithObject:unnamed]]; }) isEqual:NSInternalInconsistencyException]);
        CHECK([unnamed superentity] == nil);

        /* OBSERVED: the list keeps the order it was given in */
        NSEntityDescription *f = entityNamed(@"F"), *d = entityNamed(@"D"), *e = entityNamed(@"E");
        NSEntityDescription *ordered = entityNamed(@"Ordered");
        [ordered setSubentities:[NSArray arrayWithObjects:f, d, e, nil]];
        CHECK([[ordered subentities] isEqual:[NSArray arrayWithObjects:f, d, e, nil]]);

        /* subentitiesByName is keyed by the sub-entity names, so a rename moves the key (OBSERVED) */
        [dog setName:@"Hound"];
        CHECK([[animal subentitiesByName] objectForKey:@"Hound"] == dog && [[animal subentitiesByName] objectForKey:@"Dog"] == nil);
        CHECK([[animal subentitiesByName] count] == 1);
        /* OBSERVED: a rename to a sibling's name raises and changes nothing */
        NSEntityDescription *wolf = entityNamed(@"Wolf");
        [animal setSubentities:[NSArray arrayWithObjects:dog, wolf, nil]];
        CHECK([raiseName(^{ [wolf setName:@"Hound"]; }) isEqual:NSInternalInconsistencyException]);
        CHECK([[wolf name] isEqual:@"Wolf"] && [[animal subentitiesByName] objectForKey:@"Wolf"] == wolf);
        [wolf setName:@"Wolf2"];
        CHECK([[animal subentitiesByName] objectForKey:@"Wolf2"] == wolf && [[animal subentitiesByName] count] == 2);

        /* once the model is used by a coordinator, setSubentities: raises (OBSERVED: NSInternalInconsistencyException)
           and nothing changes */
        [animal setSubentities:[NSArray arrayWithObject:dog]];
        NSManagedObjectModel *model = [[[NSManagedObjectModel alloc] init] autorelease];
        [model setEntities:[NSArray arrayWithObjects:animal, dog, puppy, nil]];
        NSPersistentStoreCoordinator *coordinator =
            [[[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:model] autorelease];
        (void)coordinator;
        CHECK([raiseName(^{ [animal setSubentities:[NSArray array]]; }) isEqual:NSInternalInconsistencyException]);
        CHECK([[animal subentitiesByName] objectForKey:@"Hound"] == dog && [dog superentity] == animal);
    }
    if (!failures) printf("PASS\n");
    return failures;
}
