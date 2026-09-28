#import "NSImageDrawingCache.h"

static const NSUInteger drawingCacheByteLimit = 16 * 1024 * 1024;
static const NSUInteger drawingCacheEntryLimit = 4;

@implementation NSImageDrawingCache
- (instancetype) init {
    if ((self = [super init]))
        _entries = [NSMutableArray new];
    return self;
}
- (void) dealloc {
    [_entries release];
    [super dealloc];
}
- (id) representationForKey: (id) key {
    for (NSUInteger i = 0; i < [_entries count]; ++i) {
        NSArray *entry = [_entries objectAtIndex: i];
        if ([[entry objectAtIndex: 0] isEqual: key]) {
            [entry retain];
            [_entries removeObjectAtIndex: i];
            [_entries addObject: entry];
            [entry release];
            return [entry objectAtIndex: 1];
        }
    }
    return nil;
}
- (BOOL) setRepresentation: (id) representation forKey: (id<NSCopying>) key
                 byteCost: (NSUInteger) cost {
    if (representation == nil || key == nil || cost > drawingCacheByteLimit)
        return NO;
    // Construct before removing an old entry: the caller may be replacing an
    // entry with the very same key or representation object it currently owns.
    id storedKey = [(id)key copy];
    NSArray *entry = [[NSArray alloc] initWithObjects: storedKey, representation,
            [NSNumber numberWithUnsignedInteger: cost], nil];
    [storedKey release];
    for (NSUInteger i = 0; i < [_entries count]; ++i) {
        NSArray *old = [_entries objectAtIndex: i];
        if ([[old objectAtIndex: 0] isEqual: (id)key]) {
            _byteCost -= [[old objectAtIndex: 2] unsignedIntegerValue];
            [_entries removeObjectAtIndex: i];
            break;
        }
    }
    while ([_entries count] >= drawingCacheEntryLimit ||
           _byteCost > drawingCacheByteLimit - cost) {
        NSArray *old = [_entries objectAtIndex: 0];
        _byteCost -= [[old objectAtIndex: 2] unsignedIntegerValue];
        [_entries removeObjectAtIndex: 0];
    }
    [_entries addObject: entry];
    [entry release];
    _byteCost += cost;
    return YES;
}
- (void) removeAllObjects {
    ++_generation;
    [_entries removeAllObjects];
    _byteCost = 0;
}
- (NSUInteger) generation {
    return _generation;
}
- (NSUInteger) byteCost {
    return _byteCost;
}
@end
