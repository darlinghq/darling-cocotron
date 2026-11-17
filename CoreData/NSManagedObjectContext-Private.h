#import <CoreData/NSManagedObjectContext.h>

@class NSAtomicStoreCacheNode, NSPersistentStoreCoordinator;

@interface NSManagedObjectContext (private)
- (NSAtomicStoreCacheNode *) _cacheNodeForObjectID:
        (NSManagedObjectID *) objectID;
- (void) _registerObject: (NSManagedObject *) object;
- (NSPersistentStoreCoordinator *) _coordinator;
- (void) _performSync: (void (^)(void)) block;
- (NSDictionary *) _snapshotForObjectID: (NSManagedObjectID *) objectID;
- (void) _markDeleted: (NSManagedObject *) object;
- (void) _adoptChangesInserted: (NSSet *) inserted updated: (NSSet *) updated deleted: (NSSet *) deleted;
@end
