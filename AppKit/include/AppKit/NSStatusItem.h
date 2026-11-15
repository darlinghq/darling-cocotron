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

#import <CoreFoundation/CFBase.h>
#import <Foundation/Foundation.h>
#import <AppKit/NSButton.h>
#ifdef WIN32
#import <windows.h>
#endif

typedef NS_OPTIONS(NSUInteger, NSStatusItemBehavior) {
    NSStatusItemBehaviorRemovalAllowed = (1 << 1),
    NSStatusItemBehaviorTerminationOnRemoval = (1 << 2),
};

@class NSStatusBar, NSImage, NSAttributedString, NSMenu, NSView, NSWindow, NSStatusBarButton;

@interface NSStatusBarButton : NSButton {
    BOOL _appearsDisabled;
}
@property(nonatomic) BOOL appearsDisabled;
@end

@interface NSStatusItem : NSObject {
    SEL _doubleAction;
    // View-Based Item Vars
    NSView *_view;
    // Modern status item vars
    NSStatusItemBehavior _behavior;
    NSStatusBarButton *_button;
    NSString *_autosaveName;
    NSString *_defaultAutosaveName;
    BOOL _visible;
    // Other Vars
    BOOL _highlightMode;
    CGFloat _length;
    NSMenu *_menu;
    NSInteger _actionMask;
#ifdef WIN32
    int _trayIconID;
    HICON _trayIcon;
    HMENU _win32Menu;
#endif
}
- (NSStatusBar *) statusBar;

@property(nonatomic) NSStatusItemBehavior behavior;

- (NSStatusBarButton *) button;

@property(nonatomic, copy) NSString *autosaveName;

@property(nonatomic, getter=isVisible) BOOL visible;

@property(nonatomic) SEL action;
@property(nonatomic) SEL doubleAction;
@property(nonatomic, assign) id target;

@property(nonatomic, retain) NSImage *image;
@property(nonatomic, retain) NSImage *alternateImage;

@property(nonatomic, copy) NSString *title;
- (void) setToolTip: (NSString *) toolTip;
@property(nonatomic, copy) NSAttributedString *attributedTitle;

@property(nonatomic, retain) NSView *view;

@property(nonatomic) BOOL highlightMode;

@property(nonatomic, getter=isEnabled) BOOL enabled;

@property(nonatomic) CGFloat length;

@property(nonatomic, retain) NSMenu *menu;

- (void) popUpStatusItemMenu: (NSMenu *) menu;
- (NSInteger) sendActionOn: (NSInteger) mask;

- (void) drawStatusBarBackgroundInRect: (NSRect) rect
                         withHighlight: (BOOL) highlight;

@end
