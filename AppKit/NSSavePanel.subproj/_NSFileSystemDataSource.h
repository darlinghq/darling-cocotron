#import <Foundation/Foundation.h>

// The flat list of one folder shown by the open and save panels: the folder's
// entries, sorted by name. Which entries are enabled is decided by a block.
@interface _NSFileSystemDataSource : NSObject {
    NSFileManager *_fileManager;
    NSURL *_rootURL;
    NSMutableArray *_entries;
    NSMutableArray *_directoryFlags;
    NSMutableArray *_enabledFlags;
    BOOL _showsHiddenFiles;
    BOOL (^_enabledBlock)(NSURL *url, BOOL isDirectory);
}

// The folder listed; nil lists "/".
- (void) setRootURL: (NSURL *) url;
- (NSURL *) rootURL;

@property(nonatomic) BOOL showsHiddenFiles;
// Called for every entry when the folder is read, to learn whether the user can select it.
@property(nonatomic, copy) BOOL (^enabledBlock)(NSURL *url, BOOL isDirectory);

// Reads the folder again.
- (void) reload;
- (NSArray *) entries;
- (BOOL) isDirectoryEntry: (NSURL *) url;
- (BOOL) isEnabledEntry: (NSURL *) url;

@end
