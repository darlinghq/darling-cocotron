#import <Foundation/Foundation.h>

// Private, image-owned LRU storage. Callers define destination keys and account
// for the raster's byte cost; entries must only be inserted after a valid draw.
@interface NSImageDrawingCache : NSObject {
    NSMutableArray *_entries;
    NSUInteger _byteCost;
    NSUInteger _generation;
}
- (id) representationForKey: (id) key;
- (BOOL) setRepresentation: (id) representation forKey: (id<NSCopying>) key
                 byteCost: (NSUInteger) cost;
- (void) removeAllObjects;
- (NSUInteger) generation;
- (NSUInteger) byteCost;
@end
