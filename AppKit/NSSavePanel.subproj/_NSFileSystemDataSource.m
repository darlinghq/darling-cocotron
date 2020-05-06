#import "_NSFileSystemDataSource.h"
#import <AppKit/NSOutlineView.h>

@implementation _NSFileSystemDataSource

- (id) init {
    self = [super init];
    _cachedPaths = [[NSMutableSet alloc] init];
    _fileManager = [[NSFileManager defaultManager] retain];
    return self;
}

- (void) dealloc {
    [_cachedPaths release];
    [_fileManager release];
    [super dealloc];
}

- (NSInteger) outlineView: (NSOutlineView *) outlineView
    numberOfChildrenOfItem: (NSURL *) url {
    if (url == nil) {
        url = [NSURL URLWithString: @"/"];
    }
    return [[_fileManager contentsOfDirectoryAtURL: url
                        includingPropertiesForKeys: nil
                                           options: 0
                                             error: nil] count];
}

- (BOOL) outlineView: (NSOutlineView *) outlineView
    isItemExpandable: (NSURL *) url {
    if (url == nil) {
        return YES;
    }

    BOOL isDirectory;
    [_fileManager fileExistsAtPath: [url path] isDirectory: &isDirectory];
    return isDirectory;
}

- (NSURL *) outlineView: (NSOutlineView *) outlineView
                  child: (NSInteger) index
                 ofItem: (NSURL *) url {
    if (url == nil) {
        url = [NSURL URLWithString: @"/"];
    }
    NSArray *items = [_fileManager contentsOfDirectoryAtURL: url
                                 includingPropertiesForKeys: nil
                                                    options: 0
                                                      error: nil];
    // TODO: sort
    NSURL *preRes = [items objectAtIndex: index];
    NSURL *res = [_cachedPaths member: preRes];
    if (res == nil) {
        [_cachedPaths addObject: preRes];
        res = preRes;
    }

    return res;
}

- (NSString *) outlineView: (NSOutlineView *) outlineView
    objectValueForTableColumn: (NSTableColumn *) tableColumn
                       byItem: (NSURL *) url {
    return [[url pathComponents] lastObject];
}

@end
