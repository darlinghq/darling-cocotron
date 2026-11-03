#import <Foundation/Foundation.h>
#import <CoreData/CoreData.h>

static NSUInteger initialized, deallocated;
@interface AuthoredDescription : NSPersistentStoreDescription
@end
@implementation AuthoredDescription
- (instancetype)initWithURL:(NSURL *)URL {
    self = [super initWithURL:URL];
    if (self) initialized++;
    return self;
}
- (void)dealloc {
    deallocated++;
    [super dealloc];
}
@end

int main(void) {
    @autoreleasepool {
        @try {
            NSURL *URL = [NSURL fileURLWithPath:@"/authored-description-no-io"];
            NSPersistentStoreDescription *one = [NSPersistentStoreDescription persistentStoreDescriptionWithURL:URL];
            NSPersistentStoreDescription *two = [NSPersistentStoreDescription persistentStoreDescriptionWithURL:URL];
            NSPersistentStoreDescription *direct = [[[NSPersistentStoreDescription alloc] initWithURL:URL] autorelease];
            if (one == two || ![one.URL isEqual:URL] || ![two.URL isEqual:URL] ||
                ![one.type isEqual:direct.type] || ![one.options isEqual:direct.options] ||
                one.readOnly != direct.readOnly || one.shouldAddStoreAsynchronously != direct.shouldAddStoreAsynchronously ||
                one.shouldMigrateStoreAutomatically != direct.shouldMigrateStoreAutomatically ||
                one.shouldInferMappingModelAutomatically != direct.shouldInferMappingModelAutomatically)
                return 123;
            AuthoredDescription *retained;
            @autoreleasepool {
                retained = [[AuthoredDescription persistentStoreDescriptionWithURL:URL] retain];
                AuthoredDescription *temporary = [AuthoredDescription persistentStoreDescriptionWithURL:URL];
                if (![retained isKindOfClass:[AuthoredDescription class]] ||
                    ![temporary isKindOfClass:[AuthoredDescription class]] || initialized != 2 || deallocated != 0)
                    return 124;
            }
            if (deallocated != 1 || ![retained.URL isEqual:URL])
                return 125;
            [retained release];
            return deallocated == 2 ? 0 : 126;
        } @catch (NSException *exception) {
            (void)exception;
            return 127;
        }
    }
}
