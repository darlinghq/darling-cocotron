#import <Foundation/Foundation.h>
#include <stdio.h>

@protocol StoreDescriptionContract <NSObject>
- (id)initWithURL:(NSURL *)URL;
- (NSURL *)URL;
- (void)setURL:(NSURL *)URL;
- (NSString *)type;
- (void)setType:(NSString *)type;
- (NSString *)configuration;
- (void)setConfiguration:(NSString *)configuration;
- (BOOL)isReadOnly;
- (void)setReadOnly:(BOOL)value;
- (BOOL)shouldAddStoreAsynchronously;
- (void)setShouldAddStoreAsynchronously:(BOOL)value;
- (NSDictionary *)options;
- (void)setOption:(NSObject *)option forKey:(NSString *)key;
@end

#define CHECK(condition) do { if (!(condition)) return 1; } while (0)

int main(void) {
    @autoreleasepool {
        Class descriptionClass = NSClassFromString(@"NSPersistentStoreDescription");
        if (descriptionClass == Nil)
            return 44;
        NSURL *first = [NSURL fileURLWithPath:@"/first-store"];
        NSURL *second = [NSURL fileURLWithPath:@"/second-store"];
        id<StoreDescriptionContract> description = [[descriptionClass alloc] initWithURL:first];
        CHECK([[description URL] isEqual:first]);
        CHECK(![description shouldAddStoreAsynchronously]);
        [description setURL:second];
        [description setType:@"TestStore"];
        [description setConfiguration:@"TestConfiguration"];
        [description setReadOnly:YES];
        [description setShouldAddStoreAsynchronously:YES];
        [description setOption:@42 forKey:@"TestOption"];
        CHECK([[description URL] isEqual:second]);
        CHECK([[description type] isEqual:@"TestStore"]);
        CHECK([[description configuration] isEqual:@"TestConfiguration"]);
        CHECK([description isReadOnly]);
        CHECK([description shouldAddStoreAsynchronously]);
        CHECK([[[description options] objectForKey:@"TestOption"] isEqual:@42]);
        [description setOption:nil forKey:@"TestOption"];
        CHECK([[description options] objectForKey:@"TestOption"] == nil);
        [description release];
        puts("PASS_COREDATA_STORE_DESCRIPTION");
    }
    return 0;
}
