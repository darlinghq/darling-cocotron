/*
 This file is part of Darling.

 Copyright (C) 2021 Lubos Dolezel

 Darling is free software: you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation, either version 3 of the License, or
 (at your option) any later version.

 Darling is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU General Public License for more details.

 You should have received a copy of the GNU General Public License
 along with Darling.  If not, see <http://www.gnu.org/licenses/>.
*/

#import <AppKit/NSApplication.h>
#import <AppKit/NSNib.h>
#import <AppKit/NSStoryboard-Private.h>
#import <AppKit/NSViewController.h>
#import <AppKit/NSWindowController.h>

// A compiled .storyboardc is a directory holding one nib per scene plus an Info.plist that names the
// initial scene and maps scene identifiers to nib names.
static NSString *const NSStoryboardInitialIdentifierKey = @"NSStoryboardDesignatedEntryPointIdentifier";
static NSString *const NSStoryboardNibNamesKey = @"NSViewControllerIdentifiersToNibNames";
static NSString *const NSStoryboardMainMenuKey = @"NSStoryboardMainMenu";

static __thread NSStoryboard *instantiatingStoryboard;

@interface NSStoryboardControllerPlaceholder : NSObject
@end

@implementation NSStoryboard

+ (NSStoryboard *) mainStoryboard {
    static NSStoryboard *mainStoryboard;
    static dispatch_once_t once;

    dispatch_once(&once, ^{
        NSString *name = [[NSBundle mainBundle] objectForInfoDictionaryKey: @"NSMainStoryboardFile"];
        if (name != nil)
            mainStoryboard = [[self storyboardWithName: name bundle: nil] retain];
    });
    return mainStoryboard;
}

+ (instancetype) storyboardWithName: (NSStoryboardName) name bundle: (NSBundle *) bundle {
    if (name == nil)
        [NSException raise: NSInvalidArgumentException
                    format: @"+[NSStoryboard storyboardWithName:bundle:] name is nil"];
    if (bundle == nil)
        bundle = [NSBundle mainBundle];

    NSString *path = [bundle pathForResource: name ofType: @"storyboardc"];
    NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:
            [path stringByAppendingPathComponent: @"Info.plist"]];
    if (info == nil)
        [NSException raise: NSInvalidArgumentException
                    format: @"Could not find a storyboard named '%@' in bundle %@", name, bundle];

    NSStoryboard *storyboard = [[[self alloc] init] autorelease];
    storyboard->_path = [path copy];
    storyboard->_info = [info retain];
    return storyboard;
}

+ (NSStoryboard *) _instantiatingStoryboard {
    return instantiatingStoryboard;
}

- (void) dealloc {
    [_path release];
    [_info release];
    [super dealloc];
}

- (NSString *) _pathForNibNamed: (NSString *) name {
    NSString *path = [[_path stringByAppendingPathComponent: name] stringByAppendingPathExtension: @"nib"];
    return [[NSFileManager defaultManager] fileExistsAtPath: path] ? path : nil;
}

- (NSArray *) _instantiateNibNamed: (NSString *) name owner: (id) owner {
    NSString *path = [self _pathForNibNamed: name];
    NSNib *nib = path == nil ? nil : [[[NSNib alloc] initWithContentsOfURL: [NSURL fileURLWithPath: path]] autorelease];
    NSArray *topLevelObjects = nil;
    NSStoryboard *outer = instantiatingStoryboard;
    BOOL loaded;

    instantiatingStoryboard = self;
    @try {
        loaded = [nib instantiateWithOwner: owner topLevelObjects: &topLevelObjects];
    } @finally {
        instantiatingStoryboard = outer;
    }
    if (!loaded)
        [NSException raise: NSInternalInconsistencyException
                    format: @"Unable to load nib %@ of storyboard %@", name, _path];
    return topLevelObjects;
}

// NSApplicationMain's counterpart of loading NSMainNibFile: the storyboard's main menu, then its
// initial window controller, shown and kept for the life of the app.
- (void) _instantiateAsMainStoryboard {
    NSString *menuName = [_info objectForKey: NSStoryboardMainMenuKey];
    if (menuName != nil)
        [self _instantiateNibNamed: menuName owner: NSApp];

    id controller = [self instantiateInitialController];
    if (controller == nil)
        return;
    if (![controller isKindOfClass: [NSWindowController class]])
        [NSException raise: NSInternalInconsistencyException
                    format: @"Initial controller %@ of main storyboard %@ is not a window controller", controller, _path];
    [controller retain];
    [controller showWindow: nil];
}

- (id) instantiateInitialController {
    NSString *identifier = [_info objectForKey: NSStoryboardInitialIdentifierKey];
    return identifier == nil ? nil : [self instantiateControllerWithIdentifier: identifier];
}

- (id) instantiateControllerWithIdentifier: (NSStoryboardSceneIdentifier) identifier {
    NSString *nibName = [[_info objectForKey: NSStoryboardNibNamesKey] objectForKey: identifier];
    if (nibName == nil)
        [NSException raise: NSInvalidArgumentException
                    format: @"Storyboard %@ doesn't contain a controller with identifier '%@'", _path, identifier];

    id controller = nil;
    for (id object in [self _instantiateNibNamed: nibName owner: nil]) {
        if (![object isKindOfClass: [NSViewController class]] &&
            ![object isKindOfClass: [NSWindowController class]])
            continue;
        if (controller != nil)
            [NSException raise: NSInternalInconsistencyException
                        format: @"Storyboard scene %@ has more than one top-level controller", nibName];
        controller = object;
    }
    if (controller == nil)
        [NSException raise: NSInternalInconsistencyException
                    format: @"Storyboard scene %@ has no top-level controller", nibName];
    return controller;
}

@end

@implementation NSStoryboardControllerPlaceholder

- (NSMethodSignature *)methodSignatureForSelector:(SEL)aSelector
{
    return [NSMethodSignature signatureWithObjCTypes: "v@:"];
}

- (void)forwardInvocation:(NSInvocation *)anInvocation
{
    NSLog(@"Stub called: %@ in %@", NSStringFromSelector([anInvocation selector]), [self class]);
}

@end
