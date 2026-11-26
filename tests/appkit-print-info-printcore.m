// Copyright (C) 2026 Lubos Dolezel
//
// NSPrintInfo on top of PrintCore: -PMPrintSession, -PMPageFormat and -PMPrintSettings are PrintCore
// objects that have the page setup and the print settings of the print info (and are not NULL), what
// the print info is set to shows in them, and what is set in them shows in the print info after
// -updateFromPMPageFormat and -updateFromPMPrintSettings. No display connection is needed.
#import <AppKit/AppKit.h>
#import <ApplicationServices/ApplicationServices.h>
#include <stdio.h>

static int failures;
#define CHECK(cond, msg) do { if (!(cond)) { printf("FAIL: %s\n", msg); failures++; } } while (0)

int main(void) {
    @autoreleasepool {
        NSPrintInfo *info = [[[NSPrintInfo alloc] init] autorelease];
        PMPrintSession session = [info PMPrintSession];
        PMPageFormat format = [info PMPageFormat];
        PMPrintSettings settings = [info PMPrintSettings];
        PMRect rect;
        PMOrientation orientation = 0;
        double scale = 0;
        UInt32 copies = 0;

        CHECK(session != NULL && format != NULL && settings != NULL, "the objects exist");
        CHECK([info PMPageFormat] == format && [info PMPrintSession] == session, "the objects are kept");

        // the default of a print info is US Letter, which a page format has the paper of
        CHECK(PMGetUnadjustedPageRect(format, &rect) == noErr && rect.right == 576 && rect.bottom == 734,
              "the page of a Letter paper has its margins");
        CHECK(PMGetOrientation(format, &orientation) == noErr && orientation == kPMPortrait, "portrait");
        CHECK(PMGetScale(format, &scale) == noErr && scale == 100, "scale 100");

        // what the print info is set to shows in the objects
        [info setPaperSize: NSMakeSize(595, 842)];
        [info setOrientation: NSLandscapeOrientation];
        [info setScalingFactor: 0.5];
        format = [info PMPageFormat];
        CHECK(PMGetOrientation(format, &orientation) == noErr && orientation == kPMLandscape, "landscape");
        CHECK(PMGetScale(format, &scale) == noErr && scale == 50, "scale 50");
        CHECK(PMGetUnadjustedPaperRect(format, &rect) == noErr && rect.bottom == 824 && rect.right == 577, "the A4 paper");
        CHECK(PMGetAdjustedPageRect(format, &rect) == noErr && rect.right == 1566 && rect.bottom == 1118,
              "the page is landscape and in the units of a half scale");
        PMPaper paper = NULL;
        double width = 0;
        CHECK(PMGetPageFormatPaper(format, &paper) == noErr && PMPaperGetWidth(paper, &width) == noErr && width == 595, "the paper");

        // a custom paper size
        [info setPaperSize: NSMakeSize(300, 400)];
        [info setOrientation: NSPortraitOrientation];
        format = [info PMPageFormat];
        CHECK(PMGetPageFormatPaper(format, &paper) == noErr && PMPaperIsCustom(paper) && PMPaperGetWidth(paper, &width) == noErr && width == 300,
              "a paper that the printer does not have is a custom paper");

        // what is set in the objects shows in the print info after the update
        PMPrinter printer = NULL;
        CFArrayRef papers = NULL;
        CHECK(PMSessionGetCurrentPrinter(session, &printer) == noErr && PMPrinterGetPaperList(printer, &papers) == noErr, "the papers");
        PMPageFormat a3Format = NULL;
        CHECK(PMCreatePageFormatWithPMPaper(&a3Format, (PMPaper) CFArrayGetValueAtIndex(papers, 9)) == noErr, "the A3 format");
        CHECK(PMCopyPageFormat(a3Format, [info PMPageFormat]) == noErr, "copy the format in");
        PMSetOrientation([info PMPageFormat], kPMLandscape, false);
        PMSetScale([info PMPageFormat], 200);
        [info updateFromPMPageFormat];
        CHECK([info paperSize].width == 842 && [info paperSize].height == 1191, "the paper size of the objects");
        CHECK([[info paperName] isEqualToString: @"A3"], "the paper name");
        CHECK([info orientation] == NSLandscapeOrientation, "the orientation of the objects");
        CHECK([info scalingFactor] == 2.0, "the scale of the objects");
        PMRelease(a3Format);

        // the print settings
        [[info dictionary] setObject: [NSNumber numberWithInt: 4] forKey: NSPrintCopies];
        [[info dictionary] setObject: [NSNumber numberWithBool: NO] forKey: NSPrintAllPages];
        [[info dictionary] setObject: [NSNumber numberWithInt: 2] forKey: NSPrintFirstPage];
        [[info dictionary] setObject: [NSNumber numberWithInt: 3] forKey: NSPrintLastPage];
        settings = [info PMPrintSettings];
        UInt32 first = 0, last = 0;
        CHECK(PMGetCopies(settings, &copies) == noErr && copies == 4, "the copies");
        CHECK(PMGetFirstPage(settings, &first) == noErr && first == 2 && PMGetLastPage(settings, &last) == noErr && last == 3, "the pages");
        PMDestinationType destination = 0;
        CHECK(PMSessionGetDestinationType(session, settings, &destination) == noErr && destination == kPMDestinationPrinter,
              "the destination is a printer");
        NSString *path = @"/tmp/appkit-print-info-printcore.pdf";
        [info setJobDisposition: NSPrintSaveJob];
        [[info dictionary] setObject: path forKey: NSPrintSavePath];
        settings = [info PMPrintSettings];
        CFURLRef url = NULL;
        CHECK(PMSessionGetDestinationType(session, settings, &destination) == noErr && destination == kPMDestinationFile, "the destination is a file");
        CHECK(PMSessionCopyDestinationLocation(session, settings, &url) == noErr && url && [[(NSURL *) url path] isEqualToString: path], "the file");
        if (url)
            CFRelease(url);

        PMSetCopies(settings, 7, false);
        PMSetFirstPage(settings, 1, false);
        PMSetLastPage(settings, kPMPrintAllPages, false);
        PMSessionSetDestination(session, settings, kPMDestinationPrinter, NULL, NULL);
        [info updateFromPMPrintSettings];
        CHECK([[[info dictionary] objectForKey: NSPrintCopies] intValue] == 7, "the copies of the objects");
        CHECK([[[info dictionary] objectForKey: NSPrintAllPages] boolValue], "all pages");
        CHECK([[info jobDisposition] isEqualToString: NSPrintSpoolJob], "the job goes to a printer");

        // a copy of a print info has objects of its own
        NSPrintInfo *copy = [[info copy] autorelease];
        CHECK([copy PMPageFormat] != [info PMPageFormat], "the copy has a page format of its own");
        CHECK([copy paperSize].width == [info paperSize].width, "the copy has the paper");
    }
    printf(failures ? "FAIL appkit-print-info-printcore\n" : "PASS appkit-print-info-printcore\n");
    return failures != 0;
}
