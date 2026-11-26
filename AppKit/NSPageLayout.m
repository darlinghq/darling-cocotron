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

#import <AppKit/NSPageLayout.h>
#import <AppKit/NSApplication.h>
#import <AppKit/NSPrintInfo.h>
#import <AppKit/NSPopUpButton.h>
#import <AppKit/NSTextField.h>
#import <AppKit/NSWindow.h>
#import <ApplicationServices/ApplicationServices.h>
#import <Foundation/NSArray.h>
#import <Foundation/NSString.h>
#import <Foundation/NSThread.h>
#import <objc/message.h>
#import "NSPrintDialogSupport.h"

// The panel of the page setup: the paper of the printer, the orientation and the scale. What it changes
// goes into the print info, and so into its page format.
@interface _NSPageLayoutController : NSObject {
    NSPrintInfo *_printInfo;
    _NSPrintDialogWindow *_window;
    NSPopUpButton *_paper, *_orientation;
    NSTextField *_scale;
    NSMutableArray *_papers;	// the sizes of the papers in the menu, as values
    NSMutableArray *_names;
}
- initWithPrintInfo: (NSPrintInfo *) printInfo;
- (NSInteger) run;
@end

@implementation _NSPageLayoutController

- initWithPrintInfo: (NSPrintInfo *) printInfo {
    NSSize current = [printInfo paperSize];
    PMPrintSession session = [printInfo PMPrintSession];
    PMPrinter printer = NULL;
    CFArrayRef papers = NULL;
    NSInteger selected = -1;

    _printInfo = [printInfo retain];
    _papers = [[NSMutableArray alloc] init];
    _names = [[NSMutableArray alloc] init];
    // the papers of the printer and, when the paper of the print info is not one of them, that one
    PMSessionGetCurrentPrinter(session, &printer);
    if (printer != NULL && PMPrinterGetPaperList(printer, &papers) == noErr) {
        for (CFIndex i = 0; i < CFArrayGetCount(papers); i++) {
            PMPaper paper = (PMPaper) CFArrayGetValueAtIndex(papers, i);
            double width = 0, height = 0;
            CFStringRef name = NULL;

            PMPaperGetWidth(paper, &width);
            PMPaperGetHeight(paper, &height);
            if (PMPaperCreateLocalizedName(paper, printer, &name) != noErr || name == NULL)
                continue;
            if (selected < 0 && fabs(width - current.width) < 1 && fabs(height - current.height) < 1)
                selected = [_papers count];
            [_papers addObject: [NSValue valueWithSize: NSMakeSize(width, height)]];
            [_names addObject: (NSString *) name];
            CFRelease(name);
        }
    }
    if (selected < 0 && current.width > 0 && current.height > 0) {
        selected = [_papers count];
        [_papers addObject: [NSValue valueWithSize: current]];
        [_names addObject: [printInfo paperName] != nil ? [printInfo paperName] : @"Custom"];
    }

    _window = NSPrintDialogMakeWindow(@"Page Setup", NSMakeSize(380, 190), self);
    NSView *content = [_window contentView];

    [content addSubview: NSPrintDialogLabel(@"Paper Size:", NSMakeRect(20, 140, 95, 22))];
    _paper = NSPrintDialogPopUp(_names, NSMakeRect(120, 138, 240, 26));
    if (selected >= 0)
        [_paper selectItemAtIndex: selected];
    [content addSubview: _paper];
    [content addSubview: NSPrintDialogLabel(@"Orientation:", NSMakeRect(20, 104, 95, 22))];
    _orientation = NSPrintDialogPopUp([NSArray arrayWithObjects: @"Portrait", @"Landscape", nil], NSMakeRect(120, 102, 240, 26));
    [_orientation selectItemAtIndex: [printInfo orientation] == NSLandscapeOrientation ? 1 : 0];
    [content addSubview: _orientation];
    [content addSubview: NSPrintDialogLabel(@"Scale:", NSMakeRect(20, 68, 95, 22))];
    _scale = NSPrintDialogField([NSString stringWithFormat: @"%g", [printInfo scalingFactor] * 100], NSMakeRect(120, 66, 60, 24));
    [content addSubview: _scale];
    [content addSubview: NSPrintDialogLabel(@"%", NSMakeRect(186, 68, 30, 22))];
    NSPrintDialogAddButtons(_window, @"OK", self);
    return self;
}

- (void) dealloc {
    [_window release];
    [_printInfo release];
    [_papers release];
    [_names release];
    [super dealloc];
}

- (void) accept: (id) sender {
    NSInteger index = [_paper indexOfSelectedItem];
    double scale = [_scale doubleValue];

    if (index >= 0 && index < (NSInteger) [_papers count]) {
        [_printInfo setPaperSize: [[_papers objectAtIndex: index] sizeValue]];
        [_printInfo setPaperName: [_names objectAtIndex: index]];
    }
    [_printInfo setOrientation: [_orientation indexOfSelectedItem] == 1 ? NSLandscapeOrientation : NSPortraitOrientation];
    // a scale that is not a percentage that a page can have stays as it was
    if (scale >= 1 && scale <= 10000)
        [_printInfo setScalingFactor: scale / 100];
    [NSApp stopModalWithCode: NSOKButton];
}

- (void) cancel: (id) sender {
    [NSApp stopModalWithCode: NSCancelButton];
}

- (NSInteger) run {
    return NSPrintDialogRun(_window);
}

@end

@implementation NSPageLayout

+ (NSPageLayout *) pageLayout {
    return NSThreadSharedInstance(@"NSPageLayout");
}

- (int) runModalWithPrintInfo: (NSPrintInfo *) printInfo {
    _NSPageLayoutController *controller = [[_NSPageLayoutController alloc] initWithPrintInfo: printInfo];
    NSInteger result = [controller run];

    [controller release];
    return result == NSOKButton ? NSOKButton : NSCancelButton;
}

- (int) runModal {
    return [self runModalWithPrintInfo: [NSPrintInfo sharedPrintInfo]];
}

- (void) beginSheetWithPrintInfo: (NSPrintInfo *) printInfo
                  modalForWindow: (NSWindow *) docWindow
                        delegate: (id) delegate
                  didEndSelector: (SEL) didEndSelector
                     contextInfo: (void *) contextInfo
{
    NSInteger returnCode = [self runModalWithPrintInfo: printInfo];
    if (delegate != nil && didEndSelector != NULL)
        ((void (*)(id, SEL, NSPageLayout *, NSInteger, void *)) objc_msgSend)(
                delegate, didEndSelector, self, returnCode, contextInfo);
}

@end
