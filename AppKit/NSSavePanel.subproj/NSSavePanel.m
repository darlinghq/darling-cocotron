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
#import <AppKit/NSRaise.h>
#import <AppKit/NSOutlineView.h>
#import <AppKit/NSSavePanel.h>
#import <AppKit/NSScrollView.h>
#import <AppKit/NSTextField.h>
#import <AppKit/NSView.h>

@implementation NSSavePanel

@synthesize showsHiddenFiles=_showsHiddenFiles;

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

- (id) resetToDefaultValues {
    _dialogTitle = @"Save";
    _nameFieldStringValue = @"";
    [_nameField setStringValue: @""];
    _filename = @"";
    _directory = [defaultDirectory() copy];
    _requiredFileType = @"";
    _treatsFilePackagesAsDirectories = NO;
    _accessoryView = nil;
    _showsHiddenFiles = false;
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

- init {
    [self release];
    return [[NSSavePanel savePanel] retain];
}

- (void) dealloc {
    [_dialogTitle release];
    [_nameFieldStringValue release];
    [_filename release];
    [_directory release];
    [_requiredFileType release];
    [_accessoryView release];
    [_nameField release];
    [_sheetCompletionHandler release];
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
    return [NSURL fileURLWithPath: [self filename]];
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

// Like macOS, a name without an allowed extension gets the first allowed one.
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
        if ([type caseInsensitiveCompare: extension] == NSOrderedSame)
            return name;
    }
    return [name stringByAppendingPathExtension: [types objectAtIndex: 0]];
}

- (IBAction) _selectFile: (id) sender {
    if (_nameField == nil) {
        NSURL *url = [_outlineView itemAtRow: [_outlineView selectedRow]];
        [self _setFilename: [url path]];
    } else {
        NSString *name = [self nameFieldStringValue];
        if ([name length] == 0) {
            [_nameField selectText: self];
            NSBeep();
            return;
        }
        [self _setFilename: [[self _selectedDirectory]
                                    stringByAppendingPathComponent:
                                            [self _nameWithAllowedExtension: name]]];
    }

    [self _endWithCode: NSOKButton];
}

- (IBAction) _cancel: (id) sender {
    [self _endWithCode: NSCancelButton];
}

- (void) _endWithCode: (NSModalResponse) code {
    if (_runsAsSheet)
        [NSApp endSheet: self returnCode: code];
    else
        [NSApp stopModalWithCode: code];
}

- (void) beginWithCompletionHandler: (void (^)(NSModalResponse result)) handler {
    NSUnimplementedMethod();
}

- (void) beginSheetModalForWindow: (NSWindow *) window
                completionHandler: (void (^)(NSModalResponse result)) handler
{
    if (_runsAsSheet)
        [NSException raise: NSInternalInconsistencyException
                    format: @"-[%@ %@]: the panel is already a sheet",
                            [self class], NSStringFromSelector(_cmd)];
    if (window == nil) {
        NSModalResponse result = [self runModal];
        if (handler != nil)
            handler(result);
        return;
    }

    _sheetCompletionHandler = [handler copy];
    _styleMaskBeforeSheet = [self styleMask];
    _runsAsSheet = YES;
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
    } else {
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
    title = [title copy];
    [_dialogTitle release];
    _dialogTitle = title;
}

- (void) setDirectory: (NSString *) directory {
    directory = [directory copy];
    [_directory release];
    _directory = directory;
}

- (void) setDirectoryURL: (NSURL *) url {
    [self setDirectory: [url path]];
}

- (NSURL *) directoryURL {
    return [NSURL fileURLWithPath: [self directory]];
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
    view = [view retain];
    [_accessoryView release];
    _accessoryView = view;
}

- (void) setCanCreateDirectories: (BOOL) value {
    NSUnimplementedMethod();
}

- (void) setAllowedFileTypes: (NSArray *) value {
    [_allowedFileTypes release];
    _allowedFileTypes = [value copy];
}

- (NSArray *) allowedFileTypes {
    return [[_allowedFileTypes copy] autorelease];
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
