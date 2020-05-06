/* Copyright (c) 2006-2007 Christopher J. W. Lloyd <cjwl@objc.net>, 2008
   Johannes Fortmann

   Permission is hereby granted, free of charge, to any person obtaining a copy
   of this software and associated documentation files (the "Software"), to
   deal in the Software without restriction, including without limitation the
   rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
   sell copies of the Software, and to permit persons to whom the Software is
   furnished to do so, subject to the following conditions:

   The above copyright notice and this permission notice shall be included in
   all copies or substantial portions of the Software.

   THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
   IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
   FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
   AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
   LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
   FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS
   IN THE SOFTWARE. */

#import <AppKit/NSApplication.h>
#import <AppKit/NSDisplay.h>
#import <AppKit/NSRaise.h>
#import <AppKit/NSSavePanel.h>
#import <AppKit/NSView.h>

@implementation NSSavePanel

- (id) resetToDefaultValues {
    _dialogTitle = @"Save";
    _filename = @"";
    _directory = [NSHomeDirectory() copy];
    _requiredFileType = @"";
    _treatsFilePackagesAsDirectories = NO;
    _accessoryView = nil;
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
    }
    // FIXME: release it?
    return [_newPanel resetToDefaultValues];
}

- init {
    [self release];
    return [[NSSavePanel savePanel] retain];
}

- (void) dealloc {
    [_dialogTitle release];
    [_filename release];
    [_directory release];
    [_requiredFileType release];
    [_accessoryView release];
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

- (IBAction) _selectFile: (id) sender {
    NSURL *url = [_outlineView itemAtRow: [_outlineView selectedRow]];
    [self _setFilename: [url path]];

    [NSApp stopModalWithCode: NSOKButton];
}

- (IBAction) _cancel: (id) sender {
    [NSApp stopModalWithCode: NSCancelButton];
}

- (NSInteger) runModalForDirectory: (NSString *) directory
                              file: (NSString *) file {
    [self _setFilename: file];
    [self setDirectory: directory];

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

- (void) setMessage: (NSString *) message;
{
    @synchronized(self) {
        if (_message != message) {
            [_message release];
            _message = [message copy];
        }
    }
}

- (NSString *) message;
{
    id ret = nil;
    @synchronized(self) {
        ret = [[_message copy] autorelease];
    }
    return ret;
}

- (void) setPrompt: (NSString *) prompt;
{
    @synchronized(self) {
        if (_prompt != prompt) {
            [_prompt release];
            _prompt = [prompt copy];
        }
    }
}

- (NSString *) prompt;
{
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
    NSUnimplementedMethod();
}

- (void) beginSheetForDirectory: (NSString *) path
                           file: (NSString *) name
                 modalForWindow: (NSWindow *) docWindow
                  modalDelegate: (id) modalDelegate
                 didEndSelector: (SEL) didEndSelector
                    contextInfo: (void *) contextInfo {
    id inv = [NSInvocation
        invocationWithMethodSignature:
            [self
                methodSignatureForSelector: @selector
                (_background_beginSheetForDirectory:
                                               file:modalForWindow:modalDelegate
                                                   :didEndSelector:contextInfo
                                                   :)]];
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
{}

- (void) _background_beginSheetForDirectory: (NSString *) path
                                       file: (NSString *) name
                             modalForWindow: (NSWindow *) docWindow
                              modalDelegate: (id) modalDelegate
                             didEndSelector: (SEL) didEndSelector
                                contextInfo: (void *) contextInfo {
    id pool = [NSAutoreleasePool new];
    int ret = [self runModalForDirectory: path file: name];

    id inv = [NSInvocation invocationWithMethodSignature:
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
