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

#import "NSWindowTemplate.h"
#import <AppKit/NSMainMenuView.h>
#import <AppKit/NSScreen.h>
#import <AppKit/NSWindow-Private.h>
#import <Foundation/NSKeyedArchiver.h>
#import <Foundation/NSRaise.h>

@interface NSWindow (private)
+ (BOOL) hasMainMenuForStyleMask: (NSUInteger) styleMask;
@end

@implementation NSWindowTemplate

@synthesize identifier = _identifier;
@synthesize styleMask = _windowStyleMask;
@synthesize title = _windowTitle;
@synthesize collectionBehavior = _collectionBehavior;
@synthesize animationBehavior = _animationBehavior;
@synthesize frameAutosaveName = _windowAutosave;
@synthesize contentMinSize = _contentMinSize;
@synthesize contentMaxSize = _contentMaxSize;
@synthesize minFullScreenContentSize = _minFullScreenContentSize;
@synthesize maxFullScreenContentSize = _maxFullScreenContentSize;
@synthesize tabbingIdentifier = _tabbingIdentifier;
@synthesize tabbingMode = _tabbingMode;
@synthesize titlebarAppearsTransparent = _titlebarAppearsTransparent;
@synthesize titleVisibility = _titleVisibility;
@synthesize toolbar = _toolbar;
@synthesize minSize = _minSize;
@synthesize maxSize = _maxSize;
@synthesize className = _windowClass;

- (int) _NXReadWindowSizeLimits:(NSCoder *) coder sizeOne: (CGSize *) sizeOne sizeTwo: (CGSize *) sizeTwo {
    uint8_t byte;
    [coder decodeValuesOfObjCTypes:"c", &byte];

    if (sizeOne) {
        if ((byte & 0x1) == 0x0) {
            sizeOne->width = 0;
            sizeOne->height = 0;
        } else {
            *sizeOne = [coder decodeSize];
        }
    }

    if (sizeTwo) {
        if ((byte & 0x2) == 0x0) {
            sizeTwo->width = FLT_MAX;
            sizeTwo->height = FLT_MAX;
        } else {
            *sizeTwo = [coder decodeSize];
        }
    }

    return byte != 0x0 ? 0x1 : 0x0;

}

- (instancetype) init {
    self = [super init];

    if (self != nil) {
        _autorecalculatesContentBorderThicknessForMinXEdge = YES;
        _autorecalculatesContentBorderThicknessForMaxXEdge = YES;
        _autorecalculatesContentBorderThicknessForMinYEdge = YES;
        _autorecalculatesContentBorderThicknessForMaxYEdge = YES;
    }

    return self;
}

- (instancetype) initWithCoder: (NSCoder *) coder {
    if ([coder allowsKeyedCoding]) {
        NSKeyedUnarchiver *keyed = (NSKeyedUnarchiver *) coder;

        _maxSize = [keyed decodeSizeForKey: @"NSMaxSize"];
        _minSize = [keyed decodeSizeForKey: @"NSMinSize"];
        _contentMinSize = [keyed decodeSizeForKey: @"NSWindowContentMinSize"];
        _contentMaxSize = [keyed decodeSizeForKey: @"NSWindowContentMaxSize"];
        screenRect =
                [keyed decodeRectForKey: @"NSScreenRect"]; // screen created on
        _viewClass = [[keyed decodeObjectForKey: @"NSViewClass"] retain];
        _wtFlags = [keyed decodeIntForKey: @"NSWTFlags"];
        _windowBacking = [keyed decodeIntegerForKey: @"NSWindowBacking"];
        _windowClass = [[keyed decodeObjectForKey: @"NSWindowClass"] retain];
        windowRect = [keyed decodeRectForKey: @"NSWindowRect"];
        _windowStyleMask = [keyed decodeIntegerForKey: @"NSWindowStyleMask"];
        _windowTitle = [[keyed decodeObjectForKey: @"NSWindowTitle"] retain];
        windowView = [[keyed decodeObjectForKey: @"NSWindowView"] retain];
        _windowAutosave =
                [[keyed decodeObjectForKey: @"NSFrameAutosaveName"] retain];
        _collectionBehavior =
                [keyed decodeIntegerForKey: @"NSWindowCollectionBehavior"];
        _animationBehavior =
                [keyed decodeIntegerForKey: @"NSWindowAnimationBehavior"];
        _minFullScreenContentSize =
                [keyed decodeSizeForKey: @"NSMinFullScreenContentSize"];
        _maxFullScreenContentSize =
                [keyed decodeSizeForKey: @"NSMaxFullScreenContentSize"];
        _tabbingIdentifier =
                [[keyed decodeObjectForKey: @"NSWindowTabbingIdentifier"]
                        retain];
        _tabbingMode = [keyed decodeIntegerForKey: @"NSWindowTabbingMode"];
        _titleVisibility =
                [keyed decodeIntegerForKey: @"NSWindowTitleVisibility"];
        _contentBorderThicknessForMinXEdge =
                [keyed decodeDoubleForKey: @"NSContentBorderThicknessMinX"];
        _contentBorderThicknessForMaxXEdge =
                [keyed decodeDoubleForKey: @"NSContentBorderThicknessMaxX"];
        _contentBorderThicknessForMinYEdge =
                [keyed decodeDoubleForKey: @"NSContentBorderThicknessMinY"];
        _contentBorderThicknessForMaxYEdge =
                [keyed decodeDoubleForKey: @"NSContentBorderThicknessMaxY"];
        _titlebarAppearsTransparent =
                [keyed decodeBoolForKey: @"NSTitlebarAppearsTransparent"];
        _autorecalculatesContentBorderThicknessForMinXEdge =
                [keyed decodeBoolForKey:
                    @"NSAutorecalculatesContentBorderThicknessMinX"];
        _autorecalculatesContentBorderThicknessForMaxXEdge =
                [keyed decodeBoolForKey:
                    @"NSAutorecalculatesContentBorderThicknessMaxX"];
        _autorecalculatesContentBorderThicknessForMinYEdge =
                [keyed decodeBoolForKey:
                    @"NSAutorecalculatesContentBorderThicknessMinY"];
        _autorecalculatesContentBorderThicknessForMaxYEdge =
                [keyed decodeBoolForKey:
                    @"NSAutorecalculatesContentBorderThicknessMaxY"];
    } else {
        NSInteger version = [coder versionForClassName: @"NSWindowTemplate"];

        if (version > 40) {

            float windowRectX, windowRectY, windowRectWidth, windowRectHeight;
            uint8 isEqualToDefaultScreenRect;   // 0x1 or 0x0 if screen rect is equal to _NXDefaultScreenRecet

            [coder decodeValuesOfObjCTypes:"iiffffi@@@@@c", &_windowStyleMask, &_windowBacking, &windowRectX, &windowRectY, &windowRectWidth, &windowRectHeight, &_wtFlags, &_windowTitle, &_windowClass, &_viewClass, &windowView, &_extension, &isEqualToDefaultScreenRect];


            windowRect = CGRectMake(windowRectX, windowRectY, windowRectWidth, windowRectHeight);
            screenRect = [coder decodeRect];

            [self _NXReadWindowSizeLimits: coder sizeOne: &_minSize sizeTwo: nil];

            if (version >= 43) {
                _windowAutosave = [[coder decodeObject] retain];

                [self _NXReadWindowSizeLimits: coder sizeOne: nil sizeTwo: &_maxSize];
            }
        } else {
            [NSException raise: NSInvalidArgumentException
                    format: @"%@ can not initWithCoder:%@", [self class],
                            [coder class]];
        }
    }

    // Apple's AppKit can have maxSize as 0,0 when initWithCoder finishes,
    // but this causes problems with our implemenationm, so we set it to biggest possible
    if (CGSizeEqualToSize(_maxSize, CGSizeZero)) {
        _maxSize.width = FLT_MAX;
        _maxSize.height = FLT_MAX;
    }

    if ([NSScreen mainScreen])
        windowRect.origin.y -= screenRect.size.height -
                                [[NSScreen mainScreen] frame].size.height;
    if ([NSClassFromString(_windowClass)
                hasMainMenuForStyleMask: _windowStyleMask])
        windowRect.origin.y -= [NSMainMenuView
                menuHeight]; // compensation for the additional menu bar

    return self;
}

- (void) dealloc {
    [_viewClass release];
    [_windowClass release];
    [_windowTitle release];
    [windowView release];
    [_windowAutosave release];
    [_identifier release];
    [_tabbingIdentifier release];
    [_toolbar release];
    [super dealloc];
}

- (void) encodeWithCoder: (NSCoder *) coder {
    if (coder.allowsKeyedCoding) {
        [coder encodeSize: _maxSize forKey: @"NSMaxSize"];
        [coder encodeSize: _minSize  forKey: @"NSMinSize"];
        [coder encodeSize: _contentMinSize forKey: @"NSWindowContentMinSize"];
        [coder encodeSize: _contentMaxSize forKey: @"NSWindowContentMaxSize"];
        [coder encodeRect: screenRect forKey: @"NSScreenRect"];
        [coder encodeObject: _viewClass forKey: @"NSViewClass"];
        [coder encodeInt: _wtFlags forKey: @"NSWTFlags"];
        [coder encodeInteger: _windowBacking forKey: @"NSWindowBacking"];
        [coder encodeObject: _windowClass forKey: @"NSWindowClass"];
        [coder encodeRect: windowRect forKey: @"NSWindowRect"];
        [coder encodeInteger: _windowStyleMask forKey: @"NSWindowStyleMask"];
        [coder encodeObject: _windowTitle forKey: @"NSWindowTitle"];
        [coder encodeObject: windowView forKey: @"NSWindowView"];
        [coder encodeObject: _windowAutosave forKey: @"NSFrameAutosaveName"];
        [coder encodeInteger: _collectionBehavior
                      forKey: @"NSWindowCollectionBehavior"];
        [coder encodeInteger: _animationBehavior
                      forKey: @"NSWindowAnimationBehavior"];
        [coder encodeSize: _minFullScreenContentSize
                   forKey: @"NSMinFullScreenContentSize"];
        [coder encodeSize: _maxFullScreenContentSize
                   forKey: @"NSMaxFullScreenContentSize"];
        [coder encodeObject: _tabbingIdentifier
                     forKey: @"NSWindowTabbingIdentifier"];
        [coder encodeInteger: _tabbingMode forKey: @"NSWindowTabbingMode"];
        [coder encodeInteger: _titleVisibility
                      forKey: @"NSWindowTitleVisibility"];
        [coder encodeDouble: _contentBorderThicknessForMinXEdge
                     forKey: @"NSContentBorderThicknessMinX"];
        [coder encodeDouble: _contentBorderThicknessForMaxXEdge
                     forKey: @"NSContentBorderThicknessMaxX"];
        [coder encodeDouble: _contentBorderThicknessForMinYEdge
                     forKey: @"NSContentBorderThicknessMinY"];
        [coder encodeDouble: _contentBorderThicknessForMaxYEdge
                     forKey: @"NSContentBorderThicknessMaxY"];
        [coder encodeBool: _titlebarAppearsTransparent
                   forKey: @"NSTitlebarAppearsTransparent"];
        [coder encodeBool: _autorecalculatesContentBorderThicknessForMinXEdge
                   forKey: @"NSAutorecalculatesContentBorderThicknessMinX"];
        [coder encodeBool: _autorecalculatesContentBorderThicknessForMaxXEdge
                   forKey: @"NSAutorecalculatesContentBorderThicknessMaxX"];
        [coder encodeBool: _autorecalculatesContentBorderThicknessForMinYEdge
                   forKey: @"NSAutorecalculatesContentBorderThicknessMinY"];
        [coder encodeBool: _autorecalculatesContentBorderThicknessForMaxYEdge
                   forKey: @"NSAutorecalculatesContentBorderThicknessMaxY"];
    } else {
        [NSException raise: NSInvalidArchiveOperationException
                    format: @"TODO: support unkeyed encoding in NSWindowTemplate"];
    }
}

- awakeAfterUsingCoder: (NSCoder *) coder {
    NSWindow *result;
    Class class;

    if ((class = NSClassFromString(_windowClass)) == Nil) {
        [NSException
                 raise: NSInvalidArgumentException
                format: @"Unable to locate NSWindow class %@, using NSWindow",
                        _windowClass];
        class = [NSWindow class];
    }
    result = [[class alloc] initWithContentRect: windowRect
                                      styleMask: _windowStyleMask
                                        backing: _windowBacking
                                          defer: self.isDeferred];
    [result setMinSize: _minSize];
    [result setMaxSize: _maxSize];
    [result setOneShot: self.isOneShot];
    [result setReleasedWhenClosed: self.releasedWhenClosed];
    [result setHidesOnDeactivate: self.hidesOnDeactivate];
    [result setTitle: _windowTitle];
    [result setIdentifier: _identifier];
    [result setToolbar: _toolbar];

    [result setContentView: windowView];
    [windowView setAutoresizesSubviews: YES];
    [windowView setAutoresizingMask: NSViewWidthSizable | NSViewHeightSizable];

    if ([_viewClass isKindOfClass: [NSToolbar class]]) {
        [result setToolbar: _viewClass];
    }

    if ([_windowAutosave length] > 0)
        [result _setFrameAutosaveNameNoIO: _windowAutosave];

    [self release];
    return result;
}

- (Class) windowClassForNibInstantiate {
    // this method requires that the window class is a subclass of NSWindow; otherwise, it returns nil.
    Class theClass = NSClassFromString(_windowClass);
    if ([theClass isSubclassOfClass: [NSWindow class]]) {
        return theClass;
    }
    return nil;
}

- (id) appearance {
    NSUnimplementedMethod();
    return nil;
}

- (BOOL) isOneShot {
    return (_wtFlags & NSWindowTemplateFlagOneShot) != 0;
}

- (void) setOneShot: (BOOL) oneShot {
    if (oneShot) {
        _wtFlags |= NSWindowTemplateFlagOneShot;
    } else {
        _wtFlags &= ~NSWindowTemplateFlagOneShot;
    }
}

- (BOOL) isDeferred {
    return (_wtFlags & NSWindowTemplateFlagDeferred) != 0;
}

- (void) setDeferred: (BOOL) deferred {
    if (deferred) {
        _wtFlags |= NSWindowTemplateFlagDeferred;
    } else {
        _wtFlags &= ~NSWindowTemplateFlagDeferred;
    }
}

- (BOOL) isReleasedWhenClosed {
    return (_wtFlags & NSWindowTemplateFlagNotReleasedWhenClosed) == 0;
}

- (void) setReleasedWhenClosed: (BOOL) releasedWhenClosed {
    if (releasedWhenClosed) {
        _wtFlags &= ~NSWindowTemplateFlagNotReleasedWhenClosed;
    } else {
        _wtFlags |= NSWindowTemplateFlagNotReleasedWhenClosed;
    }
}

- (BOOL) hidesOnDeactivate {
    return (_wtFlags & NSWindowTemplateFlagHidesOnDeactivate) != 0;
}

- (void) setHidesOnDeactivate: (BOOL) hidesOnDeactivate {
    if (hidesOnDeactivate) {
        _wtFlags |= NSWindowTemplateFlagHidesOnDeactivate;
    } else {
        _wtFlags &= ~NSWindowTemplateFlagHidesOnDeactivate;
    }
}

- (BOOL) allowsToolTipsWhenApplicationIsInactive {
    return (_wtFlags & NSWindowTemplateFlagAllowsToolTipsWhenApplicationIsInactive) != 0;
}

- (void) setAllowsToolTipsWhenApplicationIsInactive: (BOOL) allowsToolTipsWhenApplicationIsInactive {
    if (allowsToolTipsWhenApplicationIsInactive) {
        _wtFlags |= NSWindowTemplateFlagAllowsToolTipsWhenApplicationIsInactive;
    } else {
        _wtFlags &= ~NSWindowTemplateFlagAllowsToolTipsWhenApplicationIsInactive;
    }
}

- (BOOL) autorecalculatesKeyViewLoop {
    return (_wtFlags & NSWindowTemplateFlagAutorecalculatesKeyViewLoop) != 0;
}

- (void) setAutorecalculatesKeyViewLoop: (BOOL) autorecalculatesKeyViewLoop {
    if (autorecalculatesKeyViewLoop) {
        _wtFlags |= NSWindowTemplateFlagAutorecalculatesKeyViewLoop;
    } else {
        _wtFlags &= ~NSWindowTemplateFlagAutorecalculatesKeyViewLoop;
    }
}

- (BOOL) isRestorable {
    return (_wtFlags & NSWindowTemplateFlagRestorable) != 0;
}

- (void) setRestorable: (BOOL) restorable {
    if (restorable) {
        _wtFlags |= NSWindowTemplateFlagRestorable;
    } else {
        _wtFlags &= ~NSWindowTemplateFlagRestorable;
    }
}

- (BOOL) hasShadow {
    return (_wtFlags & NSWindowTemplateFlagNoShadow) == 0;
}

- (void) setHasShadow: (BOOL) hasShadow {
    if (hasShadow) {
        _wtFlags &= ~NSWindowTemplateFlagNoShadow;
    } else {
        _wtFlags |= NSWindowTemplateFlagNoShadow;
    }
}

- (uint32_t) autoPositionMask {
    return (_wtFlags & NSWindowTemplateFlagAutoPositionMask) >> NSWindowTemplateFlagAutoPositionShift;
}

- (void) setAutoPositionMask: (uint32_t) autoPositionMask {
    _wtFlags = (_wtFlags & ~NSWindowTemplateFlagAutoPositionMask) | ((autoPositionMask << NSWindowTemplateFlagAutoPositionShift) & NSWindowTemplateFlagAutoPositionMask);
}

- (BOOL) wantsToBeColor {
    return (_wtFlags & NSWindowTemplateFlagWantsToBeColor) != 0;
}

- (void) setWantsToBeColor: (BOOL) wantsToBeColor {
    if (wantsToBeColor) {
        _wtFlags |= NSWindowTemplateFlagWantsToBeColor;
    } else {
        _wtFlags &= ~NSWindowTemplateFlagWantsToBeColor;
    }
}

- (BOOL) autorecalculatesContentBorderThicknessForEdge: (NSRectEdge) edge {
    if (edge == NSRectEdgeMinX) {
        return _autorecalculatesContentBorderThicknessForMinXEdge;
    } else if (edge == NSRectEdgeMaxX) {
        return _autorecalculatesContentBorderThicknessForMaxXEdge;
    } else if (edge == NSRectEdgeMinY) {
        return _autorecalculatesContentBorderThicknessForMinYEdge;
    } else if (edge == NSRectEdgeMaxY) {
        return _autorecalculatesContentBorderThicknessForMaxYEdge;
    } else {
        return NO;
    }
}

- (void) setAutorecalculatesContentBorderThickness: (BOOL) autorecalculatesContentBorderThickness
                                           forEdge: (NSRectEdge) edge
{
    if (edge == NSRectEdgeMinX) {
        _autorecalculatesContentBorderThicknessForMinXEdge = autorecalculatesContentBorderThickness;
    } else if (edge == NSRectEdgeMaxX) {
        _autorecalculatesContentBorderThicknessForMaxXEdge = autorecalculatesContentBorderThickness;
    } else if (edge == NSRectEdgeMinY) {
        _autorecalculatesContentBorderThicknessForMinYEdge = autorecalculatesContentBorderThickness;
    } else if (edge == NSRectEdgeMaxY) {
        _autorecalculatesContentBorderThicknessForMaxYEdge = autorecalculatesContentBorderThickness;
    }
}

- (CGFloat) contentBorderThicknessForEdge: (NSRectEdge) edge {
    if (edge == NSRectEdgeMinX) {
        return _contentBorderThicknessForMinXEdge;
    } else if (edge == NSRectEdgeMaxX) {
        return _contentBorderThicknessForMaxXEdge;
    } else if (edge == NSRectEdgeMinY) {
        return _contentBorderThicknessForMinYEdge;
    } else if (edge == NSRectEdgeMaxY) {
        return _contentBorderThicknessForMaxYEdge;
    } else {
        return 0;
    }
}

- (void) setContentBorderThickness: (CGFloat) contentBorderThickness
                           forEdge: (NSRectEdge) edge
{
    if (edge == NSRectEdgeMinX) {
        _contentBorderThicknessForMinXEdge = contentBorderThickness;
    } else if (edge == NSRectEdgeMaxX) {
        _contentBorderThicknessForMaxXEdge = contentBorderThickness;
    } else if (edge == NSRectEdgeMinY) {
        _contentBorderThicknessForMinYEdge = contentBorderThickness;
    } else if (edge == NSRectEdgeMaxY) {
        _contentBorderThicknessForMaxYEdge = contentBorderThickness;
    }
}

@end
