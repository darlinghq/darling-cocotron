/* Copyright (c) 2006-2007 Christopher J. W. Lloyd <cjwl@objc.net>, 2008
Johannes Fortmann

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

#import <AppKit/NSApplication.h>
#import <AppKit/NSDisplay.h>
#import "DarlingPortalFileChooser.h"
#import <AppKit/NSRaise.h>
#import <AppKit/NSOutlineView.h>
#import <AppKit/NSSavePanel.h>
#import <AppKit/NSScrollView.h>
#import <AppKit/NSTextField.h>
#import <AppKit/NSView.h>
#import <AppKit/NSWorkspace.h>
#import "_NSFileSystemDataSource.h"
#import "_NSSavePanelNavigation.h"
#import <CoreServices/CoreServices.h>

// UTType; Darling's UTType may not implement it.
@interface NSObject (NSSavePanelContentTypes)
- (NSString *) preferredFilenameExtension;
@end

@implementation NSSavePanel

@synthesize showsHiddenFiles=_showsHiddenFiles;
@dynamic delegate; // the window's, typed here as an NSOpenSavePanelDelegate
@synthesize canSelectHiddenExtension = _canSelectHiddenExtension;
@synthesize extensionHidden = _extensionHidden;

// Like macOS, panels start in ~/Documents when there is one.
static NSString *defaultDirectory(void) {
    NSString *documents =
            [NSHomeDirectory() stringByAppendingPathComponent: @"Documents"];
    BOOL isDirectory = NO;
    if ([[NSFileManager defaultManager] fileExistsAtPath: documents
                                             isDirectory: &isDirectory] &&
        isDirectory)
        return documents;
    return NSHomeDirectory();
}

// QUIRK: a save panel is titled, not resizable, and shows its title; its prompt is "Save" and its message
// is empty, with no other style bits. Not documented. Evidence: black-box observation of -title, -prompt,
// -message, -styleMask and -titleVisibility of a new save panel on macOS 10.14.4 (tier 2).
// Test: appkit-panel-default-values.m
- (id) resetToDefaultValues {
    NSBundle *bundle = [NSBundle bundleForClass: [NSSavePanel class]];
    NSString *save = NSLocalizedStringFromTableInBundle(@"Save", nil, bundle, @"The title of the save panel");
    [self setStyleMask: NSWindowStyleMaskTitled];
    [self setTitleVisibility: NSWindowTitleVisible];
    [self setTitle: save];
    [self setPrompt: save];
    [self setMessage: @""];
    [self setNameFieldStringValue: @""];
    [self _setFilename: @""];
    [self setDirectory: defaultDirectory()];
    [self setRequiredFileType: @""];
    [self setAllowedFileTypes: nil];
    [self setAllowsOtherFileTypes: NO];
    _treatsFilePackagesAsDirectories = NO;
    [self setAccessoryView: nil];
    _showsHiddenFiles = false;
    // QUIRK: a new save panel allows making folders (canCreateDirectories is YES). Not documented.
    // Evidence: black-box observation on macOS 10.14.4 and 26.7.3 (tier 2).
    // Test: appkit-panel-create-directories.m
    _canCreateDirectories = YES;
    return self;
}

static NSSavePanel *_newPanel = nil;

+ (void) set_newPanel: (NSSavePanel *) newPanel {
    _newPanel = newPanel;
}

+ (NSSavePanel *) savePanel {
    if ([[NSDisplay currentDisplay] implementsCustomPanelForClass: self]) {
        _newPanel = [[self alloc]
                initWithContentRect: NSMakeRect(0, 0, 1, 1)
                          styleMask: NSTitledWindowMask | NSResizableWindowMask
                            backing: NSBackingStoreBuffered
                              defer: YES];
    } else {
        [NSBundle loadNibNamed: @"NSSavePanel" owner: self];
        [_newPanel _addNameField];
        [_newPanel _installNavigation];
    }
    // FIXME: release it?
    return [_newPanel resetToDefaultValues];
}

// The panel nib only has a file browser; saving also needs a field for the new file's name.
- (void) _addNameField {
    const CGFloat height = 22, spacing = 8, labelWidth = 64;
    NSScrollView *browser = [_outlineView enclosingScrollView];
    NSRect frame = [browser frame];
    frame.size.height -= height + spacing;
    [browser setFrame: frame];

    NSRect row = NSMakeRect(NSMinX(frame), NSMaxY(frame) + spacing, labelWidth,
                            height);
    NSTextField *label = [[[NSTextField alloc] initWithFrame: row] autorelease];
    [label setStringValue: NSLocalizedStringFromTableInBundle(
                                   @"Save As:", nil,
                                   [NSBundle bundleForClass: [NSSavePanel class]],
                                   @"The label of the save panel's name field")];
    [label setEditable: NO];
    [label setSelectable: NO];
    [label setBezeled: NO];
    [label setDrawsBackground: NO];
    [label setAutoresizingMask: NSViewMinYMargin];
    [[browser superview] addSubview: label];

    row.origin.x += labelWidth;
    row.size.width = NSWidth(frame) - labelWidth;
    _nameField = [[NSTextField alloc] initWithFrame: row];
    [_nameField setAutoresizingMask: NSViewWidthSizable | NSViewMinYMargin];
    [_nameField setTarget: self];
    [_nameField setAction: @selector(_selectFile:)];
    [[browser superview] addSubview: _nameField];
}

// The folder navigation controls of the nib-based panel; see _NSSavePanelNavigation.
- (void) _installNavigation {
    if (_outlineView == nil)
        return;
    _NSSavePanelNavigation *navigation =
            [[_NSSavePanelNavigation alloc] initWithPanel: self
                                              outlineView: _outlineView
                                                nameField: _nameField];
    [navigation installLayout];
    [navigation release]; // owned by the panel now
}

- (void) setShowsHiddenFiles: (BOOL) flag {
    _showsHiddenFiles = flag;
    [[_NSSavePanelNavigation navigationForPanel: self] reloadList];
}

- (BOOL) performKeyEquivalent: (NSEvent *) event {
    if ([[_NSSavePanelNavigation navigationForPanel: self]
                handleKeyEquivalent: event])
        return YES;
    return [super performKeyEquivalent: event];
}

- (BOOL) _packageAtURL: (NSURL *) url {
    return !_treatsFilePackagesAsDirectories &&
           [[NSWorkspace sharedWorkspace] isFilePackageAtPath: [url path]];
}

// The extension test of allowedFileTypes. A type that is not a plain
// extension (a UTI) is not interpreted here and lets the file through, so
// that no file is ever made unselectable by a type this panel cannot read.
- (BOOL) _fileURLMatchesAllowedTypes: (NSURL *) url {
    NSArray *types = [self allowedFileTypes];
    if ([types count] == 0)
        return YES;
    NSString *extension = [url pathExtension];
    for (NSString *type in types) {
        if ([type rangeOfString: @"."].location != NSNotFound)
            return YES;
        if ([type caseInsensitiveCompare: extension] == NSOrderedSame)
            return YES;
    }
    return NO;
}

// A save panel lists files, but only folders can be entered.
- (BOOL) _canSelectURL: (NSURL *) url isDirectory: (BOOL) isDirectory {
    return isDirectory && ![self _packageAtURL: url];
}

- (void) _navigationSelectionChanged {
    id delegate = [self delegate];
    if ([delegate respondsToSelector: @selector(panelSelectionDidChange:)])
        [delegate panelSelectionDidChange: self];
}

- (void) ok: (id) sender {
    [self _selectFile: sender];
}

- (void) cancel: (id) sender {
    [self _cancel: sender];
}

- init {
    [self release];
    return [[NSSavePanel savePanel] retain];
}

- (void) dealloc {
    // while the views are still alive: the navigation object is released after them
    [[_NSSavePanelNavigation navigationForPanel: self] detachFromViews];
    [_dialogTitle release];
    [_nameFieldStringValue release];
    [_filename release];
    [_directory release];
    [_requiredFileType release];
    [_allowedFileTypes release];
    [_allowedContentTypes release];
    [_accessoryView release];
    [_nameField release];
    [_sheetCompletionHandler release];
    [_modelessCompletionHandler release];
    [super dealloc];
}

- (void) _setFilename: (NSString *) filename {
    @synchronized(self) {
        if (filename != _filename) {
            [_filename release];
            _filename = [filename copy];
            if (_filename == nil) {
                _filename = @"";
            }
        }
    }
}

- (NSURL *) URL {
    NSString *fn = [self filename];
    return (fn != nil && [fn length] > 0) ? [NSURL fileURLWithPath: fn] : nil;
}

- (NSString *) filename {
    id ret = nil;
    @synchronized(self) {
        ret = [[_filename copy] autorelease];
    }
    return ret;
}

- (NSString *) nameFieldStringValue {
    if (_nameField != nil) {
        [_nameField validateEditing];
        return [_nameField stringValue];
    }
    return [[_nameFieldStringValue copy] autorelease];
}

- (void) setNameFieldStringValue: (NSString *) value {
    [_nameFieldStringValue release];
    _nameFieldStringValue = [value copy];

    if (_nameFieldStringValue == nil) {
        _nameFieldStringValue = @"";
    }
    [_nameField setStringValue: _nameFieldStringValue];
}

// The directory selected in the browser, the one holding a selected file, or the panel's directory.
- (NSString *) _selectedDirectory {
    NSInteger row = [_outlineView selectedRow];
    if (row < 0)
        return _directory;

    NSString *path = [[_outlineView itemAtRow: row] path];
    BOOL isDirectory = NO;
    if ([[NSFileManager defaultManager] fileExistsAtPath: path
                                             isDirectory: &isDirectory] &&
        isDirectory)
        return path;
    return [path stringByDeletingLastPathComponent];
}

// An allowed file type with a dot is a uniform type identifier, any other a
// filename extension.
static BOOL isTypeIdentifier(NSString *type) {
    return [type rangeOfString: @"."].location != NSNotFound;
}

// Whether a filename extension is one of an allowed type: the same extension,
// or for a type identifier, an extension whose type conforms to it.
static BOOL extensionIsOfAllowedType(NSString *extension, NSString *type) {
    if ([extension length] == 0)
        return NO;
    if (!isTypeIdentifier(type))
        return [type caseInsensitiveCompare: extension] == NSOrderedSame;

    CFStringRef identifier = UTTypeCreatePreferredIdentifierForTag(
            kUTTagClassFilenameExtension, (CFStringRef) extension, NULL);
    if (identifier == NULL)
        return NO;
    BOOL conforms = UTTypeConformsTo(identifier, (CFStringRef) type);
    CFRelease(identifier);
    return conforms;
}

// The extension a name gets for an allowed type: the type itself, or for a
// type identifier, its preferred filename extension (nil when it has none).
static NSString *extensionForAllowedType(NSString *type) {
    if (!isTypeIdentifier(type))
        return type;
    CFStringRef tag = UTTypeCopyPreferredTagWithClass(
            (CFStringRef) type, kUTTagClassFilenameExtension);
    return [(NSString *) tag autorelease];
}

// Like macOS, a name without an allowed extension gets the extension of the
// first allowed type that has one.
- (NSString *) _nameWithAllowedExtension: (NSString *) name {
    NSArray *types = [self allowedFileTypes];
    if ([types count] == 0 && [_requiredFileType length] > 0)
        types = [NSArray arrayWithObject: _requiredFileType];
    if ([types count] == 0)
        return name;

    NSString *extension = [name pathExtension];
    if (_allowsOtherFileTypes && [extension length] > 0)
        return name;
    for (NSString *type in types) {
        if (extensionIsOfAllowedType(extension, type))
            return name;
    }
    for (NSString *type in types) {
        NSString *allowed = extensionForAllowedType(type);
        if ([allowed length] > 0)
            return [name stringByAppendingPathExtension: allowed];
    }
    return name;
}

// The paths of the rows selected in the file browser, in row order.
- (NSArray *) _selectedPaths {
    NSMutableArray *paths = [NSMutableArray array];
    NSIndexSet *rows = [_outlineView selectedRowIndexes];
    for (NSUInteger row = [rows firstIndex]; row != NSNotFound;
         row = [rows indexGreaterThanIndex: row]) {
        id item = [_outlineView itemAtRow: row];
        if ([item isKindOfClass: [NSURL class]] && [[item path] length] > 0)
            [paths addObject: [item path]];
    }
    return paths;
}

// What a panel without a name field accepts: the selected rows. Empty when
// there is nothing to accept, and the panel then stays up.
- (NSArray *) _acceptablePaths {
    return [self _selectedPaths];
}

- (void) _setAcceptedPaths: (NSArray *) paths {
    [self _setFilename: [paths firstObject]];
}

// Asks the delegate whether each chosen URL is acceptable; the panel stays up when one is not.
- (BOOL) _validatePaths: (NSArray *) paths {
    id delegate = [self delegate];
    if (![delegate respondsToSelector: @selector(panel:validateURL:error:)])
        return YES;
    for (NSString *path in paths) {
        NSError *error = nil;
        if (![delegate panel: self
                  validateURL: [NSURL fileURLWithPath: path]
                        error: &error]) {
            if (error != nil)
                [NSApp presentError: error];
            else
                NSBeep();
            return NO;
        }
    }
    return YES;
}

- (IBAction) _selectFile: (id) sender {
    if (_nameField == nil) {
        NSArray *paths = [self _acceptablePaths];
        if ([paths count] == 0) {
            // Nothing to accept, but a selected folder is opened instead.
            NSURL *folder = [[_NSSavePanelNavigation navigationForPanel: self]
                    selectedFolderToOpen];
            if (folder != nil)
                [self setDirectory: [folder path]];
            else
                NSBeep();
            return;
        }
        if (![self _validatePaths: paths])
            return;
        [self _setAcceptedPaths: paths];
    } else {
        NSString *name = [self nameFieldStringValue];
        if ([name length] == 0) {
            NSURL *folder = [[_NSSavePanelNavigation navigationForPanel: self]
                    selectedFolderToOpen];
            if (folder != nil) {
                [self setDirectory: [folder path]];
                return;
            }
            [_nameField selectText: self];
            NSBeep();
            return;
        }
        // Like macOS, a typed path starting with / or ~ names the folder too.
        NSString *path = [name stringByExpandingTildeInPath];
        if (![path isAbsolutePath])
            path = [[self _selectedDirectory]
                    stringByAppendingPathComponent: name];
        NSString *target = [[path stringByDeletingLastPathComponent]
                stringByAppendingPathComponent:
                        [self _nameWithAllowedExtension: [path lastPathComponent]]];
        if (![self _validatePaths: @[ target ]])
            return;
        [self _setFilename: target];
    }

    [self _endWithCode: NSOKButton];
}

- (IBAction) _cancel: (id) sender {
    [self _endWithCode: NSCancelButton];
}

- (void) cancelOperation: (id) sender {
    [self _cancel: sender];
}

- (void) _endWithCode: (NSModalResponse) code {
    [[_NSSavePanelNavigation navigationForPanel: self] panelDidEnd];
    if (_runsAsSheet) {
        [NSApp endSheet: self returnCode: code];
    } else if (_runsModeless) {
        void (^handler)(NSModalResponse) = _modelessCompletionHandler;
        _modelessCompletionHandler = nil;
        _runsModeless = NO;
        [self orderOut: nil];
        if (handler != nil) {
            handler(code);
            [handler release];
        }
    } else {
        if ([NSApp modalWindow] == self)
            [NSApp stopModalWithCode: code];
        [self orderOut: nil];
    }
}

// Presents the panel as a modeless window and returns at once; the handler
// gets the button the user pressed once the panel is dismissed. A display
// with its own panels has no modeless form, so it runs them modally.
- (void) beginWithCompletionHandler: (void (^)(NSModalResponse result)) handler {
    if (_runsAsSheet || _runsModeless)
        [NSException raise: NSInternalInconsistencyException
                    format: @"-[%@ %@]: the panel is already running",
                            [self class], NSStringFromSelector(_cmd)];
    if ([[NSDisplay currentDisplay]
                implementsCustomPanelForClass: [self class]]) {
        NSModalResponse result = [self runModal];
        if (handler != nil)
            handler(result);
        return;
    }
    if (DarlingPortalBegin(self, nil, handler))
        return;

    _modelessCompletionHandler = [handler copy];
    _runsModeless = YES;
    [[_NSSavePanelNavigation navigationForPanel: self] panelWillShow];
    [self center];
    [_nameField selectText: self];
    [self makeKeyAndOrderFront: nil];
}

- (void) setNameFieldLabel: (NSString *) label {
}

- (NSString *) nameFieldLabel {
    return @"";
}

- (void) setShowsTagField: (BOOL) flag {
}

- (BOOL) showsTagField {
    return NO;
}

- (void) setTagNames: (NSArray *) names {
    (void)names;
}

- (NSArray *) tagNames {
    return [NSArray array];
}

- (void) setExtensionHidden: (BOOL) flag {
}

- (BOOL) isExtensionHidden {
    return NO;
}

- (void) setCanSelectHiddenExtension: (BOOL) flag {
}

- (BOOL) canSelectHiddenExtension {
    return NO;
}

- (void) beginSheetModalForWindow: (NSWindow *) window
                completionHandler: (void (^)(NSModalResponse result)) handler
{
    if (_runsAsSheet || _runsModeless)
        [NSException raise: NSInternalInconsistencyException
                    format: @"-[%@ %@]: the panel is already running",
                            [self class], NSStringFromSelector(_cmd)];
    if (window == nil) {
        NSModalResponse result = [self runModal];
        if (handler != nil)
            handler(result);
        return;
    }

    // The portal's dialog is a window of its own, made a child of the window.
    if (DarlingPortalBegin(self, window, handler))
        return;

    _sheetCompletionHandler = [handler copy];
    _styleMaskBeforeSheet = [self styleMask];
    _runsAsSheet = YES;
    [[_NSSavePanelNavigation navigationForPanel: self] panelWillShow];
    [NSApp beginSheet: self
            modalForWindow: window
             modalDelegate: self
            didEndSelector: @selector(_sheetDidEnd:returnCode:contextInfo:)
               contextInfo: NULL];
}

- (void) _sheetDidEnd: (NSWindow *) sheet
           returnCode: (NSModalResponse) code
          contextInfo: (void *) info
{
    void (^handler)(NSModalResponse) = _sheetCompletionHandler;
    _sheetCompletionHandler = nil;
    _runsAsSheet = NO;
    [self orderOut: nil];
    [self setStyleMask: _styleMaskBeforeSheet];
    if (handler != nil) {
        handler(code);
        [handler release];
    }
}

- (NSInteger) runModalForDirectory: (NSString *) directory
                              file: (NSString *) file
{
    [self _setFilename: file];
    if (directory != nil)
        [self setDirectory: directory];
    [self setNameFieldStringValue: file];

    return [self runModal];
}

- (NSInteger) runModal {
    NSInteger res;
    if ([[NSDisplay currentDisplay]
                implementsCustomPanelForClass: [self class]]) {
        res = [[NSDisplay currentDisplay] savePanel: self
                               runModalForDirectory: [self directory]
                                               file: [self filename]];
    } else if (DarlingPortalRunModal(self, &res)) {
        // The desktop's file chooser ran it.
    } else {
        [[_NSSavePanelNavigation navigationForPanel: self] panelWillShow];
        // Like macOS, show the panel centered rather than at the (screen-clamped) origin saved in its nib.
        [self center];
        [_nameField selectText: self];
        res = [NSApp runModalForWindow: self];
        [self close];
    }
    return res;
}

- (NSString *) directory {
    return _directory;
}

- (BOOL) treatsFilePackagesAsDirectories {
    return _treatsFilePackagesAsDirectories;
}

- (NSView *) accessoryView {
    return _accessoryView;
}

- (void) setTitle: (NSString *) title {
    // the title is the one of the window, which is what the window manager shows
    [super setTitle: title];
    title = [title copy];
    [_dialogTitle release];
    _dialogTitle = title;
}

// The file browser lists the panel's directory, as documented for
// directoryURL; without one it lists "/".
- (void) _showDirectory {
    [[_NSSavePanelNavigation navigationForPanel: self] directoryDidChange];
}

- (void) setDirectory: (NSString *) directory {
    directory = [directory copy];
    [_directory release];
    _directory = directory;
    [self _showDirectory];
}

- (void) setDirectoryURL: (NSURL *) url {
    [self setDirectory: [url path]];
}

- (NSURL *) directoryURL {
    NSString *dir = [self directory];
    return (dir != nil && [dir length] > 0) ? [NSURL fileURLWithPath: dir] : nil;
}

- (void) setRequiredFileType: (NSString *) type {
    @synchronized(self) {
        type = [type copy];
        [_requiredFileType release];
        _requiredFileType = type;
    }
}

- (NSString *) requiredFileType {
    id ret = nil;
    @synchronized(self) {
        ret = [[_requiredFileType copy] autorelease];
    }
    return ret;
}

- (void) setMessage: (NSString *) message; {
    @synchronized(self) {
        if (_message != message) {
            [_message release];
            _message = [message copy];
        }
    }
}

- (NSString *) message; {
    id ret = nil;
    @synchronized(self) {
        ret = [[_message copy] autorelease];
    }
    return ret;
}

- (void) setPrompt: (NSString *) prompt; {
    @synchronized(self) {
        if (_prompt != prompt) {
            [_prompt release];
            _prompt = [prompt copy];
        }
    }
}

- (NSString *) prompt; {
    id ret = nil;
    @synchronized(self) {
        ret = [[_prompt copy] autorelease];
    }
    return ret;
}

- (void) setTreatsFilePackagesAsDirectories: (BOOL) flag {
    _treatsFilePackagesAsDirectories = flag;
}

- (void) setAccessoryView: (NSView *) view {
    NSView *old = _accessoryView;
    _accessoryView = [view retain];
    // The navigation puts the view into the panel, below the file list.
    [[_NSSavePanelNavigation navigationForPanel: self] accessoryViewDidChangeFrom: old];
    [old release];
}

- (void) setCanCreateDirectories: (BOOL) value {
    _canCreateDirectories = value;
}

- (BOOL) canCreateDirectories {
    return _canCreateDirectories;
}

- (void) setAllowedFileTypes: (NSArray *) value {
    [_allowedFileTypes release];
    _allowedFileTypes = [value copy];
}

- (NSArray *) allowedFileTypes {
    return [[_allowedFileTypes copy] autorelease];
}

- (NSArray *) allowedContentTypes {
    return _allowedContentTypes ? [[_allowedContentTypes copy] autorelease]
                                : [NSArray array];
}

- (void) setAllowedContentTypes: (NSArray *) types {
    NSArray *copy = [types copy];
    [_allowedContentTypes release];
    _allowedContentTypes = copy;

    NSMutableArray *extensions = [NSMutableArray array];
    for (id type in types) {
        if (![type respondsToSelector: @selector(preferredFilenameExtension)])
            continue;
        NSString *extension = [type preferredFilenameExtension];
        if ([extension isKindOfClass: [NSString class]] &&
            [extension length] > 0 && ![extensions containsObject: extension])
            [extensions addObject: extension];
    }
    [self setAllowedFileTypes: [extensions count] > 0 ? extensions : nil];
}

- (void) setAllowsOtherFileTypes: (BOOL) value {
    _allowsOtherFileTypes = value;
}

- (void) beginSheetForDirectory: (NSString *) path
                           file: (NSString *) name
                 modalForWindow: (NSWindow *) docWindow
                  modalDelegate: (id) modalDelegate
                 didEndSelector: (SEL) didEndSelector
                    contextInfo: (void *) contextInfo
{
    id inv = [NSInvocation
            invocationWithMethodSignature:
                    [self methodSignatureForSelector: @selector
                            (_background_beginSheetForDirectory:
                                                           file:modalForWindow
                                                               :modalDelegate
                                                               :didEndSelector
                                                               :contextInfo:)]];
    [inv setTarget: self];
    [inv setSelector: @selector
            (_background_beginSheetForDirectory:
                                           file:modalForWindow:modalDelegate
                                               :didEndSelector:contextInfo:)];
    [inv setArgument: &path atIndex: 2];
    [inv setArgument: &name atIndex: 3];
    [inv setArgument: &docWindow atIndex: 4];
    [inv setArgument: &modalDelegate atIndex: 5];
    [inv setArgument: &didEndSelector atIndex: 6];
    [inv setArgument: &contextInfo atIndex: 7];
    [inv retainArguments];
    [inv performSelectorInBackground: @selector(invoke) withObject: nil];
}

- (void) _selector_savePanelDidEnd: (NSSavePanel *) sheet
                        returnCode: (int) returnCode
                       contextInfo: (void *) contextInfo;
{
}

- (void) _background_beginSheetForDirectory: (NSString *) path
                                       file: (NSString *) name
                             modalForWindow: (NSWindow *) docWindow
                              modalDelegate: (id) modalDelegate
                             didEndSelector: (SEL) didEndSelector
                                contextInfo: (void *) contextInfo
{
    id pool = [NSAutoreleasePool new];
    int ret = [self runModalForDirectory: path file: name];

    id inv = [NSInvocation
            invocationWithMethodSignature:
                    [self methodSignatureForSelector: @selector
                            (_selector_savePanelDidEnd:
                                            returnCode:contextInfo:)]];

    [inv setTarget: modalDelegate];
    [inv setSelector: didEndSelector];
    [inv setArgument: &self atIndex: 2];
    [inv setArgument: &ret atIndex: 3];
    [inv setArgument: &contextInfo atIndex: 4];
    [inv retainArguments];

    [inv performSelectorOnMainThread: @selector(invoke)
                          withObject: nil
                       waitUntilDone: YES];
    [pool release];
}

@end
