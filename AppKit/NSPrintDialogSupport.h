/* Copyright (c) 2026 Lubos Dolezel

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


// The window and the controls that the page setup panel and the print panel are made of

#import <AppKit/NSPanel.h>
#import <AppKit/NSButton.h>
#import <AppKit/NSTextField.h>
#import <AppKit/NSPopUpButton.h>

// A panel that is accepted by Return and Enter and cancelled by Escape, whatever has the keyboard focus. The
// owner gets -accept: and -cancel: for them.
@interface _NSPrintDialogWindow : NSPanel {
    id _dialogOwner;
}
- (void) setDialogOwner: (id) owner;
@end

@interface NSObject (_NSPrintDialogOwner)
- (void) accept: (id) sender;
- (void) cancel: (id) sender;
@end

// The window of a dialog of the size, with the title
_NSPrintDialogWindow *NSPrintDialogMakeWindow(NSString *title, NSSize size, id owner);
NSTextField *NSPrintDialogLabel(NSString *text, NSRect frame);
NSTextField *NSPrintDialogField(NSString *text, NSRect frame);
NSButton *NSPrintDialogButton(NSString *title, NSRect frame, id target, SEL action);
NSPopUpButton *NSPrintDialogPopUp(NSArray *titles, NSRect frame);
// Adds the OK (default) and the Cancel button at the bottom right of the window
void NSPrintDialogAddButtons(NSWindow *window, NSString *okTitle, id owner);
// Runs the dialog modally; the result is NSOKButton or NSCancelButton
NSInteger NSPrintDialogRun(_NSPrintDialogWindow *window);
