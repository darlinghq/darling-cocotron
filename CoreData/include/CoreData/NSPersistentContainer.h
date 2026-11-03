#import <Foundation/Foundation.h>

@class NSManagedObjectContext, NSManagedObjectModel;
@class NSPersistentStoreCoordinator, NSPersistentStoreDescription;

@interface NSPersistentContainer : NSObject {
    NSString *_name;
    NSManagedObjectModel *_managedObjectModel;
    NSPersistentStoreCoordinator *_persistentStoreCoordinator;
    NSManagedObjectContext *_viewContext;
    NSArray *_persistentStoreDescriptions;
    NSError *_modelError;
}

+ (NSURL *)defaultDirectoryURL;
- (instancetype)initWithName:(NSString *)name;
- (instancetype)initWithName:(NSString *)name managedObjectModel:(NSManagedObjectModel *)model;
@property(readonly, copy) NSString *name;
@property(readonly, retain) NSManagedObjectModel *managedObjectModel;
@property(readonly, retain) NSPersistentStoreCoordinator *persistentStoreCoordinator;
@property(readonly, retain) NSManagedObjectContext *viewContext;
@property(copy) NSArray *persistentStoreDescriptions;
- (void)loadPersistentStoresWithCompletionHandler:(void (^)(NSPersistentStoreDescription *, NSError *))block;
- (NSManagedObjectContext *)newBackgroundContext;
- (void)performBackgroundTask:(void (^)(NSManagedObjectContext *))block;

@end
