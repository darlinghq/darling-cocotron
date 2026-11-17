#import "_NSFileSystemDataSource.h"
#import <AppKit/NSOutlineView.h>
#import <AppKit/NSTableColumn.h>

@implementation _NSFileSystemDataSource

@synthesize showsHiddenFiles = _showsHiddenFiles;
@synthesize enabledBlock = _enabledBlock;

- (id) init {
    self = [super init];
    _fileManager = [[NSFileManager defaultManager] retain];
    _entries = [[NSMutableArray alloc] init];
    _directoryFlags = [[NSMutableArray alloc] init];
    _enabledFlags = [[NSMutableArray alloc] init];
    return self;
}

- (void) dealloc {
    [_fileManager release];
    [_rootURL release];
    [_entries release];
    [_directoryFlags release];
    [_enabledFlags release];
    [_enabledBlock release];
    [super dealloc];
}

- (void) setRootURL: (NSURL *) url {
    url = [url retain];
    [_rootURL release];
    _rootURL = url;
}

- (NSURL *) rootURL {
    if (_rootURL != nil)
        return _rootURL;
    return [NSURL fileURLWithPath: @"/" isDirectory: YES];
}

- (void) reload {
    [_entries removeAllObjects];
    [_directoryFlags removeAllObjects];
    [_enabledFlags removeAllObjects];

    NSArray *urls = [_fileManager contentsOfDirectoryAtURL: [self rootURL]
                                includingPropertiesForKeys: nil
                                                   options: 0
                                                     error: nil];
    NSMutableArray *shown = [NSMutableArray arrayWithCapacity: [urls count]];
    for (NSURL *url in urls) {
        if (!_showsHiddenFiles && [[url lastPathComponent] hasPrefix: @"."])
            continue;
        [shown addObject: url];
    }
    [shown sortUsingComparator: ^NSComparisonResult(NSURL *a, NSURL *b) {
        return [[a lastPathComponent]
                localizedStandardCompare: [b lastPathComponent]];
    }];

    for (NSURL *url in shown) {
        BOOL isDirectory = NO;
        [_fileManager fileExistsAtPath: [url path] isDirectory: &isDirectory];
        [_entries addObject: url];
        [_directoryFlags addObject: [NSNumber numberWithBool: isDirectory]];
        [_enabledFlags addObject:
                [NSNumber numberWithBool: _enabledBlock == nil ||
                                                  _enabledBlock(url, isDirectory)]];
    }
}

- (NSArray *) entries {
    return _entries;
}

- (NSUInteger) indexOfEntry: (NSURL *) url {
    return [_entries indexOfObjectIdenticalTo: url];
}

- (BOOL) isDirectoryEntry: (NSURL *) url {
    NSUInteger index = [self indexOfEntry: url];
    return index != NSNotFound && [[_directoryFlags objectAtIndex: index] boolValue];
}

- (BOOL) isEnabledEntry: (NSURL *) url {
    NSUInteger index = [self indexOfEntry: url];
    return index != NSNotFound && [[_enabledFlags objectAtIndex: index] boolValue];
}

- (NSInteger) outlineView: (NSOutlineView *) outlineView
        numberOfChildrenOfItem: (NSURL *) url
{
    return url == nil ? [_entries count] : 0;
}

- (BOOL) outlineView: (NSOutlineView *) outlineView
        isItemExpandable: (NSURL *) url
{
    return NO;
}

- (NSURL *) outlineView: (NSOutlineView *) outlineView
                  child: (NSInteger) index
                 ofItem: (NSURL *) url
{
    return [_entries objectAtIndex: index];
}

- (NSString *) outlineView: (NSOutlineView *) outlineView
        objectValueForTableColumn: (NSTableColumn *) tableColumn
                           byItem: (NSURL *) url
{
    if ([[tableColumn identifier] isEqual: @"kind"]) {
        NSBundle *bundle = [NSBundle bundleForClass: [self class]];
        if ([self isDirectoryEntry: url]) {
            if ([[[url pathExtension] lowercaseString] isEqual: @"app"])
                return NSLocalizedStringFromTableInBundle(
                        @"Application", nil, bundle,
                        @"The kind of an application in a file panel");
            return NSLocalizedStringFromTableInBundle(
                    @"Folder", nil, bundle, @"The kind of a folder in a file panel");
        }
        return NSLocalizedStringFromTableInBundle(
                @"Document", nil, bundle, @"The kind of a file in a file panel");
    }
    return [url lastPathComponent];
}

@end
