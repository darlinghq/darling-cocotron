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

// The storyboard whose nib is being instantiated on this thread. Kept in the
// thread dictionary: thread-local variables are not available to 32-bit
// Mach-O objects.
static NSString *const NSStoryboardInstantiatingKey = @"_NSStoryboardInstantiating";

static NSStoryboard *currentInstantiatingStoryboard(void) {
    return [[[NSThread currentThread] threadDictionary] objectForKey: NSStoryboardInstantiatingKey];
}

static void setCurrentInstantiatingStoryboard(NSStoryboard *storyboard) {
    NSMutableDictionary *dictionary = [[NSThread currentThread] threadDictionary];

    if (storyboard != nil)
        [dictionary setObject: storyboard forKey: NSStoryboardInstantiatingKey];
    else
        [dictionary removeObjectForKey: NSStoryboardInstantiatingKey];
}

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
    return currentInstantiatingStoryboard();
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
    NSMutableArray *topLevelObjects = [NSMutableArray array];
    NSMutableDictionary *nameTable = [NSMutableDictionary dictionaryWithObjectsAndKeys:
            topLevelObjects, NSNibTopLevelObjects, self, NSStoryboardSceneExternalObjectKey, nil];
    NSStoryboard *outer = [[currentInstantiatingStoryboard() retain] autorelease];
    BOOL loaded;

    if (owner != nil)
        [nameTable setObject: owner forKey: NSNibOwner];
    setCurrentInstantiatingStoryboard(self);
    @try {
        loaded = [nib instantiateNibWithExternalNameTable: nameTable];
    } @finally {
        setCurrentInstantiatingStoryboard(outer);
    }
    if (!loaded)
        [NSException raise: NSInternalInconsistencyException
                    format: @"Unable to load nib %@ of storyboard %@", name, _path];
    // The nib load retains top-level objects for its caller; this array keeps them instead.
    [topLevelObjects makeObjectsPerformSelector: @selector(autorelease)];
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

    // A scene nib may hold several controllers. The scene's own one is the object
    // its File's Owner reaches through the sceneController outlet; the rest are
    // reachable only through connections of that controller.
    NSStoryboardSceneOwner *owner = [[[NSStoryboardSceneOwner alloc] init] autorelease];
    id controller = nil;
    for (id object in [self _instantiateNibNamed: nibName owner: owner]) {
        // Scenes without the outlet: take the first window controller, else the
        // first view controller.
        if ([object isKindOfClass: [NSWindowController class]]) {
            if (controller == nil || ![controller isKindOfClass: [NSWindowController class]])
                controller = object;
        } else if (controller == nil && [object isKindOfClass: [NSViewController class]])
            controller = object;
    }
    if (owner->_sceneController != nil)
        controller = owner->_sceneController;
    if (controller == nil)
        [NSException raise: NSInternalInconsistencyException
                    format: @"Storyboard scene %@ has no top-level controller", nibName];
    return controller;
}

@end

// File's Owner of a scene nib. Compiled scenes connect its sceneController outlet to the controller
// the scene stands for.
@implementation NSStoryboardSceneOwner

- (void) setSceneController: (id) controller {
    controller = [controller retain];
    [_sceneController release];
    _sceneController = controller;
}

- (void) dealloc {
    [_sceneController release];
    [super dealloc];
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
