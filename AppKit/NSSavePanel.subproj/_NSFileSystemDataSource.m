#import "_NSFileSystemDataSource.h"
#include <stdlib.h>
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
    // A folder can have tens of thousands of entries, so the work per entry must not leave
    // temporary strings behind (they would all stay alive until the run loop's pool drains):
    // each name is made once, the sort compares those names, and the loops drain their own pools.
    NSUInteger count = [urls count];
    NSMutableArray *names = [NSMutableArray arrayWithCapacity: count];
    NSUInteger *order = malloc(sizeof(NSUInteger) * (count + 1));
    NSUInteger shown = 0;
    for (NSUInteger i = 0; i < count; i++) {
        @autoreleasepool {
            NSString *name = [[urls objectAtIndex: i] lastPathComponent];
            if (!_showsHiddenFiles && [name hasPrefix: @"."])
                continue;
            [names addObject: name];
            order[shown++] = i;
        }
    }
    // order holds URL indexes while names holds the shown names in the same sequence; sort by
    // position in names, then translate to URL indexes
    NSUInteger *position = malloc(sizeof(NSUInteger) * (shown + 1));
    for (NSUInteger i = 0; i < shown; i++)
        position[i] = i;
    qsort_b(position, shown, sizeof(NSUInteger), ^int(const void *a, const void *b) {
        return (int) [[names objectAtIndex: *(const NSUInteger *) a]
                localizedStandardCompare: [names objectAtIndex: *(const NSUInteger *) b]];
    });

    for (NSUInteger i = 0; i < shown; i++) {
        @autoreleasepool {
            NSURL *url = [urls objectAtIndex: order[position[i]]];
            BOOL isDirectory = NO;
            [_fileManager fileExistsAtPath: [url path] isDirectory: &isDirectory];
            [_entries addObject: url];
            [_directoryFlags addObject: [NSNumber numberWithBool: isDirectory]];
            [_enabledFlags addObject:
                    [NSNumber numberWithBool: _enabledBlock == nil ||
                                                      _enabledBlock(url, isDirectory)]];
        }
    }
    free(position);
    free(order);
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
