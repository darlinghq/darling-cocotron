/* Copyright (c) 2006-2007 Christopher J. W. Lloyd <cjwl@objc.net>

   Permission is hereby granted, free of charge, to any person obtaining a copy
   of this software and associated documentation files (the "Software"), to
   deal in the Software without restriction, including without limitation the
   rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
   sell copies of the Software, and to permit persons to whom the Software is
   furnished to do so, subject to the following conditions:

   The above copyright notice and this permission notice shall be included in
   all copies or substantial portions of the Software.

   THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
   IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
   FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
   AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
   LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
   FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS
   IN THE SOFTWARE. */
#import <AppKit/NSNib.h>
#import <AppKit/NSNibLoading.h>
#import <AppKit/NSRaise.h>
#import <Foundation/NSAutoreleasePool.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSPathUtilities.h>
#import <Foundation/NSPlatform.h>
#import <Foundation/NSString.h>
#import <dispatch/dispatch.h>

static NSMutableArray<NSBundle *> *_nibLoadingBundles(void) {
    static NSMutableArray<NSBundle *> *inst;
    static dispatch_once_t once;

    dispatch_once(&once, ^{
      inst = [[NSMutableArray alloc] init];
    });

    return inst;
}

static NSMutableArray<NSString *> *_nibPaths(void) {
    static NSMutableArray<NSString *> *inst;
    static dispatch_once_t once;

    dispatch_once(&once, ^{
      inst = [[NSMutableArray alloc] init];
    });

    return inst;
}

@implementation NSObject (NSNibLoading)

- (void) awakeFromNib {
    // do nothing
}

@end
@implementation NSBundle (NSNibLoading)

+ (BOOL) loadNibFile: (NSString *) path
    externalNameTable: (NSDictionary *) nameTable
             withZone: (NSZone *) zone {
    NIBDEBUG(@"+ loadNibFile: '%@' externalNameTable: withZone:", path);

    [NSBundle pushNibPath: path];

    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    NSNib *nib = [[[NSNib allocWithZone: zone] initWithContentsOfFile: path]
        autorelease];

    BOOL result = [nib instantiateNibWithExternalNameTable: nameTable];
    [pool release];

    [NSBundle popNibPath];

    return result;
}

+ (BOOL) loadNibNamed: (NSString *) name owner: owner {
    NIBDEBUG(@"+ loadNibNamed: '%@'", name);

    NSDictionary *nameTable = [NSDictionary dictionaryWithObject: owner
                                                          forKey: NSNibOwner];
    NSBundle *bundle = [NSBundle bundleForClass: [owner class]];
    return [bundle loadNibFile: name
             externalNameTable: nameTable
                      withZone: NSDefaultMallocZone()];
}

- (BOOL) loadNibFile: (NSString *) fileName
    externalNameTable: (NSDictionary *) nameTable
             withZone: (NSZone *) zone {
    NSAutoreleasePool *pool = [NSAutoreleasePool new];

    NIBDEBUG(@"- loadNibNamed: '%@' externalNameTable: withZone:", fileName);

    NSString *path = nil;
    // Build a full path if it's not yet
    if ([[fileName stringByDeletingLastPathComponent] length] == 0) {
        NSString *name = [[fileName copy] autorelease];
        name = [name stringByDeletingPathExtension];
        NSBundle *bundle = self;
        NSString *platformName = [name
            stringByAppendingFormat: @"-%@", NSPlatformResourceNameSuffix];

        path = [bundle pathForResource: platformName ofType: @"nib"];
        if (path == nil) {
            path = [[NSBundle mainBundle] pathForResource: platformName
                                                   ofType: @"nib"];
        }

        if (path == nil) {
            path = [bundle pathForResource: name ofType: @"nib"];
        }

        if (path == nil) {
            path = [[NSBundle mainBundle] pathForResource: name ofType: @"nib"];
        }
    } else {
        NSLog(@"warning: full path passed when only nib file name should be "
              @"used");
        path = fileName;
    }

    [NSBundle pushNibPath: path];
    [NSBundle pushNibLoadingBundle: self];

    NSNib *nib = [[[NSNib allocWithZone: zone] initWithContentsOfFile: path]
        autorelease];

    BOOL result = [nib instantiateNibWithExternalNameTable: nameTable];
    [pool release];

    [NSBundle popNibPath];
    [NSBundle popNibLoadingBundle];

    return result;
}

- (BOOL) loadNibNamed: (NSString *) name
                owner: (id) owner
      topLevelObjects: (NSArray **) topLevelObjects {
    [NSBundle pushNibPath: [self pathForResource: name ofType: @"nib"]];
    [NSBundle pushNibLoadingBundle: self];

    NSNib *nib = [[NSNib alloc] initWithNibNamed: name bundle: self];
    BOOL res = [nib instantiateNibWithOwner: owner
                            topLevelObjects: topLevelObjects];
    [nib release];

    [NSBundle popNibPath];
    [NSBundle popNibLoadingBundle];

    return res;
}

@end

@implementation NSBundle (UINSBundleLocalizableStringAdditions)
+ (id) currentNibLoadingBundle {
    return [_nibLoadingBundles() lastObject];
}

+ (void) popNibLoadingBundle {
    [_nibLoadingBundles() removeLastObject];
}

+ (void) pushNibLoadingBundle: (id) bundle {
    [_nibLoadingBundles() addObject: bundle];
}

+ (id) currentStringsTableName {
    // TODO
    return nil;
}

+ (id) currentNibPath {
    return [_nibPaths() lastObject];
}

+ (void) popNibPath {
    [_nibPaths() removeLastObject];
}

+ (void) pushNibPath: (id) path {
    [_nibPaths() addObject: path];
}

+ (BOOL) _loadNibFile: (id) file
    externalNameTable: (id) tableName
              options: (id) options
             withZone: (struct _NSZone *) zone {
    // TODO: work with options
    return [NSBundle loadNibFile: file
               externalNameTable: tableName
                        withZone: zone];
}

- (BOOL) loadNibFile: (id) file
    externalNameTable: (id) tableName
              options: (id) options
             withZone: (struct _NSZone *) zone {
    // TODO: work with options
    return [self loadNibFile: file externalNameTable: tableName withZone: zone];
}
@end
