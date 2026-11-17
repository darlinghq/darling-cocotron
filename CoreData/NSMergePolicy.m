#import <CoreData/NSMergePolicy.h>

id NSErrorMergePolicy = nil;
id NSMergeByPropertyStoreTrumpMergePolicy = nil;
id NSMergeByPropertyObjectTrumpMergePolicy = nil;
id NSOverwriteMergePolicy = nil;
id NSRollbackMergePolicy = nil;

@implementation NSMergePolicy
+ (void)initialize {
    if (self == [NSMergePolicy class]) {
        NSErrorMergePolicy = [self new];
        NSMergeByPropertyStoreTrumpMergePolicy = [self new];
        NSMergeByPropertyObjectTrumpMergePolicy = [self new];
        NSOverwriteMergePolicy = [self new];
        NSRollbackMergePolicy = [self new];
    }
}
@end
