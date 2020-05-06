#import <Foundation/Foundation.h>

@interface _NSFileSystemDataSource : NSObject {
    NSMutableSet *_cachedPaths;
    NSFileManager *_fileManager;
}

@end
