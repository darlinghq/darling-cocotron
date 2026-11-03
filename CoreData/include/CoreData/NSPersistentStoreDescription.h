#import <Foundation/Foundation.h>

@interface NSPersistentStoreDescription : NSObject {
    NSURL *_URL;
    NSString *_type;
    NSString *_configuration;
    NSMutableDictionary *_options;
    BOOL _shouldAddStoreAsynchronously;
}

+ (instancetype)persistentStoreDescriptionWithURL:(NSURL *)URL;
- (instancetype)initWithURL:(NSURL *)URL;
@property(copy) NSURL *URL;
@property(copy) NSString *type;
@property(copy) NSString *configuration;
@property(getter=isReadOnly) BOOL readOnly;
@property BOOL shouldAddStoreAsynchronously;
@property BOOL shouldMigrateStoreAutomatically;
@property BOOL shouldInferMappingModelAutomatically;
@property(readonly, copy) NSDictionary *options;
- (void)setOption:(NSObject *)option forKey:(NSString *)key;

@end
