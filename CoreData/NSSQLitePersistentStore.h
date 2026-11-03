#import <CoreData/NSAtomicStore.h>
#include <sqlite3.h>

@interface NSSQLitePersistentStore : NSAtomicStore {
    sqlite3 *_database;
    NSData *_modelDescription;
    NSArray *_selectedEntities;
    long long _revision;
}
- (BOOL)_commitInserted:(NSSet *)inserted updated:(NSSet *)updated deleted:(NSSet *)deleted error:(NSError **)error;
- (long long)_versionForObjectID:(NSManagedObjectID *)objectID;
@end
