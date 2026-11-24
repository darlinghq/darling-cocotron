/* Copyright (c) 2006-2007 Christopher J. W. Lloyd

Permission is hereby granted, free of charge, to any person obtaining a copy of
this software and associated documentation files (the "Software"), to deal in
the Software without restriction, including without limitation the rights to
use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
the Software, and to permit persons to whom the Software is furnished to do so,
subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */

#import "NSCustomObject.h"
#import "NSIBObjectData.h"
#import "NSNibHelpConnector.h"
#import <AppKit/NSApplication.h>
#import <AppKit/NSMenu.h>
#import <AppKit/NSNib.h>
#import <AppKit/NSNibLoading.h>
#import <AppKit/NSRaise.h>
#import <AppKit/NSTableCornerView.h>
#import <AppKit/NSToolbar.h>
#import <Foundation/NSKeyedArchiver.h>
#import <Foundation/NSProcessInfo.h>
#import <Foundation/NSURL.h>
#import <UIFoundation/UIFoundation.h>
#import <UIFoundation/UINibDecoder.h>
#include <string.h>

NSString *const NSNibOwner = @"NSOwner";
NSString *const NSNibTopLevelObjects = @"NSNibTopLevelObjects";

@interface NSToolbar (NSNibConnections)
- (void) _nibDidConnectObjects;
@end

// NSArchiver data starts with its typedstream signature; anything else is a keyed archive or a
// NIBArchive.
static BOOL NSNibDataIsKeyed(NSData *data) {
    static const char typedstream[] = "\x04\x0bstreamtyped";
    return !([data length] >= sizeof(typedstream) - 1 &&
             memcmp([data bytes], typedstream, sizeof(typedstream) - 1) == 0);
}

@implementation NSNib

- initWithCoder: (NSCoder *) coder {
    if ([coder allowsKeyedCoding]) {
        _data = [[coder decodeObjectForKey: @"NSNibFileData"] retain];
        // A nib archived inside another nib (the nib of a table's cell views, for one) is
        // instantiated like any other nib, so it has to know which kind of archive it holds.
        _flags._isKeyed = NSNibDataIsKeyed(_data);

        // TODO: NSNibFileIsKeyed
        // NSNibFileUseParentBundle
        // NSNibFileBundleName
        // NSNibFileImages
        // NSNibFileSounds
    } else {
        NSString *bundleIdentifier;
        short isKeyed = 0;
        NSArray *imageBlobs, *soundBlobs;
        NSArray *images, *sounds;

        [coder decodeValuesOfObjCTypes: "@s@@@@@", &_data, &isKeyed,
                                        &bundleIdentifier, &images, &imageBlobs,
                                        &sounds, &soundBlobs];

        // TODO
        [bundleIdentifier release];
        [imageBlobs release];
        [images release];
        [soundBlobs release];
        [sounds release];
    }

    return self;
}

// Nibs built for newer systems sit next to the plain keyedobjects.nib as keyedobjects-<version>.nib,
// where the version is the minimum system version written as MMmmpp (101300 for 10.13). Returns
// the newest one that this system can read, or nil when there is none.
+ (NSString *) _versionedKeyedObjectsPathInDirectory: (NSString *) directory {
    NSOperatingSystemVersion os = [[NSProcessInfo processInfo] operatingSystemVersion];
    long current = os.majorVersion * 10000 + os.minorVersion * 100 + os.patchVersion;
    NSString *best = nil;
    long bestVersion = 0;

    for (NSString *name in [[NSFileManager defaultManager] contentsOfDirectoryAtPath: directory
                                                                               error: NULL]) {
        if (![name hasPrefix: @"keyedobjects-"] || ![name hasSuffix: @".nib"])
            continue;
        NSString *digits = [name substringWithRange: NSMakeRange(13, [name length] - 13 - 4)];
        NSScanner *scanner = [NSScanner scannerWithString: digits];
        long long version;
        if (![scanner scanLongLong: &version] || ![scanner isAtEnd] || version <= 0)
            continue;
        if (version <= current && version > bestVersion) {
            best = name;
            bestVersion = (long) version;
        }
    }
    return best != nil ? [directory stringByAppendingPathComponent: best] : nil;
}

- initWithContentsOfFile: (NSString *) path {

    NIBDEBUG(@"initWithContentsOfFile: %@", path);

    NSString *objects = path;
    BOOL isDirectory = NO;

    if (![[NSFileManager defaultManager] fileExistsAtPath: path
                                              isDirectory: &isDirectory]) {
        [self release];
        return nil;
    }
    if (isDirectory) {
        objects = [NSNib _versionedKeyedObjectsPathInDirectory: path];
        if (objects == nil)
            objects = [[path stringByAppendingPathComponent: @"keyedobjects"]
                    stringByAppendingPathExtension: @"nib"];

        if ([[NSFileManager defaultManager] fileExistsAtPath: objects])
            _flags._isKeyed = TRUE;
        else
            objects = [[path stringByAppendingPathComponent: @"objects"]
                    stringByAppendingPathExtension: @"nib"];
    } else {
        // FIXME: Should we try to infer keyed-ness form the file itself in this
        // case?
        _flags._isKeyed = TRUE;
    }

    if (!objects && !isDirectory) {
        objects = path; // assume new-style compiled xib
        _flags._isKeyed = TRUE;
    }

    if ((_data = [[NSData alloc] initWithContentsOfFile: objects]) == nil) {
        [self release];
        return nil;
    }

    _allObjects = [NSMutableArray new];

    return self;
}

- initWithNibData: (NSData *) data bundle: (NSBundle *) bundle {
    if (data == nil) {
        [self release];
        return nil;
    }
    _data = [data copy];
    // The bundle is not kept, as for a nib read from a file.
    _flags._isKeyed = NSNibDataIsKeyed(_data);
    _allObjects = [NSMutableArray new];
    return self;
}

- initWithContentsOfURL: (NSURL *) url {

    NIBDEBUG(@"initWithContentsOfURL: %@", url);

    if (![url isFileURL]) {
        [self release];
        return nil;
    }

    return [self initWithContentsOfFile: [url path]];
}

- initWithNibNamed: (NSString *) name bundle: (NSBundle *) bundle {

    NIBDEBUG(@"initWithNibNamed: %@ bundle: %@", name, bundle);

    if (bundle == nil)
        bundle = [NSBundle mainBundle];

    NSString *path = [bundle pathForResource: name ofType: @"nib"];

    if (path == nil) {
        NSLog(@"%s: unable to init nib with name '%@'", __PRETTY_FUNCTION__,
              name);
        [self release];
        return nil;
    }

    return [self initWithContentsOfFile: path];
}

- (void) dealloc {
    [_data release];
    [_allObjects release];
    [super dealloc];
}

- unarchiver: (NSKeyedUnarchiver *) unarchiver didDecodeObject: object {
    if (object != nil)
        [_allObjects addObject: object];
    return object;
}

- (void) _replaceDecodedObject: object withObject: replacement {
    if (object != nil && replacement != nil) {
        NSUInteger index = [_allObjects indexOfObjectIdenticalTo: object];
        if (index != NSNotFound)
            [_allObjects replaceObjectAtIndex: index withObject: replacement];
    }
}

- (void) unarchiver: (NSKeyedUnarchiver *) unarchiver
        willReplaceObject: object
               withObject: replacement
{
    [self _replaceDecodedObject: object withObject: replacement];
}

- (NSDictionary *) externalNameTable {
    return _nameTable;
}

- (BOOL) instantiateNibWithExternalNameTable: (NSDictionary *) nameTable {
    NIBDEBUG(@"instantiateNibWithExternalNameTable: %@", nameTable);

    _nameTable = [nameTable retain];
    @try {
        return [self _instantiateWithNameTable];
    } @finally {
        [_nameTable release];
        _nameTable = nil;
    }
}

- (BOOL) _instantiateWithNameTable {
    NSIBObjectData *objectData;
    @autoreleasepool {
        NSCoder *unarchiver;
        int i, count;
        NSMenu *menu;
        NSArray *topLevelObjects;

        BOOL isNibArchive = UIDataLooksLikeNibArchive(_data);

        if (isNibArchive) {
            // The compact binary format ibtool writes for current deployment targets.
            UINibDecoder *decoder = [[[UINibDecoder alloc] initForReadingWithData: _data] autorelease];
            unarchiver = decoder;
            [decoder setDelegate: (id) self];
            [decoder setClass: [NSTableCornerView class]
                 forClassName: @"_NSCornerView"];
            [decoder setClass: [NSNibHelpConnector class]
                 forClassName: @"NSIBHelpConnector"];

            // Like macOS, a nib that cannot be read fails to instantiate without raising.
            @try {
                objectData = [decoder decodeObjectForKey: @"IB.objectdata"];
            } @catch (NSException *exception) {
                objectData = nil;
            }
        } else if (_flags._isKeyed) {
            NSKeyedUnarchiver *keyed = nil;
            @try {
                keyed = [[[NSKeyedUnarchiver alloc] initForReadingWithData: _data] autorelease];
            } @catch (NSException *exception) {
                // Like the NIBArchive path: data that is not an archive (such as an empty file)
                // fails to instantiate without raising.
                return NO;
            }
            unarchiver = keyed;

            [keyed setDelegate: self];

            /*
            TO DO:
            - utf8 in the multinational panel
            - misaligned objects in boxes everywhere
            */

            [keyed setClass: [NSTableCornerView class]
               forClassName: @"_NSCornerView"];
            [keyed setClass: [NSNibHelpConnector class]
               forClassName: @"NSIBHelpConnector"];

            objectData = [keyed decodeObjectForKey: @"IB.objectdata"];
        } else {
            NSUnarchiver *unkeyed;
            unarchiver = unkeyed = [[[NSUnarchiver alloc]
                    initForReadingWithData: _data] autorelease];

            [unkeyed decodeClassName: @"_NSCornerView"
                         asClassName: @"NSTableCornerView"];
            [unkeyed decodeClassName: @"NSIBHelpConnector"
                         asClassName: @"NSNibHelpConnector"];

            objectData = [unkeyed decodeObject];
        }

        if (![objectData isKindOfClass: [NSIBObjectData class]])
            return NO;

        // NSArchiver data has no decoding delegate to collect the objects as they are decoded;
        // the objects of the object table stand in for them, with the owner taking the place
        // of its placeholder.
        NSArray *unkeyedObjects = nil;
        id formerOwner = nil;
        if (!isNibArchive && !_flags._isKeyed) {
            unkeyedObjects = [[objectData allObjects] retain];
            formerOwner = [[objectData rootObject] retain];
        }

        [objectData buildConnectionsWithNameTable: _nameTable];

        // A toolbar asks its delegate for its default items once the delegate's own outlets are
        // connected, before anything is awakened.
        for (id object in _allObjects)
            if ([object isKindOfClass: [NSToolbar class]])
                [(NSToolbar *) object _nibDidConnectObjects];

        if (unkeyedObjects != nil) {
            id owner = [objectData rootObject];
            for (id object in unkeyedObjects)
                [_allObjects addObject: (object == formerOwner && owner != nil) ? owner : object];
            // The owner is among the objects that are awakened even when the object table does
            // not list its placeholder.
            if (owner != nil && [_allObjects indexOfObjectIdenticalTo: owner] == NSNotFound)
                [_allObjects addObject: owner];
            [unkeyedObjects release];
            [formerOwner release];
        }
        if ((menu = [objectData mainMenu]) != nil) {
            // Rename the first item to have the application name.
            if ([menu numberOfItems] > 0) {
                NSMenuItem *firstItem = [menu itemAtIndex: 0];
                NSString *appName = [[NSBundle mainBundle]
                        objectForInfoDictionaryKey: (NSString *)
                                                            kCFBundleNameKey];
                [firstItem setTitle: appName];
            }
            [NSApp setMainMenu: menu];
        }

        topLevelObjects = [objectData topLevelObjects];
        // Objects the caller passed in stand for nib placeholders; like File's Owner they
        // aren't top-level objects of the nib.
        NSArray *externalObjects = [_nameTable allValues];
        NSMutableArray *nibTopLevelObjects = [NSMutableArray array];
        for (id object in topLevelObjects)
            if ([externalObjects indexOfObjectIdenticalTo: object] == NSNotFound)
                [nibTopLevelObjects addObject: object];
        topLevelObjects = nibTopLevelObjects;

        // Top-level objects are always retained - this echoes observed Cocoa
        // behaviour
        [topLevelObjects makeObjectsPerformSelector: @selector(retain)];

        // if external table contains a mutable array for key
        // NSNibTopLevelObjects, then this array also retains all top-level
        // objects,
        if ([_nameTable objectForKey: NSNibTopLevelObjects]) {
            [[_nameTable objectForKey: NSNibTopLevelObjects]
                    setArray: topLevelObjects];
        }

        // We do not need to add the objects from nameTable to allObjects as
        // they get put into the uid->object table already Do we send
        // awakeFromNib to objects in the nameTable *not* present in the nib ?

        count = [_allObjects count];

        for (i = 0; i < count; i++) {
            id object = [_allObjects objectAtIndex: i];

            if ([object respondsToSelector: @selector(awakeFromNib)])
                [object awakeFromNib];
        }

        for (i = 0; i < count; i++) {
            id object = [_allObjects objectAtIndex: i];

            if ([object respondsToSelector: @selector(postAwakeFromNib)])
                [object performSelector: @selector(postAwakeFromNib)];
        }

        [[objectData visibleWindows]
                makeObjectsPerformSelector: @selector(makeKeyAndOrderFront:)
                                withObject: nil];
    }

    return (objectData != nil);
}

- (BOOL) instantiateNibWithOwner: owner topLevelObjects: (NSArray **) objects {

    NIBDEBUG(@"instantiateNibWithOwner: %@ topLevelObjects: ", owner);

    NSMutableArray *topLevelObjects = [[NSMutableArray alloc] init];
    // The owner goes last so a nil owner doesn't drop the array from the table.
    NSDictionary *nameTable = [NSDictionary
            dictionaryWithObjectsAndKeys: topLevelObjects, NSNibTopLevelObjects,
                                          owner, NSNibOwner, nil];
    BOOL result = [self instantiateNibWithExternalNameTable: nameTable];

    if (objects != NULL && result)
        *objects = [NSArray arrayWithArray: topLevelObjects];
    [topLevelObjects release];

    return result;
}

- (BOOL) instantiateWithOwner: (id) owner topLevelObjects: (NSArray **) objects {
    NSArray *topLevelObjects = nil;
    if (![self instantiateNibWithOwner: owner topLevelObjects: &topLevelObjects])
        return NO;

    // Unlike instantiateNibWithOwner:, the caller doesn't own the top-level objects.
    [topLevelObjects makeObjectsPerformSelector: @selector(autorelease)];
    if (objects != NULL)
        *objects = topLevelObjects;
    return YES;
}

@end
