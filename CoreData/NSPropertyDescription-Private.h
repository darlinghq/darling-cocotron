#import <CoreData/NSPropertyDescription.h>

@interface NSPropertyDescription (DarlingModelConstruction)
- (void)_setEntity:(NSEntityDescription *)entity;
- (void)_checkMutable;
@end
