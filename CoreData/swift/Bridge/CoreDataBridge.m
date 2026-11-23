#import "CoreDataBridge.h"
NSArray *DarlingCoreDataExecuteFetch(NSManagedObjectContext *context, id request, NSError **error) {
    return [context executeFetchRequest:(NSFetchRequest *)request error:error];
}
