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
#import <AppKit/NSPanel.h>
#import <Foundation/NSURL.h>

@class NSView, NSOutlineView, NSTextField;

enum {
    NSFileHandlingPanelCancelButton = NSCancelButton,
    NSFileHandlingPanelOKButton = NSOKButton,
};

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
}

@property (copy) NSString *nameFieldStringValue;
@property BOOL showsHiddenFiles;
// Stored only: the panel has no hide-extension checkbox.
@property BOOL canSelectHiddenExtension;
@property (getter=isExtensionHidden) BOOL extensionHidden;

+ (NSSavePanel *) savePanel;

- (NSURL *) URL;
- (NSString *) filename;

- (void) beginWithCompletionHandler: (void (^)(NSModalResponse result)) handler;
- (void) beginSheetModalForWindow: (NSWindow *) window
                completionHandler: (void (^)(NSModalResponse result)) handler;

- (NSModalResponse) runModalForDirectory: (NSString *) directory
                                    file: (NSString *) file;
- (NSModalResponse) runModal;

@property(nonatomic, copy) NSString *directory;
@property(nonatomic) BOOL treatsFilePackagesAsDirectories;
@property(nonatomic, retain) NSView *accessoryView;

- (void) setTitle: (NSString *) title;


- (void) setRequiredFileType: (NSString *) type;

@property(nonatomic, copy) NSURL *directoryURL;

@property(nonatomic, copy) NSArray *allowedFileTypes;

- (void) setCanCreateDirectories: (BOOL) value;
// UTType objects (macOS 11). Setting them also sets allowedFileTypes to their
// preferred filename extensions, or nil (any file) when none has one.
@property(nonatomic, copy) NSArray *allowedContentTypes;
- (void) setAllowsOtherFileTypes: (BOOL) value;

@property(nonatomic, copy) NSString *message;

@property(nonatomic, copy) NSString *prompt;

@property(nonatomic, copy) NSString *nameFieldLabel;
@property(nonatomic) BOOL showsTagField;
@property(nonatomic, copy) NSArray *tagNames;
- (void) setExtensionHidden: (BOOL) flag;
- (BOOL) isExtensionHidden;
- (void) setCanSelectHiddenExtension: (BOOL) flag;
- (BOOL) canSelectHiddenExtension;

- (void) cancelOperation: (id) sender;
- (void) beginWithCompletionHandler: (void (^)(NSModalResponse result)) handler;

- (void) beginSheetForDirectory: (NSString *) path
                           file: (NSString *) name
                 modalForWindow: (NSWindow *) docWindow
                  modalDelegate: (id) modalDelegate
                 didEndSelector: (SEL) didEndSelector
                    contextInfo: (void *) contextInfo;

- (IBAction) _selectFile: (id) sender;
- (IBAction) _cancel: (id) sender;
@end

@protocol NSOpenSavePanelDelegate <NSObject>

// TODO

@end
