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

#import <ApplicationServices/ApplicationServices.h>
#import <AppKit/NSDisplay.h>
#import <AppKit/NSGraphicsContext.h>
#import <AppKit/NSPanel.h>
#import <AppKit/NSPrintInfo.h>
#import <AppKit/NSPrintOperation.h>
#import <AppKit/NSPrintPanel.h>
#import <AppKit/NSView.h>

#import "NSPrintProgressPanelController.h"

// Private to the print info: the page inside its margins and the imageable area
@interface NSPrintInfo (NSPrintOperationPages)
- (NSRect) _printableArea;
@end
#import <objc/message.h>

enum {
    NSPrintOperationPDFInRect,
    NSPrintOperationEPSInRect,
    NSPrintOperationPrinter,
    NSPrintOperationFile,
};

@implementation NSPrintOperation

static NSString *const NSPrintOperationCurrentKey = @"NSPrintOperationCurrent";

// Each thread has its own current operation.
+ (NSPrintOperation *) currentOperation {
    return [[[NSThread currentThread] threadDictionary] objectForKey: NSPrintOperationCurrentKey];
}

+ (void) setCurrentOperation: (NSPrintOperation *) operation {
    NSMutableDictionary *dictionary = [[NSThread currentThread] threadDictionary];
    if (operation != nil)
        [dictionary setObject: operation forKey: NSPrintOperationCurrentKey];
    else
        [dictionary removeObjectForKey: NSPrintOperationCurrentKey];
}

- initWithView: (NSView *) view
         printInfo: (NSPrintInfo *) printInfo
        insideRect: (NSRect) rect
            toData: (NSMutableData *) data
              type: (int) type
{
    NS_EXTRA(NSPrintOperation, self)->_view = [view retain];
    NS_EXTRA(NSPrintOperation, self)->_printInfo = [printInfo copy];
    if (type == NSPrintOperationPDFInRect ||
        type == NSPrintOperationEPSInRect) {
        // the paper is the rectangle, as it is; a printing operation that saves its job has the paper of its print
        // info like any other
        [NS_EXTRA(NSPrintOperation, self)->_printInfo setPaperSize: rect.size];
        [NS_EXTRA(NSPrintOperation, self)->_printInfo setOrientation: NSPortraitOrientation];
    }
    NS_EXTRA(NSPrintOperation, self)->_printPanel = [[NSPrintPanel printPanel] retain];
    NS_EXTRA(NSPrintOperation, self)->_showsPrintPanel = YES;
    NS_EXTRA(NSPrintOperation, self)->_currentPage = 0;
    NS_EXTRA(NSPrintOperation, self)->_insideRect = rect;
    NS_EXTRA(NSPrintOperation, self)->_mutableData = [data retain];
    NS_EXTRA(NSPrintOperation, self)->_type = type;
    return self;
}

- initWithView: (NSView *) view printInfo: (NSPrintInfo *) printInfo {
    int type = NSPrintOperationPrinter;

    if ([[printInfo jobDisposition] isEqualToString: NSPrintSaveJob]) {
        type = NSPrintOperationFile;
    }
    return [self initWithView: view
                    printInfo: printInfo
                   insideRect: [view bounds]
                       toData: nil
                         type: type];
}

- (void) dealloc {
    [NS_EXTRA(NSPrintOperation, self)->_view release];
    [NS_EXTRA(NSPrintOperation, self)->_printInfo release];
    [NS_EXTRA(NSPrintOperation, self)->_printPanel release];
    [NS_EXTRA(NSPrintOperation, self)->_path release];
    [NS_EXTRA(NSPrintOperation, self)->_context release];
    [NS_EXTRA(NSPrintOperation, self)->_mutableData release];
    [NS_EXTRA(NSPrintOperation, self)->_jobTitle release];
    NS_EXTRA_FREE(NSPrintOperation, self);
    [super dealloc];
}

+ (NSPrintOperation *) printOperationWithView: (NSView *) view {
    return [[[self alloc] initWithView: view
                             printInfo: [NSPrintInfo sharedPrintInfo]]
            autorelease];
}

+ (NSPrintOperation *) printOperationWithView: (NSView *) view
                                    printInfo: (NSPrintInfo *) printInfo
{
    return [[[self alloc] initWithView: view printInfo: printInfo] autorelease];
}

+ (NSPrintOperation *) PDFOperationWithView: (NSView *) view
                                 insideRect: (NSRect) rect
                                     toData: (NSMutableData *) data
{
    return [self PDFOperationWithView: view
                           insideRect: rect
                               toData: data
                            printInfo: [NSPrintInfo sharedPrintInfo]];
}

+ (NSPrintOperation *) PDFOperationWithView: (NSView *) view
                                 insideRect: (NSRect) rect
                                     toData: (NSMutableData *) data
                                  printInfo: (NSPrintInfo *) printInfo
{
    return [[[self alloc] initWithView: view
                             printInfo: printInfo
                            insideRect: rect
                                toData: data
                                  type: NSPrintOperationPDFInRect] autorelease];
}

// The PDF goes into data as for toData:, and -runOperation writes it to path.
+ (NSPrintOperation *) PDFOperationWithView: (NSView *) view
                                 insideRect: (NSRect) rect
                                     toPath: (NSString *) path
                                  printInfo: (NSPrintInfo *) printInfo
{
    NSPrintOperation *operation = [self PDFOperationWithView: view
                                                  insideRect: rect
                                                      toData: [NSMutableData data]
                                                   printInfo: printInfo];
    NS_EXTRA(NSPrintOperation, operation)->_path = [path copy];
    return operation;
}

+ (NSPrintOperation *) EPSOperationWithView: (NSView *) view
                                 insideRect: (NSRect) rect
                                     toData: (NSMutableData *) data
{
    return [self EPSOperationWithView: view
                           insideRect: rect
                               toData: data
                            printInfo: [NSPrintInfo sharedPrintInfo]];
}

+ (NSPrintOperation *) EPSOperationWithView: (NSView *) view
                                 insideRect: (NSRect) rect
                                     toData: (NSMutableData *) data
                                  printInfo: (NSPrintInfo *) printInfo
{
    return [[[self alloc] initWithView: view
                             printInfo: printInfo
                            insideRect: rect
                                toData: data
                                  type: NSPrintOperationEPSInRect] autorelease];
}

- (BOOL) isCopyingOperation {
    return NO;
}

- (void) setAccessoryView: (NSView *) view {
    view = [view retain];
    [NS_EXTRA(NSPrintOperation, self)->_accessoryView release];
    NS_EXTRA(NSPrintOperation, self)->_accessoryView = view;
}

- (NSView *) view {
    return NS_EXTRA(NSPrintOperation, self)->_view;
}

- (NSPrintInfo *) printInfo {
    return NS_EXTRA(NSPrintOperation, self)->_printInfo;
}

- (NSPrintPanel *) printPanel {
    return NS_EXTRA(NSPrintOperation, self)->_printPanel;
}

- (BOOL) showsPrintPanel {
    return NS_EXTRA(NSPrintOperation, self)->_showsPrintPanel;
}

- (void) setShowsPrintPanel: (BOOL) flag {
    NS_EXTRA(NSPrintOperation, self)->_showsPrintPanel = flag;
}

- (int) currentPage {
    return NS_EXTRA(NSPrintOperation, self)->_currentPage;
}

- (BOOL) showsProgressPanel {
    return NS_EXTRA(NSPrintOperation, self)->_showsPrintProgressPanel;
}

- (void) setShowsProgressPanel: (BOOL) flag {
    NS_EXTRA(NSPrintOperation, self)->_showsPrintProgressPanel = flag;
}

- (void) _autopaginatePageRange: (NSRange) pageRange
                actualPageRange: (NSRange *) rangep
{
    NSRange result = NSMakeRange(1, 0);
    NSRect bounds = [NS_EXTRA(NSPrintOperation, self)->_view bounds];
    CGFloat scale = [NS_EXTRA(NSPrintOperation, self)->_printInfo scalingFactor];
    // The part of the view that fits a page: the printable area of the page, as large as the scaling factor lets
    // it be in the view
    NSRect imageableRect = [NS_EXTRA(NSPrintOperation, self)->_printInfo _printableArea];
    BOOL isFlipped = [NS_EXTRA(NSPrintOperation, self)->_view isFlipped];
    CGFloat top = isFlipped ? NSMinY(bounds) : NSMaxY(bounds);
    NSPrintingOrientation orientation = [NS_EXTRA(NSPrintOperation, self)->_printInfo orientation];

    if (scale <= 0)
        scale = 1;
    imageableRect.size.width /= scale;
    imageableRect.size.height /= scale;

    while (YES) {
        CGFloat heightAdjustLimit = [NS_EXTRA(NSPrintOperation, self)->_view heightAdjustLimit];
        CGFloat widthAdjustLimit = [NS_EXTRA(NSPrintOperation, self)->_view widthAdjustLimit];
        CGFloat left = NSMinX(bounds);
        CGFloat right = left + imageableRect.size.width;
        CGFloat rightLimit = left + imageableRect.size.width * widthAdjustLimit;
        CGFloat bottom = isFlipped ? top + imageableRect.size.height
                                   : top - imageableRect.size.height;
        CGFloat bottomLimit =
                isFlipped ? top + imageableRect.size.height * heightAdjustLimit
                          : top - imageableRect.size.height * heightAdjustLimit;

        if (orientation == NSLandscapeOrientation) {
            // FIX
        }

        if (isFlipped) {
            if (bottom > NSMaxY(bounds))
                bottom = NSMaxY(bounds);
        } else {
            if (bottom < NSMinY(bounds))
                bottom = NSMinY(bounds);
        }

        // a view narrower than the page is a page as wide as the view
        if (right > NSMaxX(bounds))
            right = NSMaxX(bounds);

        [NS_EXTRA(NSPrintOperation, self)->_view adjustPageWidthNew: &right
                             left: left
                            right: right
                            limit: rightLimit];
        [NS_EXTRA(NSPrintOperation, self)->_view adjustPageHeightNew: &bottom
                               top: top
                            bottom: bottom
                             limit: bottomLimit];

        if (pageRange.location == NSNotFound ||
            NSLocationInRange(NSMaxRange(result), pageRange)) {
            // the rectangle of the page, whichever way the view runs
            NSRect rect = NSMakeRect(left, MIN(top, bottom), right - left, fabs(bottom - top));
            NSPoint location = [NS_EXTRA(NSPrintOperation, self)->_view locationOfPrintRect: rect];

            [self _beginPageInRect: rect atPlacement: location];
            [NS_EXTRA(NSPrintOperation, self)->_view drawRect: rect];
            [self _endPage];
            NS_EXTRA(NSPrintOperation, self)->_currentPage++;
        }

        result.length++;

        top = bottom;

        if (isFlipped) {
            if (top >= NSMaxY(bounds))
                break;
        } else {
            if (top <= NSMinY(bounds))
                break;
        }
    }

    *rangep = result;
}

- (void) _paginateWithPageRange: (NSRange) pageRange
{
    int i;

    NSPrintProgressPanelController *printProgressPanelController = nil;

    if ([self showsProgressPanel]) {
        printProgressPanelController =
                [NSPrintProgressPanelController printProgressPanelController];
        if ([[[self printInfo] jobDisposition]
                    isEqualToString: NSPrintSaveJob]) {
            [printProgressPanelController
                    setTitle: NSLocalizedString(@"Save", @"Save a print job")];
        }
        [printProgressPanelController setMaxPages: pageRange.length];
        [printProgressPanelController showPanel];
    }
    for (i = 0, NS_EXTRA(NSPrintOperation, self)->_currentPage = pageRange.location; i < pageRange.length;
         i++, NS_EXTRA(NSPrintOperation, self)->_currentPage++) {
        NSRect rect = [NS_EXTRA(NSPrintOperation, self)->_view rectForPage: NS_EXTRA(NSPrintOperation, self)->_currentPage];
        NSPoint location = [NS_EXTRA(NSPrintOperation, self)->_view locationOfPrintRect: rect];

        [self _beginPageInRect: rect atPlacement: location];
        [NS_EXTRA(NSPrintOperation, self)->_view drawRect: rect];
        [self _endPage];
        [printProgressPanelController setCurrentPage: i];
    }
    [printProgressPanelController hidePanel];
}

// The PDF document info: the job title, else the view's window title. A view
// outside any window has neither, and then there is no info dictionary.
- (NSString *) _documentTitle {
    NSString *title = [self jobTitle];
    if (title == nil)
        title = [[NS_EXTRA(NSPrintOperation, self)->_view window] title];
    return title;
}

- (NSDictionary *) _documentInfo {
    NSString *title = [self _documentTitle];
    if (title == nil)
        return nil;
    return [NSDictionary dictionaryWithObject: title
                                       forKey: (NSString *) kCGPDFContextTitle];
}

// Whether the job is made by PrintCore: the job of a printing operation (also one that saves the job), as
// opposed to the PDF and EPS operations that make their data themselves.
- (BOOL) _usesPrintCore {
    return NS_EXTRA(NSPrintOperation, self)->_type == NSPrintOperationPrinter ||
           NS_EXTRA(NSPrintOperation, self)->_type == NSPrintOperationFile;
}

// Whether a page of the PrintCore session is open: the page and its graphics context are PrintCore's, and the
// view must not begin or end a page of the context itself (NSView's page methods ask).
- (BOOL) _printCorePageIsOpen {
    return NS_EXTRA(NSPrintOperation, self)->_printCorePageOpen;
}

// The job in a PrintCore session, as the print settings of the print info have it: a PDF file, the destination
// of the settings. There is no print queue to take the job otherwise.
- (BOOL) _beginPrintCoreDocument {
    NSPrintInfo *printInfo = NS_EXTRA(NSPrintOperation, self)->_printInfo;
    PMPrintSession session = [printInfo PMPrintSession];
    PMPrintSettings settings = [printInfo PMPrintSettings];
    PMPageFormat format = [printInfo PMPageFormat];
    NSString *title = [self _documentTitle];

    if (title != nil)
        PMPrintSettingsSetJobName(settings, (CFStringRef) title);
    return PMSessionBeginCGDocumentNoDialog(session, settings, format) == noErr;
}

// A page of the job: for a PrintCore job the page is begun in the session, whose graphics context is then the
// current one, and the view sets itself up in it.
- (void) _beginPageInRect: (NSRect) rect atPlacement: (NSPoint) placement {
    if ([self _usesPrintCore]) {
        NSPrintInfo *printInfo = NS_EXTRA(NSPrintOperation, self)->_printInfo;
        PMPrintSession session = [printInfo PMPrintSession];
        CGContextRef port = NULL;

        if (PMSessionBeginPageNoDialog(session, [printInfo PMPageFormat], NULL) == noErr &&
            PMSessionGetCGGraphicsContext(session, &port) == noErr && port != NULL) {
            NS_EXTRA(NSPrintOperation, self)->_printCorePageOpen = YES;
            [NS_EXTRA(NSPrintOperation, self)->_context release];
            NS_EXTRA(NSPrintOperation, self)->_context = [[NSGraphicsContext graphicsContextWithGraphicsPort: port
                                                                                                    flipped: NO] retain];
            [NSGraphicsContext setCurrentContext: NS_EXTRA(NSPrintOperation, self)->_context];
        }
    }
    [NS_EXTRA(NSPrintOperation, self)->_view beginPageInRect: rect atPlacement: placement];
}

- (void) _endPage {
    [NS_EXTRA(NSPrintOperation, self)->_view endPage];
    if (NS_EXTRA(NSPrintOperation, self)->_printCorePageOpen) {
        PMSessionEndPageNoDialog([NS_EXTRA(NSPrintOperation, self)->_printInfo PMPrintSession]);
        NS_EXTRA(NSPrintOperation, self)->_printCorePageOpen = NO;
    }
}

// Shows the print panel when the operation does. NO when the user cancelled it.
- (BOOL) _confirmedByPrintPanel {
    if (!NS_EXTRA(NSPrintOperation, self)->_showsPrintPanel)
        return YES;

    NSPrintPanel *printPanel = [self printPanel];
    int panelResult;

    // We can't assume that there are valid titles on every window
    NSString *title = [[NS_EXTRA(NSPrintOperation, self)->_view window] title];
    if (title == nil) {
        title = @"Printing View";
    }

    [[NS_EXTRA(NSPrintOperation, self)->_printInfo dictionary] setObject: NS_EXTRA(NSPrintOperation, self)->_view forKey: @"_NSView"];
    [[NS_EXTRA(NSPrintOperation, self)->_printInfo dictionary] setObject: title forKey: @"_title"];
    panelResult = [printPanel runModal];
    [[NS_EXTRA(NSPrintOperation, self)->_printInfo dictionary] removeObjectForKey: @"_NSView"];
    [[NS_EXTRA(NSPrintOperation, self)->_printInfo dictionary] removeObjectForKey: @"_title"];
    return panelResult == NSOKButton;
}

// The graphics context of the PDF operations, which make their data without PrintCore (an EPS operation has none).
// A PrintCore job has a context for each page, see -_beginPageInRect:atPlacement:.
- (NSGraphicsContext *) createContext {
    CGContextRef context;
    NSDictionary *auxiliaryInfo = [self _documentInfo];
    CGDataConsumerRef consumer =
            CGDataConsumerCreateWithCFData((CFMutableDataRef) NS_EXTRA(NSPrintOperation, self)->_mutableData);

    if (NS_EXTRA(NSPrintOperation, self)->_type != NSPrintOperationPDFInRect || consumer == NULL) {
        CGDataConsumerRelease(consumer);
        return nil;
    }
    context = CGPDFContextCreate(consumer, &NS_EXTRA(NSPrintOperation, self)->_insideRect,
                                 (CFDictionaryRef) auxiliaryInfo);
    [(id) context autorelease];

    CGDataConsumerRelease(consumer);
    return [NSGraphicsContext graphicsContextWithGraphicsPort: context
                                                      flipped: NO];
}

- (void) destroyContext {
    [NS_EXTRA(NSPrintOperation, self)->_context release];
    NS_EXTRA(NSPrintOperation, self)->_context = nil;
}

- (NSGraphicsContext *) context {
    return NS_EXTRA(NSPrintOperation, self)->_context;
}

- (BOOL) runOperation {
    NSRange pageRange = NSMakeRange(NSNotFound, NSNotFound);
    BOOL knowsPageRange;
    BOOL printCore = [self _usesPrintCore];
    CGContextRef cgContext = NULL;
    NSMutableDictionary *dict = [NS_EXTRA(NSPrintOperation, self)->_printInfo dictionary];

    [NSPrintOperation setCurrentOperation: self];

    // Set the page range if not set yet
    knowsPageRange = [NS_EXTRA(NSPrintOperation, self)->_view knowsPageRange: &pageRange];

    if (knowsPageRange) {
        if ([dict objectForKey: NSPrintFirstPage] == nil) {
            [dict setObject: [NSNumber numberWithInt: pageRange.location]
                     forKey: NSPrintFirstPage];
        }
        if ([dict objectForKey: NSPrintLastPage] == nil) {
            [dict setObject: [NSNumber numberWithInt: NSMaxRange(pageRange) - 1]
                     forKey: NSPrintLastPage];
        }
    } else {
        if ([dict objectForKey: NSPrintFirstPage] == nil) {
            [dict setObject: [NSNumber numberWithInt: 1]
                     forKey: NSPrintFirstPage];
        }
        if ([dict objectForKey: NSPrintLastPage] == nil) {
            [dict setObject: [NSNumber numberWithInt: 1]
                     forKey: NSPrintLastPage];
        }
    }

    if (printCore) {
        // The print panel may be cancelled by the user.
        if (![self _confirmedByPrintPanel] || ![self _beginPrintCoreDocument]) {
            [NSPrintOperation setCurrentOperation: nil];
            return NO;
        }
    } else {
        NS_EXTRA(NSPrintOperation, self)->_context = [[self createContext] retain];
        if (NS_EXTRA(NSPrintOperation, self)->_context == nil) {
            [NSPrintOperation setCurrentOperation: nil];
            return NO;
        }
        cgContext = [NS_EXTRA(NSPrintOperation, self)->_context graphicsPort];
    }

    if (knowsPageRange) {
        int firstPage = [[dict objectForKey: NSPrintFirstPage] intValue];
        int lastPage = [[dict objectForKey: NSPrintLastPage] intValue];
        pageRange.location = firstPage;
        pageRange.length = lastPage - firstPage + 1;
    }

    [NS_EXTRA(NSPrintOperation, self)->_printInfo setUpPrintOperationDefaultValues];

    [NSGraphicsContext saveGraphicsState];
    if (NS_EXTRA(NSPrintOperation, self)->_context != nil)
        [NSGraphicsContext setCurrentContext: NS_EXTRA(NSPrintOperation, self)->_context];
    [NS_EXTRA(NSPrintOperation, self)->_view beginDocument];

    if (NS_EXTRA(NSPrintOperation, self)->_type == NSPrintOperationPDFInRect) {
        [NS_EXTRA(NSPrintOperation, self)->_view beginPageInRect: NS_EXTRA(NSPrintOperation, self)->_insideRect atPlacement: NSMakePoint(0, 0)];
        [NS_EXTRA(NSPrintOperation, self)->_view displayRect: NS_EXTRA(NSPrintOperation, self)->_insideRect];
        [NS_EXTRA(NSPrintOperation, self)->_view endPage];
    } else {
        if (knowsPageRange)
            [self _paginateWithPageRange: pageRange];
        else
            [self _autopaginatePageRange: pageRange
                         actualPageRange: &pageRange];
    }

    [NS_EXTRA(NSPrintOperation, self)->_view endDocument];
    if (printCore)
        PMSessionEndDocumentNoDialog([NS_EXTRA(NSPrintOperation, self)->_printInfo PMPrintSession]);
    else
        CGPDFContextClose(cgContext);
    [NSGraphicsContext restoreGraphicsState];

    [self destroyContext];

    [NSPrintOperation setCurrentOperation: nil];

    if (NS_EXTRA(NSPrintOperation, self)->_path != nil)
        return [NS_EXTRA(NSPrintOperation, self)->_mutableData writeToFile: NS_EXTRA(NSPrintOperation, self)->_path atomically: YES];
    return YES;
}

@end

@implementation NSPrintOperation (NSJobTitle)

- (NSString *) jobTitle {
    return NS_EXTRA(NSPrintOperation, self)->_jobTitle;
}

- (void) setJobTitle: (NSString *) title {
    title = [title copy];
    [NS_EXTRA(NSPrintOperation, self)->_jobTitle release];
    NS_EXTRA(NSPrintOperation, self)->_jobTitle = title;
}

@end

@implementation NSPrintOperation (NSPrintOperationModal)

- (void) setShowPanels: (BOOL) flag {
    [self setShowsPrintPanel: flag];
    [self setShowsProgressPanel: flag];
}

- (BOOL) showPanels {
    return [self showsPrintPanel];
}

- (void) runOperationModalForWindow: (NSWindow *) docWindow
                           delegate: (id) delegate
                     didRunSelector: (SEL) didRunSelector
                        contextInfo: (void *) contextInfo
{
    BOOL success = [self runOperation];
    if (delegate != nil && didRunSelector != NULL)
        ((void (*)(id, SEL, NSPrintOperation *, BOOL, void *)) objc_msgSend)(
                delegate, didRunSelector, self, success, contextInfo);
}

@end
