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

#import <AppKit/NSPrintInfo.h>
#import <AppKit/NSPrinter.h>
#import <ApplicationServices/ApplicationServices.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSString.h>
#import <Foundation/NSThread.h>
#import <Foundation/NSValue.h>
#import <Foundation/NSURL.h>
#import <objc/runtime.h>
#import <math.h>
#import <limits.h>

NSPrintInfoAttributeKey const NSPrintPaperName = @"NSPaperName";
NSPrintInfoAttributeKey const NSPrintPaperSize = @"NSPaperSize";
NSPrintInfoAttributeKey const NSPrintOrientation = @"NSOrientation";
NSPrintInfoAttributeKey const NSPrintScalingFactor = @"NSScalingFactor";

NSPrintInfoAttributeKey const NSPrintLeftMargin = @"NSLeftMargin";
NSPrintInfoAttributeKey const NSPrintRightMargin = @"NSRightMargin";
NSPrintInfoAttributeKey const NSPrintTopMargin = @"NSTopMargin";
NSPrintInfoAttributeKey const NSPrintBottomMargin = @"NSBottomMargin";
NSPrintInfoAttributeKey const NSPrintHorizontallyCentered = @"NSHorizontallyCentered";
NSPrintInfoAttributeKey const NSPrintVerticallyCentered = @"NSVerticallyCentered";
NSPrintInfoAttributeKey const NSPrintHorizontalPagination = @"NSHorizonalPagination";
NSPrintInfoAttributeKey const NSPrintVerticalPagination = @"NSVerticalPagination";

NSPrintInfoAttributeKey const NSPrintAllPages = @"NSPrintAllPages";
NSPrintInfoAttributeKey const NSPrintCopies = @"NSCopies";
NSPrintInfoAttributeKey const NSPrintDetailedErrorReporting = @"NSDetailedErrorReporting";
NSPrintInfoAttributeKey const NSPrintFirstPage = @"NSFirstPage";
NSPrintInfoAttributeKey const NSPrintHeaderAndFooter = @"NSPrintHeaderAndFooter";
NSPrintInfoAttributeKey const NSPrintJobDisposition = @"NSJobDisposition";
NSPrintInfoAttributeKey const NSPrintJobSavingURL = @"NSJobSavingURL";
NSPrintInfoAttributeKey const NSPrintLastPage = @"NSLastPage";
NSPrintInfoAttributeKey const NSPrintMustCollate = @"NSMustCollate";
NSPrintInfoAttributeKey const NSPrintPrinter = @"NSPrinter";
NSPrintInfoAttributeKey const NSPrintPrinterName = @"NSPrinterName";
NSPrintInfoAttributeKey const NSPrintSelectionOnly = @"NSPrintSelectionOnly";

NSPrintJobDispositionValue const NSPrintSpoolJob = @"NSPrintSpoolJob";
NSPrintJobDispositionValue const NSPrintPreviewJob = @"NSPrintPreviewJob";
NSPrintJobDispositionValue const NSPrintSaveJob = @"NSPrintSaveJob";
NSPrintJobDispositionValue const NSPrintCancelJob = @"NSPrintCancelJob";

NSString *const NSPrintSavePath = @"NSPrintSavePath";

// The PrintCore objects behind a print info. A print info keeps its attributes in a dictionary, and the
// session, page format and print settings are made from them when asked for and kept: the attributes
// that are page setup or print settings are put into the objects again when they have changed since the
// objects were last made or updated, and updateFromPMPageFormat / updateFromPMPrintSettings take the
// values of the objects back into the attributes.
@interface _NSPrintInfoPMObjects : NSObject {
@public
    PMPrintSession session;
    PMPageFormat pageFormat;
    PMPrintSettings printSettings;
    NSString *pageSignature;
    NSString *settingsSignature;
}
@end

@implementation _NSPrintInfoPMObjects
- (void) dealloc {
    PMRelease(session);
    PMRelease(pageFormat);
    PMRelease(printSettings);
    [pageSignature release];
    [settingsSignature release];
    [super dealloc];
}
@end

static const char pmObjectsKey;

@implementation NSPrintInfo

+ (NSPrintInfo *) sharedPrintInfo {
    return NSThreadSharedInstance(@"NSPrintInfo");
}

+ (NSPrinter *) defaultPrinter {
    return [NSPrinter printerWithName: [[NSPrinter printerNames] firstObject]];
}

+ (void) setSharedPrintInfo: (NSPrintInfo *) printInfo {
    NSMutableDictionary *shared = [[NSThread currentThread] sharedDictionary];
    if (printInfo != nil)
        [shared setObject: printInfo forKey: @"NSPrintInfo"];
    else
        [shared removeObjectForKey: @"NSPrintInfo"];
}

- initWithDictionary: (NSDictionary *) dictionary {
    _attributes = [[NSMutableDictionary alloc] initWithDictionary: dictionary];
    // Unscaled unless the dictionary says otherwise; the dictionary then
    // holds the factor too, as on macOS 26.7.3.
    if ([_attributes objectForKey: NSPrintScalingFactor] == nil)
        [_attributes setObject: [NSNumber numberWithDouble: 1.0] forKey: NSPrintScalingFactor];
    return self;
}

- init {
    NSDictionary *defaults = [NSDictionary
            dictionaryWithObjectsAndKeys:
                    [NSNumber numberWithInt: 1], NSPrintCopies,
                    [NSNumber numberWithBool: YES], NSPrintAllPages,
                    @"US Letter", NSPrintPaperName,
                    [NSValue valueWithSize: NSMakeSize(612, 792)],
                    NSPrintPaperSize, [NSNumber numberWithFloat: 36],
                    NSPrintTopMargin, [NSNumber numberWithFloat: 36],
                    NSPrintLeftMargin, [NSNumber numberWithFloat: 36],
                    NSPrintRightMargin, [NSNumber numberWithFloat: 36],
                    NSPrintBottomMargin,
                    [NSNumber numberWithInt: NSPortraitOrientation],
                    NSPrintOrientation, nil];

    return [self initWithDictionary: defaults];
}

- (void) dealloc {
    [_attributes release];
    [super dealloc];
}

- copyWithZone: (NSZone *) zone {
    NSPrintInfo *copy = NSCopyObject(self, 0, zone);

    copy->_attributes = [_attributes mutableCopy];

    return copy;
}

- (NSMutableDictionary *) dictionary {
    return _attributes;
}

- (NSPrinter *) printer {
    NSPrinter *printer = [_attributes objectForKey: NSPrintPrinter];
    if (printer == nil) {
        printer = [NSPrintInfo defaultPrinter];
        if (printer != nil) {
            [_attributes setObject: printer forKey: NSPrintPrinter];
        }
    }
    return printer;
}

- (NSString *) jobDisposition {
    return [_attributes objectForKey: NSPrintJobDisposition];
}

- (NSString *) paperName {
    return [_attributes objectForKey: NSPrintPaperName];
}

- (NSSize) paperSize {
    return [[_attributes objectForKey: NSPrintPaperSize] sizeValue];
}

- (NSPrintingOrientation) orientation {
    return [[_attributes objectForKey: NSPrintOrientation] intValue];
}

- (NSPrintingPaginationMode) horizontalPagination {
    return [[_attributes objectForKey: NSPrintHorizontalPagination] intValue];
}

- (NSPrintingPaginationMode) verticalPagination {
    return [[_attributes objectForKey: NSPrintVerticalPagination] intValue];
}

- (CGFloat) topMargin {
    return [[_attributes objectForKey: NSPrintTopMargin] floatValue];
}

- (CGFloat) bottomMargin {
    return [[_attributes objectForKey: NSPrintBottomMargin] floatValue];
}

- (CGFloat) leftMargin {
    return [[_attributes objectForKey: NSPrintLeftMargin] floatValue];
}

- (CGFloat) rightMargin {
    return [[_attributes objectForKey: NSPrintRightMargin] floatValue];
}

- (BOOL) isHorizontallyCentered {
    return [[_attributes objectForKey: NSPrintHorizontallyCentered] boolValue];
}

- (BOOL) isVerticallyCentered {
    return [[_attributes objectForKey: NSPrintVerticallyCentered] boolValue];
}

- (NSString *) localizedPaperName {
    return [self paperName];
}

- (NSRect) imageablePageBounds {
    NSRect result;
    NSValue *imageable = [_attributes objectForKey: @"_imageableRect"];

    if (imageable != nil)
        result = [imageable rectValue];
    else {
        result.origin.x = 0;
        result.origin.y = 0;
        result.size = [self paperSize];
    }

    if ([self orientation] == NSLandscapeOrientation) {
        NSRect portrait = result;

        result.origin.x = portrait.origin.y;
        result.size.width = portrait.size.height;
        result.origin.y = portrait.origin.x;
        result.size.height = portrait.size.width;
    }

    return result;
}

// The part of the page a view is printed in, in page coordinates: the page inside its margins, kept within the
// imageable area. A page that the margins leave nothing of has its imageable area.
- (NSRect) _printableArea {
    NSSize paper = [self paperSize];
    NSRect imageable = [self imageablePageBounds];

    // the paper size is the one of the upright paper, the margins are those of the page as it is printed
    if ([self orientation] == NSLandscapeOrientation)
        paper = NSMakeSize(paper.height, paper.width);

    NSRect area = NSMakeRect([self leftMargin], [self bottomMargin],
                             paper.width - [self leftMargin] - [self rightMargin],
                             paper.height - [self topMargin] - [self bottomMargin]);

    area = NSIntersectionRect(area, imageable);
    if (area.size.width <= 0 || area.size.height <= 0)
        return imageable;
    return area;
}

- (void) setPrinter: (NSPrinter *) printer {
    [_attributes setObject: printer forKey: NSPrintPrinter];
}

- (void) setJobDisposition: (NSString *) value {
    [_attributes setObject: value forKey: NSPrintJobDisposition];
}

- (void) setPaperName: (NSString *) value {
    [_attributes setObject: value forKey: NSPrintPaperName];
}

- (void) setPaperSize: (NSSize) value {
    [_attributes setObject: [NSValue valueWithSize: value]
                    forKey: NSPrintPaperSize];
}

- (void) setOrientation: (NSPrintingOrientation) value {
    [_attributes setObject: [NSNumber numberWithInt: value]
                    forKey: NSPrintOrientation];
}

- (void) setHorizontalPagination: (NSPrintingPaginationMode) value {
    [_attributes setObject: [NSNumber numberWithInt: value]
                    forKey: NSPrintHorizontalPagination];
}

- (void) setVerticalPagination: (NSPrintingPaginationMode) value {
    [_attributes setObject: [NSNumber numberWithInt: value]
                    forKey: NSPrintVerticalPagination];
}

- (CGFloat) scalingFactor {
    return [[_attributes objectForKey: NSPrintScalingFactor] doubleValue];
}

- (void) setScalingFactor: (CGFloat) value {
    [_attributes setObject: [NSNumber numberWithDouble: value]
                    forKey: NSPrintScalingFactor];
}

- (void) setTopMargin: (CGFloat) value {
    [_attributes setObject: [NSNumber numberWithFloat: value]
                    forKey: NSPrintTopMargin];
}

- (void) setBottomMargin: (CGFloat) value {
    [_attributes setObject: [NSNumber numberWithFloat: value]
                    forKey: NSPrintBottomMargin];
}

- (void) setLeftMargin: (CGFloat) value {
    [_attributes setObject: [NSNumber numberWithFloat: value]
                    forKey: NSPrintLeftMargin];
}

- (void) setRightMargin: (CGFloat) value {
    [_attributes setObject: [NSNumber numberWithFloat: value]
                    forKey: NSPrintRightMargin];
}

- (void) setHorizontallyCentered: (BOOL) value {
    [_attributes setObject: [NSNumber numberWithBool: value]
                    forKey: NSPrintHorizontallyCentered];
}

- (void) setVerticallyCentered: (BOOL) value {
    [_attributes setObject: [NSNumber numberWithBool: value]
                    forKey: NSPrintVerticallyCentered];
}

- (void) setUpPrintOperationDefaultValues {
    // do nothing ?
}


- (_NSPrintInfoPMObjects *) _pmObjects {
    _NSPrintInfoPMObjects *objects = objc_getAssociatedObject(self, &pmObjectsKey);

    if (objects == nil) {
        objects = [[[_NSPrintInfoPMObjects alloc] init] autorelease];
        PMCreateSession(&objects->session);
        PMCreatePageFormat(&objects->pageFormat);
        PMCreatePrintSettings(&objects->printSettings);
        PMSessionDefaultPageFormat(objects->session, objects->pageFormat);
        PMSessionDefaultPrintSettings(objects->session, objects->printSettings);
        objc_setAssociatedObject(self, &pmObjectsKey, objects, OBJC_ASSOCIATION_RETAIN);
        // the attributes that the dictionary has (the defaults of the object are those of a session)
        [self _pushPageFormat];
        [self _pushPrintSettings];
    }
    return objects;
}

// The attributes of the page setup, in one string, to tell whether they have changed
- (NSString *) _pageSignature {
    NSSize size = [self paperSize];

    return [NSString stringWithFormat: @"%g %g %d %g", size.width, size.height, (int) [self orientation],
                     [self scalingFactor]];
}

- (NSString *) _settingsSignature {
    NSDictionary *d = _attributes;

    return [NSString stringWithFormat: @"%@ %@ %@ %@ %@ %@ %@", [d objectForKey: NSPrintCopies],
                     [d objectForKey: NSPrintAllPages], [d objectForKey: NSPrintFirstPage],
                     [d objectForKey: NSPrintLastPage], [d objectForKey: NSPrintMustCollate],
                     [d objectForKey: NSPrintJobDisposition], [d objectForKey: NSPrintSavePath]];
}

// The paper that the size names in the list of the printer, else a paper of that size
static PMPaper paperOfSize(PMPrintSession session, NSSize size, NSString *name) {
    PMPrinter printer = NULL;
    CFArrayRef papers = NULL;
    PMPaper paper = NULL;

    PMSessionGetCurrentPrinter(session, &printer);
    if (printer && PMPrinterGetPaperList(printer, &papers) == noErr) {
        for (CFIndex i = 0; i < CFArrayGetCount(papers); i++) {
            PMPaper candidate = (PMPaper) CFArrayGetValueAtIndex(papers, i);
            double width = 0, height = 0;

            PMPaperGetWidth(candidate, &width);
            PMPaperGetHeight(candidate, &height);
            if (fabs(width - size.width) < 1 && fabs(height - size.height) < 1) {
                CFRetain(candidate);
                return candidate;
            }
        }
    }
    PMPaperMargins none = { 0, 0, 0, 0 };

    PMPaperCreateCustom(printer, CFSTR("custom"), (CFStringRef) (name ? name : @"Custom"), size.width, size.height,
                        &none, &paper);
    return paper;
}

- (void) _pushPageFormat {
    _NSPrintInfoPMObjects *objects = objc_getAssociatedObject(self, &pmObjectsKey);
    NSSize size = [self paperSize];

    if (objects == nil)
        return;
    if (size.width > 0 && size.height > 0) {
        PMPaper paper = paperOfSize(objects->session, size, [self paperName]);
        PMPageFormat format = NULL;

        if (paper != NULL && PMCreatePageFormatWithPMPaper(&format, paper) == noErr) {
            PMCopyPageFormat(format, objects->pageFormat);
            PMRelease(format);
        }
        PMRelease(paper);
    }
    PMSetOrientation(objects->pageFormat, [self orientation] == NSLandscapeOrientation ? kPMLandscape : kPMPortrait,
                     false);
    if ([self scalingFactor] > 0)
        PMSetScale(objects->pageFormat, [self scalingFactor] * 100);
    PMSessionValidatePageFormat(objects->session, objects->pageFormat, NULL);
    [objects->pageSignature release];
    objects->pageSignature = [[self _pageSignature] retain];
}

- (void) _pushPrintSettings {
    _NSPrintInfoPMObjects *objects = objc_getAssociatedObject(self, &pmObjectsKey);
    NSNumber *copies = [_attributes objectForKey: NSPrintCopies];

    if (objects == nil)
        return;
    if (copies != nil)
        PMSetCopies(objects->printSettings, [copies unsignedIntValue], false);
    if ([[_attributes objectForKey: NSPrintAllPages] boolValue] ||
        [_attributes objectForKey: NSPrintAllPages] == nil) {
        PMSetFirstPage(objects->printSettings, 1, false);
        PMSetLastPage(objects->printSettings, kPMPrintAllPages, false);
    } else {
        PMSetFirstPage(objects->printSettings, [[_attributes objectForKey: NSPrintFirstPage] unsignedIntValue], false);
        PMSetLastPage(objects->printSettings, [[_attributes objectForKey: NSPrintLastPage] unsignedIntValue], false);
    }
    if ([_attributes objectForKey: NSPrintMustCollate] != nil)
        PMSetCollate(objects->printSettings, [[_attributes objectForKey: NSPrintMustCollate] boolValue]);
    NSString *path = [_attributes objectForKey: NSPrintSavePath];

    if ([[self jobDisposition] isEqualToString: NSPrintSaveJob] && path != nil) {
        NSURL *url = [NSURL fileURLWithPath: path];

        PMSessionSetDestination(objects->session, objects->printSettings, kPMDestinationFile, kPMDocumentFormatPDF,
                                (CFURLRef) url);
    } else {
        PMSessionSetDestination(objects->session, objects->printSettings, kPMDestinationPrinter, NULL, NULL);
    }
    [objects->settingsSignature release];
    objects->settingsSignature = [[self _settingsSignature] retain];
}

- (void *) PMPrintSession {
    return [self _pmObjects]->session;
}

- (void *) PMPageFormat {
    _NSPrintInfoPMObjects *objects = [self _pmObjects];

    if (![objects->pageSignature isEqualToString: [self _pageSignature]])
        [self _pushPageFormat];
    return objects->pageFormat;
}

- (void *) PMPrintSettings {
    _NSPrintInfoPMObjects *objects = [self _pmObjects];

    if (![objects->settingsSignature isEqualToString: [self _settingsSignature]])
        [self _pushPrintSettings];
    return objects->printSettings;
}

- (void) updateFromPMPageFormat {
    _NSPrintInfoPMObjects *objects = [self _pmObjects];
    PMPaper paper = NULL;
    PMOrientation orientation = kPMPortrait;
    double scale = 100;
    PMRect pageRect, paperRect;

    PMSessionValidatePageFormat(objects->session, objects->pageFormat, NULL);
    if (PMGetPageFormatPaper(objects->pageFormat, &paper) == noErr && paper != NULL) {
        double width = 0, height = 0;
        CFStringRef name = NULL;
        PMPrinter printer = NULL;

        PMPaperGetWidth(paper, &width);
        PMPaperGetHeight(paper, &height);
        [_attributes setObject: [NSValue valueWithSize: NSMakeSize(width, height)] forKey: NSPrintPaperSize];
        PMSessionGetCurrentPrinter(objects->session, &printer);
        if (PMPaperCreateLocalizedName(paper, printer, &name) == noErr && name != NULL) {
            [_attributes setObject: (NSString *) name forKey: NSPrintPaperName];
            CFRelease(name);
        }
    }
    if (PMGetOrientation(objects->pageFormat, &orientation) == noErr)
        [_attributes setObject: [NSNumber numberWithInt: orientation == kPMLandscape || orientation == kPMReverseLandscape
                                                                 ? NSLandscapeOrientation
                                                                 : NSPortraitOrientation]
                        forKey: NSPrintOrientation];
    if (PMGetScale(objects->pageFormat, &scale) == noErr)
        [_attributes setObject: [NSNumber numberWithDouble: scale / 100] forKey: NSPrintScalingFactor];
    // the part of the paper that a printer can print on, as the rectangle of the portrait paper
    if (PMGetUnadjustedPageRect(objects->pageFormat, &pageRect) == noErr &&
        PMGetUnadjustedPaperRect(objects->pageFormat, &paperRect) == noErr)
        [_attributes setObject: [NSValue valueWithRect: NSMakeRect(-paperRect.left, paperRect.bottom - pageRect.bottom,
                                                                   pageRect.right, pageRect.bottom)]
                        forKey: @"_imageableRect"];
    [objects->pageSignature release];
    objects->pageSignature = [[self _pageSignature] retain];
}

- (void) updateFromPMPrintSettings {
    _NSPrintInfoPMObjects *objects = [self _pmObjects];
    UInt32 copies = 1, first = 1, last = INT_MAX;
    Boolean collate = false;
    PMDestinationType destination = kPMDestinationPrinter;

    if (PMGetCopies(objects->printSettings, &copies) == noErr)
        [_attributes setObject: [NSNumber numberWithUnsignedInt: copies] forKey: NSPrintCopies];
    PMGetFirstPage(objects->printSettings, &first);
    PMGetLastPage(objects->printSettings, &last);
    if (first <= 1 && last >= INT_MAX) {
        [_attributes setObject: [NSNumber numberWithBool: YES] forKey: NSPrintAllPages];
    } else {
        [_attributes setObject: [NSNumber numberWithBool: NO] forKey: NSPrintAllPages];
        [_attributes setObject: [NSNumber numberWithUnsignedInt: first] forKey: NSPrintFirstPage];
        [_attributes setObject: [NSNumber numberWithUnsignedInt: last] forKey: NSPrintLastPage];
    }
    if (PMGetCollate(objects->printSettings, &collate) == noErr)
        [_attributes setObject: [NSNumber numberWithBool: collate] forKey: NSPrintMustCollate];
    PMSessionGetDestinationType(objects->session, objects->printSettings, &destination);
    if (destination == kPMDestinationFile) {
        CFURLRef url = NULL;

        PMSessionCopyDestinationLocation(objects->session, objects->printSettings, &url);
        [_attributes setObject: NSPrintSaveJob forKey: NSPrintJobDisposition];
        if (url != NULL) {
            [_attributes setObject: [(NSURL *) url path] forKey: NSPrintSavePath];
            CFRelease(url);
        }
    } else if ([[self jobDisposition] isEqualToString: NSPrintSaveJob]) {
        [_attributes setObject: NSPrintSpoolJob forKey: NSPrintJobDisposition];
    }
    [objects->settingsSignature release];
    objects->settingsSignature = [[self _settingsSignature] retain];
}

@end

NSPrintInfoAttributeKey const NSPrintReversePageOrder = @"NSReversePageOrder";
NSPrintInfoAttributeKey const NSPrintPagesAcross = @"NSPagesAcross";
NSPrintInfoAttributeKey const NSPrintPagesDown = @"NSPagesDown";
NSPrintInfoAttributeKey const NSPrintTime = @"NSPrintTime";
NSPrintInfoAttributeKey const NSPrintFaxNumber = @"NSFaxNumber";
NSPrintInfoAttributeKey const NSPrintJobSavingFileNameExtensionHidden = @"NSJobSavingFileNameExtensionHidden";
NSString * const NSPrintFormName = @"NSFormName";
NSString * const NSPrintJobFeatures = @"NSJobFeatures";
NSString * const NSPrintManualFeed = @"NSPrintManualFeed";
NSString * const NSPrintPagesPerSheet = @"NSPagesPerSheet";
NSString * const NSPrintPaperFeed = @"NSPaperFeed";
