#import "NSManagedObjectSet.h"
#import "NSManagedObjectSetEnumerator.h"
#import <CoreData/NSManagedObject.h>
#import <CoreData/NSManagedObjectContext.h>

@implementation NSManagedObjectSet

- initWithManagedObjectContext: (NSManagedObjectContext *) context
                           set: (NSSet *) set {
    _context = [context retain];
    _set = [set retain];
    return self;
}

- (void) dealloc {
    [_context release];
    [_set release];
    [super dealloc];
}

- (NSUInteger) count {
    return [_set count];
}

- member: object {
    return [_set member: [object objectID]];
}

- (NSEnumerator *) objectEnumerator {
    NSEnumerator *state = [_set objectEnumerator];

    if (state == nil) {
        return nil;
    }

    return [[[NSManagedObjectSetEnumerator alloc]
        initWithManagedObjectContext: _context
                    objectEnumerator: state] autorelease];
}

@end
