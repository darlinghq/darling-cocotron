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

#import <AppKit/AppKitExport.h>
#import <Foundation/NSGeometry.h>
#import <Foundation/NSObject.h>

@class NSDictionary, NSMutableDictionary, NSPrinter;

typedef enum NSPrintingPaginationMode : int {
    NSPrintingPaginationModeAutomatic,
    NSPrintingPaginationModeFit,
    NSPrintingPaginationModeClip,
} NSPrintingPaginationMode;

APPKIT_EXPORT const NSPrintingPaginationMode NSFitPagination;
APPKIT_EXPORT const NSPrintingPaginationMode NSAutoPagination;
APPKIT_EXPORT const NSPrintingPaginationMode NSClipPagination;

typedef enum {
    NSPortraitOrientation,
    NSLandscapeOrientation,
} NSPrintingOrientation;

typedef NSString *NSPrintInfoAttributeKey;

/* Page Setup */
APPKIT_EXPORT NSPrintInfoAttributeKey const NSPrintPaperName;
APPKIT_EXPORT NSPrintInfoAttributeKey const NSPrintPaperSize;
APPKIT_EXPORT NSPrintInfoAttributeKey const NSPrintOrientation;

/* Pagination */
APPKIT_EXPORT NSPrintInfoAttributeKey const NSPrintLeftMargin;
APPKIT_EXPORT NSPrintInfoAttributeKey const NSPrintRightMargin;
APPKIT_EXPORT NSPrintInfoAttributeKey const NSPrintTopMargin;
APPKIT_EXPORT NSPrintInfoAttributeKey const NSPrintBottomMargin;
APPKIT_EXPORT NSPrintInfoAttributeKey const NSPrintHorizontallyCentered;
APPKIT_EXPORT NSPrintInfoAttributeKey const NSPrintVerticallyCentered;
APPKIT_EXPORT NSPrintInfoAttributeKey const NSPrintHorizontalPagination;
APPKIT_EXPORT NSPrintInfoAttributeKey const NSPrintVerticalPagination;

/* Other */
APPKIT_EXPORT NSPrintInfoAttributeKey const NSPrintAllPages;
APPKIT_EXPORT NSPrintInfoAttributeKey const NSPrintCopies;
APPKIT_EXPORT NSPrintInfoAttributeKey const NSPrintDetailedErrorReporting;
APPKIT_EXPORT NSPrintInfoAttributeKey const NSPrintFirstPage;
APPKIT_EXPORT NSPrintInfoAttributeKey const NSPrintHeaderAndFooter;
APPKIT_EXPORT NSPrintInfoAttributeKey const NSPrintJobDisposition;
APPKIT_EXPORT NSPrintInfoAttributeKey const NSPrintJobSavingURL;
APPKIT_EXPORT NSPrintInfoAttributeKey const NSPrintLastPage;
APPKIT_EXPORT NSPrintInfoAttributeKey const NSPrintMustCollate;
APPKIT_EXPORT NSPrintInfoAttributeKey const NSPrintPrinter;
APPKIT_EXPORT NSPrintInfoAttributeKey const NSPrintPrinterName;
APPKIT_EXPORT NSPrintInfoAttributeKey const NSPrintSelectionOnly;

typedef NSString *NSPrintJobDispositionValue;

APPKIT_EXPORT NSPrintJobDispositionValue const NSPrintSpoolJob;
APPKIT_EXPORT NSPrintJobDispositionValue const NSPrintPreviewJob;
APPKIT_EXPORT NSPrintJobDispositionValue const NSPrintSaveJob;
APPKIT_EXPORT NSPrintJobDispositionValue const NSPrintCancelJob;

APPKIT_EXPORT NSString *const NSPrintSavePath;

@interface NSPrintInfo : NSObject <NSCopying> {
    NSMutableDictionary *_attributes;
}

+ (NSPrintInfo *) sharedPrintInfo;

- initWithDictionary: (NSDictionary *) dictionary;

- (NSMutableDictionary *) dictionary;

- (NSPrinter *) printer;
- (NSString *) jobDisposition;

- (NSString *) paperName;
- (NSSize) paperSize;
- (NSPrintingOrientation) orientation;

- (NSPrintingPaginationMode) horizontalPagination;
- (NSPrintingPaginationMode) verticalPagination;

- (CGFloat) topMargin;
- (CGFloat) bottomMargin;
- (CGFloat) leftMargin;
- (CGFloat) rightMargin;

- (BOOL) isHorizontallyCentered;
- (BOOL) isVerticallyCentered;

- (NSString *) localizedPaperName;
- (NSRect) imageablePageBounds;

- (void) setPrinter: (NSPrinter *) printer;
- (void) setJobDisposition: (NSString *) value;

- (void) setPaperName: (NSString *) value;
- (void) setPaperSize: (NSSize) value;
- (void) setOrientation: (NSPrintingOrientation) value;

- (void) setHorizontalPagination: (NSPrintingPaginationMode) value;
- (void) setVerticalPagination: (NSPrintingPaginationMode) value;

- (void) setTopMargin: (CGFloat) value;
- (void) setBottomMargin: (CGFloat) value;
- (void) setLeftMargin: (CGFloat) value;
- (void) setRightMargin: (CGFloat) value;

- (void) setHorizontallyCentered: (BOOL) value;
- (void) setVerticallyCentered: (BOOL) value;

- (void) setUpPrintOperationDefaultValues;

@end
