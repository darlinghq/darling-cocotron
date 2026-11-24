#import <CoreData/NSManagedObject.h>

@interface NSManagedObject (private)
- initWithObjectID: (NSManagedObjectID *) objectID
        managedObjectContext: (NSManagedObjectContext *) context;
- (void)_setInserted:(BOOL)inserted updated:(BOOL)updated deleted:(BOOL)deleted;
- (void)_didCommit;
- (long long)_storeVersion;
- (void)_mergeCommittedValues;
- (void)_reloadCommittedValuesDiscardingChanges:(BOOL)discard;
- (void)_discardInsertedValues;
- (void)_dropChangedValuesEqualToCommitted;
- (void)_discardPendingValues;
- (NSDictionary *) _committedValues;
@end
