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

#import <AppKit/NSDisplay.h>
#import <AppKit/NSGraphicsContext.h>
#import <AppKit/NSPanel.h>
#import <AppKit/NSPrintInfo.h>
#import <AppKit/NSPrintOperation.h>
#import <AppKit/NSPrintPanel.h>
#import <AppKit/NSView.h>

#import "NSPrintProgressPanelController.h"
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
        type == NSPrintOperationEPSInRect || type == NSPrintOperationFile)
        [NS_EXTRA(NSPrintOperation, self)->_printInfo setPaperSize: rect.size];
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
                        context: (CGContextRef) context
{
    NSRange result = NSMakeRange(1, 0);
    NSRect bounds = [NS_EXTRA(NSPrintOperation, self)->_view bounds];
    NSRect imageableRect = [NS_EXTRA(NSPrintOperation, self)->_printInfo imageablePageBounds];
    BOOL isFlipped = [NS_EXTRA(NSPrintOperation, self)->_view isFlipped];
    CGFloat top = isFlipped ? NSMinY(bounds) : NSMaxY(bounds);
    NSPrintingOrientation orientation = [NS_EXTRA(NSPrintOperation, self)->_printInfo orientation];

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

        [NS_EXTRA(NSPrintOperation, self)->_view adjustPageWidthNew: &right
                             left: left
                            right: right
                            limit: rightLimit];
        [NS_EXTRA(NSPrintOperation, self)->_view adjustPageHeightNew: &bottom
                               top: top
                            bottom: bottom
                             limit: bottomLimit];

        if (context != nil &&
            (pageRange.location == NSNotFound ||
             NSLocationInRange(NSMaxRange(result), pageRange))) {
            NSRect rect = NSMakeRect(left, top, right - left, bottom - top);
            NSPoint location = [NS_EXTRA(NSPrintOperation, self)->_view locationOfPrintRect: rect];

            [NS_EXTRA(NSPrintOperation, self)->_view beginPageInRect: rect atPlacement: location];
            [NS_EXTRA(NSPrintOperation, self)->_view drawRect: rect];
            [NS_EXTRA(NSPrintOperation, self)->_view endPage];
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
                        context: (CGContextRef) context
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

        [NS_EXTRA(NSPrintOperation, self)->_view beginPageInRect: rect atPlacement: location];
        [NS_EXTRA(NSPrintOperation, self)->_view drawRect: rect];
        [NS_EXTRA(NSPrintOperation, self)->_view endPage];
        [printProgressPanelController setCurrentPage: i];
    }
    [printProgressPanelController hidePanel];
}

// The PDF document info: the job title, else the view's window title. A view
// outside any window has neither, and then there is no info dictionary.
- (NSDictionary *) _documentInfo {
    NSString *title = [self jobTitle];
    if (title == nil)
        title = [[NS_EXTRA(NSPrintOperation, self)->_view window] title];
    if (title == nil)
        return nil;
    return [NSDictionary dictionaryWithObject: title
                                       forKey: (NSString *) kCGPDFContextTitle];
}

- (NSGraphicsContext *) createContext {
    CGContextRef context;

    if (NS_EXTRA(NSPrintOperation, self)->_type == NSPrintOperationPrinter) {
        if (NS_EXTRA(NSPrintOperation, self)->_showsPrintPanel) {
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

            if (panelResult != NSOKButton) {
                return nil;
            }
        } else {
            NSLog(@"Printing not implemented without print panel yet");
            return nil;
        }

        if ((context = (CGContextRef)
                     [[NS_EXTRA(NSPrintOperation, self)->_printInfo dictionary] objectForKey: @"_KGContext"]) ==
            nil)
            return nil;
    } else if (NS_EXTRA(NSPrintOperation, self)->_type == NSPrintOperationPDFInRect) {
        NSDictionary *auxiliaryInfo = [self _documentInfo];

        CGDataConsumerRef consumer =
                CGDataConsumerCreateWithCFData((CFMutableDataRef) NS_EXTRA(NSPrintOperation, self)->_mutableData);

        context = CGPDFContextCreate(consumer, &NS_EXTRA(NSPrintOperation, self)->_insideRect,
                                     (CFDictionaryRef) auxiliaryInfo);
        [(id) context autorelease];

        CGDataConsumerRelease(consumer);
    } else if (NS_EXTRA(NSPrintOperation, self)->_type == NSPrintOperationFile) {
        NSDictionary *auxiliaryInfo = [self _documentInfo];

        NSString *filePath =
                [NS_EXTRA(NSPrintOperation, self)->_printInfo.dictionary objectForKey: NSPrintSavePath];
        CGDataConsumerRef consumer = CGDataConsumerCreateWithURL(
                (CFURLRef) [NSURL fileURLWithPath: filePath]);

        context = CGPDFContextCreate(consumer, &NS_EXTRA(NSPrintOperation, self)->_insideRect,
                                     (CFDictionaryRef) auxiliaryInfo);
        [(id) context autorelease];

        CGDataConsumerRelease(consumer);

    } else {
        return nil;
    }
    return [NSGraphicsContext graphicsContextWithGraphicsPort: context
                                                      flipped: NO];
}

- (void) destroyContext {
    if (NS_EXTRA(NSPrintOperation, self)->_type == NSPrintOperationPrinter) {
        [[NS_EXTRA(NSPrintOperation, self)->_printInfo dictionary] removeObjectForKey: @"_KGContext"];
    }
    [NS_EXTRA(NSPrintOperation, self)->_context release];
    NS_EXTRA(NSPrintOperation, self)->_context = nil;
}

- (NSGraphicsContext *) context {
    return NS_EXTRA(NSPrintOperation, self)->_context;
}

- (BOOL) runOperation {
    NSRange pageRange = NSMakeRange(NSNotFound, NSNotFound);
    BOOL knowsPageRange;
    CGContextRef cgContext;
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

    NS_EXTRA(NSPrintOperation, self)->_context = [[self createContext] retain];
    if (NS_EXTRA(NSPrintOperation, self)->_context == nil) {
        // It'll be nil if the user cancelled the print panel for example.
        return NO;
    }

    if (knowsPageRange) {
        int firstPage = [[dict objectForKey: NSPrintFirstPage] intValue];
        int lastPage = [[dict objectForKey: NSPrintLastPage] intValue];
        pageRange.location = firstPage;
        pageRange.length = lastPage - firstPage + 1;
    }
    cgContext = [NS_EXTRA(NSPrintOperation, self)->_context graphicsPort];

    [NS_EXTRA(NSPrintOperation, self)->_printInfo setUpPrintOperationDefaultValues];

    [NSGraphicsContext saveGraphicsState];
    [NSGraphicsContext setCurrentContext: NS_EXTRA(NSPrintOperation, self)->_context];
    [NS_EXTRA(NSPrintOperation, self)->_view beginDocument];

    if (NS_EXTRA(NSPrintOperation, self)->_type == NSPrintOperationPDFInRect) {
        [NS_EXTRA(NSPrintOperation, self)->_view beginPageInRect: NS_EXTRA(NSPrintOperation, self)->_insideRect atPlacement: NSMakePoint(0, 0)];
        [NS_EXTRA(NSPrintOperation, self)->_view displayRect: NS_EXTRA(NSPrintOperation, self)->_insideRect];
        [NS_EXTRA(NSPrintOperation, self)->_view endPage];
    } else {
        if (knowsPageRange)
            [self _paginateWithPageRange: pageRange context: cgContext];
        else
            [self _autopaginatePageRange: pageRange
                         actualPageRange: &pageRange
                                 context: cgContext];
    }

    [NS_EXTRA(NSPrintOperation, self)->_view endDocument];
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
