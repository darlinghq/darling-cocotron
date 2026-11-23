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
// marked GUESS pin choices the pages leave open (they are not observed on macOS). Prints PASS
// when everything holds; the exit code is the number of failed checks.

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
        [animal setSubentities:[NSArray arrayWithObjects:dog, cat, nil]];
        CHECK([[NSSet setWithArray:[animal subentities]] isEqual:[NSSet setWithObjects:dog, cat, nil]]);
        CHECK([[animal subentitiesByName] objectForKey:@"Dog"] == dog);
        CHECK([[animal subentitiesByName] objectForKey:@"Cat"] == cat);
        CHECK([[animal subentitiesByName] count] == 2);
        CHECK([dog superentity] == animal && [cat superentity] == animal);
        CHECK([animal superentity] == nil);

        /* a second level */
        [dog setSubentities:[NSArray arrayWithObject:puppy]];
        CHECK([puppy superentity] == dog && [dog superentity] == animal);

        /* replacing the list releases the entities that are no longer listed */
        [animal setSubentities:[NSArray arrayWithObject:dog]];
        CHECK([[animal subentitiesByName] count] == 1 && [cat superentity] == nil && [dog superentity] == animal);
        /* setting the same entity again is fine, and nil clears */
        [animal setSubentities:[NSArray arrayWithObject:dog]];
        CHECK([dog superentity] == animal);
        [animal setSubentities:nil];
        CHECK([[animal subentities] count] == 0 && [dog superentity] == nil);
        CHECK([puppy superentity] == dog);   /* the lower level is untouched */

        /* GUESS: invalid lists raise NSInvalidArgumentException and change nothing */
        [animal setSubentities:[NSArray arrayWithObject:dog]];
        NSEntityDescription *other = entityNamed(@"Other");
        CHECK([raiseName(^{ [other setSubentities:[NSArray arrayWithObject:dog]]; }) isEqual:NSInvalidArgumentException]);   /* already has a superentity */
        CHECK([dog superentity] == animal && [[other subentities] count] == 0);
        CHECK([raiseName(^{ [dog setSubentities:[NSArray arrayWithObject:animal]]; }) isEqual:NSInvalidArgumentException]);   /* ancestor */
        CHECK([raiseName(^{ [other setSubentities:[NSArray arrayWithObject:other]]; }) isEqual:NSInvalidArgumentException]);  /* itself */
        CHECK([raiseName(^{ [other setSubentities:[NSArray arrayWithObject:@"Dog"]]; }) isEqual:NSInvalidArgumentException]); /* not an entity */
        NSEntityDescription *twin = entityNamed(@"Cat");
        NSEntityDescription *twin2 = entityNamed(@"Cat");
        CHECK([raiseName(^{ [other setSubentities:[NSArray arrayWithObjects:twin, twin2, nil]]; }) isEqual:NSInvalidArgumentException]); /* same name */
        CHECK([twin superentity] == nil && [twin2 superentity] == nil && [[other subentities] count] == 0);

        /* the returned dictionary is a snapshot, not the entity's own storage */
        NSDictionary *snapshot = [animal subentitiesByName];
        CHECK(![snapshot isKindOfClass:[NSMutableDictionary class]]);
        [animal setSubentities:nil];
        CHECK([snapshot count] == 1 && [[animal subentitiesByName] count] == 0);
        [animal setSubentities:[NSArray arrayWithObject:dog]];

        /* an entity without a name cannot be a sub-entity (GUESS: raises) */
        NSEntityDescription *unnamed = [[[NSEntityDescription alloc] init] autorelease];
        CHECK([raiseName(^{ [other setSubentities:[NSArray arrayWithObject:unnamed]]; }) isEqual:NSInvalidArgumentException]);
        CHECK([unnamed superentity] == nil);

        /* subentitiesByName is keyed by the sub-entity names, so a rename moves the key */
        NSDictionary *beforeRename = [animal subentitiesByName];
        [dog setName:@"Hound"];
        CHECK([[animal subentitiesByName] objectForKey:@"Hound"] == dog && [[animal subentitiesByName] objectForKey:@"Dog"] == nil);
        CHECK([[animal subentitiesByName] count] == 1 && [beforeRename objectForKey:@"Dog"] == dog);
        /* GUESS: a rename to a sibling's name raises and changes nothing */
        NSEntityDescription *wolf = entityNamed(@"Wolf");
        [animal setSubentities:[NSArray arrayWithObjects:dog, wolf, nil]];
        CHECK([raiseName(^{ [wolf setName:@"Hound"]; }) isEqual:NSInvalidArgumentException]);
        CHECK([[wolf name] isEqual:@"Wolf"] && [[animal subentitiesByName] objectForKey:@"Wolf"] == wolf);
        [wolf setName:@"Wolf2"];
        CHECK([[animal subentitiesByName] objectForKey:@"Wolf2"] == wolf && [[animal subentitiesByName] count] == 2);
        /* setName:nil does not raise for a sub-entity (it did not before sub-entities could be set) */
        CHECK(raiseName(^{ [dog setName:nil]; }) == nil);
        CHECK([[animal subentitiesByName] objectForKey:@"Hound"] == nil && [dog superentity] == animal);
        [dog setName:@"Dog"];
        CHECK([[animal subentitiesByName] objectForKey:@"Dog"] == dog);
        [animal setSubentities:[NSArray arrayWithObject:dog]];

        /* GUESS: an entity of another model is refused */
        NSEntityDescription *foreign = entityNamed(@"Foreign");
        NSManagedObjectModel *foreignModel = [[[NSManagedObjectModel alloc] init] autorelease];
        [foreignModel setEntities:[NSArray arrayWithObject:foreign]];
        NSEntityDescription *local = entityNamed(@"Local");
        NSManagedObjectModel *localModel = [[[NSManagedObjectModel alloc] init] autorelease];
        [localModel setEntities:[NSArray arrayWithObject:local]];
        CHECK([raiseName(^{ [local setSubentities:[NSArray arrayWithObject:foreign]]; }) isEqual:NSInvalidArgumentException]);
        CHECK([foreign superentity] == nil);

        /* GUESS: an entity whose model is in use is refused, and keeps its superentity (nil) */
        NSEntityDescription *live = entityNamed(@"Live");
        NSManagedObjectModel *liveModel = [[[NSManagedObjectModel alloc] init] autorelease];
        [liveModel setEntities:[NSArray arrayWithObject:live]];
        NSPersistentStoreCoordinator *liveCoordinator =
            [[[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:liveModel] autorelease];
        (void)liveCoordinator;
        NSEntityDescription *fresh = entityNamed(@"Fresh");
        CHECK([raiseName(^{ [fresh setSubentities:[NSArray arrayWithObject:live]]; }) isEqual:NSInvalidArgumentException]);
        CHECK([live superentity] == nil && [[fresh subentities] count] == 0);

        /* once the model is used by a coordinator, setSubentities: raises and nothing changes */
        NSManagedObjectModel *model = [[[NSManagedObjectModel alloc] init] autorelease];
        [model setEntities:[NSArray arrayWithObjects:animal, dog, puppy, nil]];
        NSPersistentStoreCoordinator *coordinator =
            [[[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:model] autorelease];
        (void)coordinator;
        CHECK(raiseName(^{ [animal setSubentities:nil]; }) != nil);
        CHECK([[animal subentitiesByName] objectForKey:@"Dog"] == dog && [dog superentity] == animal);
    }
    if (!failures) printf("PASS\n");
    return failures;
}
