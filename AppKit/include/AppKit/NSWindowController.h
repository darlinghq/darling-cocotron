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

#import <AppKit/AppKitIvarLayout.h>
#import <AppKit/NSNib.h>
#import <AppKit/NSResponder.h>

@class NSWindow, NSDocument, NSStoryboard, NSViewController;

// Legacy ObjC ABI (i386): instance size must stay 0x28, Apple's; the ivars
// before the extras sit at Apple's offsets. Add new state to the extra
// struct, never as an ivar.
NS_ASSUME_NONNULL_BEGIN

@interface NSWindowController : NSResponder {
    NSWindow *_window;
    NSString *_nibName;
    NSDocument *_document;
    NSArray *_topLevelObjects;
    id _owner;
    NS_LEGACY_IVAR_PAD(_NSWindowControllerReserved1, 4)
    NSString *_windowFrameAutosaveName;
    NS_EXTRA_IVARS_BEGIN(NSWindowController)
        NSString *_nibPath;
        BOOL _shouldCloseDocument;
        BOOL _shouldCascadeWindows;
        NSStoryboard *_storyboard;
        BOOL _loadingWindowLifecycle;
        BOOL _loadingWindowNib;
    NS_EXTRA_IVARS_END(NSWindowController)
}

- (instancetype) initWithWindow: (nullable NSWindow *) window;
- (instancetype) initWithWindowNibName: (NSNibName) nibName;
- (instancetype) initWithWindowNibName: (NSNibName) nibName owner: (id) owner;
- (instancetype) initWithWindowNibPath: (NSString *) nibPath owner: (id) owner;

@property(nullable, readonly, strong) NSStoryboard *storyboard;

// Loads the window first if it isn't loaded and a nib name is set, as
// subclasses that build the window in -loadWindow rely on.
@property(nullable, nonatomic, retain) NSWindow *window;
@property (nullable, retain) NSViewController *contentViewController;

- (BOOL) isWindowLoaded;
- (void) loadWindow;
- (void) windowWillLoad;
- (void) windowDidLoad;

- (void) showWindow: (nullable id) sender;

- (void) setDocument: (null_unspecified NSDocument *) document;
- (nullable id) document;
- (void) setDocumentEdited: (BOOL) flag;

- (void) close;
@property(nonatomic) BOOL shouldCloseDocument;

- (id) owner;
@property (readonly, copy) NSNibName windowNibName;
- (nullable NSString *) windowNibPath;

@property(nonatomic) BOOL shouldCascadeWindows;

@property(null_unspecified, nonatomic, copy) NSString *windowFrameAutosaveName;

- (void) synchronizeWindowTitleWithDocumentName;
- (NSString *) windowTitleForDocumentDisplayName: (NSString *) displayName;

@end

NS_ASSUME_NONNULL_END
