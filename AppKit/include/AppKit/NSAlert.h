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

#import <Foundation/NSObject.h>
#import <AppKit/AppKitIvarLayout.h>

@class NSButton, NSImage, NSArray, NSWindow, NSError, NSView, NSMutableArray;

// NSApplication.h imports this header, so the modal response type is declared here.
NS_ASSUME_NONNULL_BEGIN

typedef NSInteger NSModalResponse NS_TYPED_EXTENSIBLE_ENUM;

static const NSModalResponse NSModalResponseOK = 1;
static const NSModalResponse NSModalResponseCancel = 0;
static const NSModalResponse NSModalResponseStop = -1000;
static const NSModalResponse NSModalResponseAbort = -1001;
static const NSModalResponse NSModalResponseContinue = -1002;

typedef NS_ENUM(NSUInteger, NSAlertStyle) {
    NSAlertStyleWarning = 0,
    NSAlertStyleInformational = 1,
    NSAlertStyleCritical = 2,
};

// Names used before the modern spellings; plain constants, so Swift does not see them.
enum {
    NSWarningAlertStyle = NSAlertStyleWarning,
    NSInformationalAlertStyle = NSAlertStyleInformational,
    NSCriticalAlertStyle = NSAlertStyleCritical,
};

static const NSModalResponse NSAlertFirstButtonReturn = 1000;
static const NSModalResponse NSAlertSecondButtonReturn = 1001;
static const NSModalResponse NSAlertThirdButtonReturn = 1002;

@interface NSAlert : NSObject {
    id _delegate;
    NSAlertStyle _style;
    NSImage *_icon;
    NSString *_messageText;
    NSString *_informativeText;
    NSView *_accessoryView;
    BOOL _showsHelp;
    BOOL _showsSuppressionButton;
    NSString *_helpAnchor;
    NSMutableArray *_buttons;
    NSButton *_suppressionButton;
    NSWindow *_window;

    BOOL _needsLayout;
    id _sheetDelegate;
    SEL _sheetDidEnd;
    NS_LEGACY_IVAR_PAD(_NSAlertReserved, 60)
}

+ (NSAlert *) alertWithError: (NSError *) error;
+ (NSAlert *) alertWithMessageText: (nullable NSString *) messageText
                     defaultButton: (nullable NSString *) defaultTitle
                   alternateButton: (nullable NSString *) alternateTitle
                       otherButton: (nullable NSString *) otherTitle
         informativeTextWithFormat: (NSString *) format, ...;

- (null_unspecified id) delegate;
@property(nonatomic) NSAlertStyle alertStyle;
@property(null_resettable, nonatomic, retain) NSImage *icon;
@property(nonatomic, copy) NSString *messageText;
@property(nonatomic, copy) NSString *informativeText;
@property(nullable, nonatomic, retain) NSView *accessoryView;
@property(nonatomic) BOOL showsHelp;
@property(nonatomic) BOOL showsSuppressionButton;
@property(null_unspecified, nonatomic, copy) NSString *helpAnchor;
@property(nonatomic, readonly) NSArray<NSButton *> *buttons;
@property(nullable, nonatomic, readonly) NSButton *suppressionButton;
- (null_unspecified id) window;

- (void) setDelegate: (null_unspecified id) delegate;

- (NSButton *) addButtonWithTitle: (NSString *) title;

- (void) layout;

- (void) beginSheetModalForWindow: (NSWindow *) window
                    modalDelegate: (nullable id) delegate
                   didEndSelector: (nullable SEL) selector
                      contextInfo: (nullable void *) info;
- (void) beginSheetModalForWindow: (NSWindow *) sheetWindow
                completionHandler:
                        (void (^ _Nullable)(NSModalResponse returnCode)) handler;
- (NSModalResponse) runModal;

@end

@protocol NSAlertDelegate <NSObject>
- (BOOL) alertShowHelp: (NSAlert *) alert;
@end

NS_ASSUME_NONNULL_END
