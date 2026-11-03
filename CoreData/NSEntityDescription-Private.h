#import <CoreData/NSEntityDescription.h>

@interface NSEntityDescription (private)
- (BOOL) _isKindOfEntity: (NSEntityDescription *) other;
- (NSPropertyDescription *) _propertyForSelector: (SEL) selector;
- (void)_setManagedObjectModel:(NSManagedObjectModel *)model;
- (void)_setInUse;
- (void)_renameProperty:(NSPropertyDescription *)property from:(NSString *)oldName to:(NSString *)newName;
@end
