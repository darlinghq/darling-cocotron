/* Copyright (c) 2006-2007 Christopher J. W. Lloyd <cjwl@objc.net>

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

#import <AppKit/NSNibLoading.h>
#import <AppKit/AppKitIvarLayout.h>
#import <AppKit/NSPanel.h>
#import <Foundation/NSURL.h>

@class NSView, NSOutlineView, NSTextField;

NS_ASSUME_NONNULL_BEGIN

enum {
    NSFileHandlingPanelCancelButton = NSCancelButton,
    NSFileHandlingPanelOKButton = NSOKButton,
};

@protocol NSOpenSavePanelDelegate <NSObject>
@optional
// Return NO to make the URL unselectable in the panel's list.
- (BOOL) panel: (id) sender shouldEnableURL: (NSURL *) url;
// Return NO (and set the error) to keep the panel up when the chosen URL is not acceptable.
- (BOOL) panel: (id) sender validateURL: (NSURL *) url error: (NSError **) outError;
// Sent when the folder shown by the panel changes, and once when it is shown.
- (void) panel: (id) sender didChangeToDirectoryURL: (nullable NSURL *) url;
- (void) panelSelectionDidChange: (nullable id) sender;
@end

// Legacy ObjC ABI (i386): instance size must stay 0xf8, Apple's; an
// application's subclass is laid out right after it. New state goes to a
// side structure, never to a larger ivar block.
@interface NSSavePanel : NSPanel {
    NSString *_dialogTitle;

    NSString *_nameFieldStringValue;
    NSString *_filename;
    NSString *_directory;
    NSString *_requiredFileType;
    NSArray *_allowedFileTypes;
    NSString *_message;
    NSString *_prompt;

    BOOL _showsHiddenFiles;

    BOOL _treatsFilePackagesAsDirectories;
    BOOL _canSelectHiddenExtension;
    BOOL _extensionHidden;
    NSView *_accessoryView;

    IBOutlet NSOutlineView *_outlineView;
    NSTextField *_nameField;
    BOOL _allowsOtherFileTypes;
    BOOL _runsAsSheet;
    NSUInteger _styleMaskBeforeSheet;
    id _sheetCompletionHandler;
    BOOL _runsModeless;
    id _modelessCompletionHandler;
    NSArray *_allowedContentTypes;
    BOOL _canCreateDirectories;
    NS_LEGACY_IVAR_PAD(_NSSavePanelReserved1, 43)
}

@property (copy) NSString *nameFieldStringValue;
@property BOOL showsHiddenFiles;
// Stored only: the panel has no hide-extension checkbox.
@property BOOL canSelectHiddenExtension;
@property (getter=isExtensionHidden) BOOL extensionHidden;

+ (NSSavePanel *) savePanel;

- (nullable NSURL *) URL;
- (NSString *) filename;

- (void) beginWithCompletionHandler: (void (^)(NSModalResponse result)) handler;
- (void) beginSheetModalForWindow: (NSWindow *) window
                completionHandler: (void (^)(NSModalResponse result)) handler;

- (NSModalResponse) runModalForDirectory: (nullable NSString *) directory
                                    file: (nullable NSString *) file;
- (NSModalResponse) runModal;

@property(null_resettable, nonatomic, copy) NSString *directory;
@property(nonatomic) BOOL treatsFilePackagesAsDirectories;
@property(nullable, nonatomic, retain) NSView *accessoryView;

- (void) setTitle: (nullable NSString *) title;


- (void) setRequiredFileType: (nullable NSString *) type;

@property(nullable, nonatomic, copy) NSURL *directoryURL;

@property(nullable, nonatomic, copy) NSArray<NSString *> *allowedFileTypes;

// Stored only: the panel has no button for making a new folder.
@property BOOL canCreateDirectories;
// UTType objects (macOS 11). Setting them also sets allowedFileTypes to their
// preferred filename extensions, or nil (any file) when none has one.
@property(nonatomic, copy) NSArray *allowedContentTypes;
- (void) setAllowsOtherFileTypes: (BOOL) value;

@property(null_resettable, nonatomic, copy) NSString *message;

@property(null_resettable, nonatomic, copy) NSString *prompt;

@property(null_resettable, nonatomic, copy) NSString *nameFieldLabel;
@property(nonatomic) BOOL showsTagField;
@property(nullable, nonatomic, copy) NSArray<NSString *> *tagNames;
- (void) setExtensionHidden: (BOOL) flag;
- (BOOL) isExtensionHidden;
- (void) setCanSelectHiddenExtension: (BOOL) flag;
- (BOOL) canSelectHiddenExtension;

- (void) cancelOperation: (nullable id) sender;
- (void) beginWithCompletionHandler: (void (^)(NSModalResponse result)) handler;

- (void) beginSheetForDirectory: (nullable NSString *) path
                           file: (nullable NSString *) name
                 modalForWindow: (nullable NSWindow *) docWindow
                  modalDelegate: (nullable id) modalDelegate
                 didEndSelector: (nullable SEL) didEndSelector
                    contextInfo: (nullable void *) contextInfo;

- (void) ok: (nullable id) sender;
- (void) cancel: (nullable id) sender;
// Like NSWindow's delegate, typed for the panel's own delegate protocol (the SDK's
// header redeclares it the same way).
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wincompatible-property-type"
@property(nullable, assign) id<NSOpenSavePanelDelegate> delegate;
#pragma clang diagnostic pop
- (IBAction) _selectFile: (null_unspecified id) sender;
- (IBAction) _cancel: (null_unspecified id) sender;
@end

NS_ASSUME_NONNULL_END
