#import <CoreData/NSManagedObjectModel.h>

@class NSEntityDescription;

@interface NSManagedObjectModel (DarlingModelConstruction)
- (void)_setInUse;
- (void)_renameEntity:(NSEntityDescription *)entity from:(NSString *)oldName to:(NSString *)newName;
+ (NSEntityDescription *)_entityForManagedClass:(Class)managedClass;
@end
