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

#import <Foundation/NSGeometry.h>
#import <Foundation/NSObject.h>
#import <AppKit/NSUserInterfaceItemIdentification.h>
#import <AppKit/NSWindow.h>

@class NSView;

typedef NS_OPTIONS(uint32_t, NSWindowTemplateFlags) {
    NSWindowTemplateFlagRestorable = 1u << 9,
    NSWindowTemplateFlagDoesNotShowToolbarButton = 1u << 10,
    NSWindowTemplateFlagAutorecalculatesKeyViewLoop = 1u << 11,
    NSWindowTemplateFlagNoShadow = 1u << 12,
    NSWindowTemplateFlagAllowsToolTipsWhenApplicationIsInactive = 1u << 13,
    NSWindowTemplateFlagAutoPositionShift = 19,
    NSWindowTemplateFlagAutoPositionMask = 0x3fu << NSWindowTemplateFlagAutoPositionShift,
    NSWindowTemplateFlagHasDynamicDepthLimit = 1u << 25,
    NSWindowTemplateFlagWantsToBeColor = 1u << 26,
    NSWindowTemplateFlagOneShot = 1u << 28,
    NSWindowTemplateFlagDeferred = 1u << 29,
    NSWindowTemplateFlagNotReleasedWhenClosed = 1u << 30,
    NSWindowTemplateFlagHidesOnDeactivate = 1u << 31,
};

@interface NSWindowTemplate : NSObject <NSUserInterfaceItemIdentification, NSCoding> {
    // the ivars without a `_` prefix are like that because Xcode
    // requires them to be named like that.

    // TODO: we might also need to put these ivars in the same order as the real AppKit does.
    //       this is only a problem for platforms with fragile base classes (e.g. i386), though.

    NSSize _maxSize;
    NSSize _minSize;
    NSSize _contentMinSize;
    NSSize _contentMaxSize;
    NSRect screenRect;
    id _viewClass;
    id _extension;
    NSWindowTemplateFlags _wtFlags;
    NSInteger _windowBacking;
    NSString *_windowClass;
    NSRect windowRect;
    NSWindowStyleMask _windowStyleMask;
    NSString *_windowTitle;
    NSView *windowView;
    NSString *_windowAutosave;
    NSUserInterfaceItemIdentifier _identifier;
    NSWindowCollectionBehavior _collectionBehavior;
    NSUInteger _animationBehavior;
    NSSize _minFullScreenContentSize;
    NSSize _maxFullScreenContentSize;
    NSString *_tabbingIdentifier;
    NSUInteger _tabbingMode;
    NSUInteger _titleVisibility;
    NSToolbar *_toolbar;
    CGFloat _contentBorderThicknessForMinXEdge;
    CGFloat _contentBorderThicknessForMaxXEdge;
    CGFloat _contentBorderThicknessForMinYEdge;
    CGFloat _contentBorderThicknessForMaxYEdge;

    BOOL _titlebarAppearsTransparent;
    BOOL _autorecalculatesContentBorderThicknessForMinXEdge;
    BOOL _autorecalculatesContentBorderThicknessForMaxXEdge;
    BOOL _autorecalculatesContentBorderThicknessForMinYEdge;
    BOOL _autorecalculatesContentBorderThicknessForMaxYEdge;
}

@property NSWindowStyleMask styleMask;
@property(copy) NSString *title;
@property BOOL allowsToolTipsWhenApplicationIsInactive;
@property BOOL autorecalculatesKeyViewLoop;
@property(getter=isDeferred) BOOL deferred;
@property BOOL hasShadow;
@property BOOL hidesOnDeactivate;
@property(getter=isReleasedWhenClosed) BOOL releasedWhenClosed;
@property(getter=isOneShot) BOOL oneShot;
@property NSWindowCollectionBehavior collectionBehavior;
@property NSUInteger animationBehavior;
@property(copy) NSString *frameAutosaveName;
@property NSSize contentMinSize;
@property NSSize contentMaxSize;
@property NSSize minFullScreenContentSize;
@property NSSize maxFullScreenContentSize;
@property(copy) NSString *tabbingIdentifier;
@property NSUInteger tabbingMode;
@property BOOL titlebarAppearsTransparent;
@property NSUInteger titleVisibility;
@property(strong) NSToolbar *toolbar;
@property(getter=isRestorable) BOOL restorable;
@property uint32_t autoPositionMask;
@property BOOL wantsToBeColor;
@property NSSize minSize;
@property NSSize maxSize;
@property(copy) NSString *className;

- (BOOL) autorecalculatesContentBorderThicknessForEdge: (NSRectEdge) edge;
- (void) setAutorecalculatesContentBorderThickness: (BOOL) autorecalculatesContentBorderThickness
                                           forEdge: (NSRectEdge) edge;

- (CGFloat) contentBorderThicknessForEdge: (NSRectEdge) edge;
- (void) setContentBorderThickness: (CGFloat) contentBorderThickness
                           forEdge: (NSRectEdge) edge;

@end
