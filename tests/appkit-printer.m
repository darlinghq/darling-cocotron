// Copyright (C) 2026 Lubos Dolezel
//
// NSPrinter lookups, the default printer of NSPrintInfo, and the print delegate callbacks of
// NSDocument. No display connection is needed.
#import <AppKit/AppKit.h>
#include <stdio.h>

static int failures;
#define CHECK(cond, msg) do { if (!(cond)) { printf("FAIL: %s\n", msg); failures++; } } while (0)

@interface PrintDelegate : NSObject
{
    int _calls;
    BOOL _success;
}
@property(assign) int calls;
@property(assign) BOOL success;
@end
@implementation PrintDelegate
@synthesize calls = _calls;
@synthesize success = _success;
- (void)document:(NSDocument *)doc didPrint:(BOOL)success contextInfo:(void *)info {
    self.calls++;
    self.success = success;
}
@end

@interface NoOperationDocument : NSDocument
@end
@implementation NoOperationDocument
- (NSPrintOperation *)printOperationWithSettings:(NSDictionary *)settings error:(NSError **)error {
    return nil;
}
@end

int main(void) {
    @autoreleasepool {
        NSArray *names = [NSPrinter printerNames];
        CHECK([names count] > 0, "at least one printer");
        NSPrinter *printer = [NSPrinter printerWithName:[names objectAtIndex:0]];
        CHECK(printer != nil, "printer found by its listed name");
        CHECK([[printer name] isEqualToString:[names objectAtIndex:0]], "name round trip");
        CHECK([[NSPrinter printerTypes] containsObject:[printer type]], "listed type");
        CHECK([NSPrinter printerWithName:@"darling-no-such-printer"] == nil, "unknown name gives nil");
        CHECK([NSPrinter printerWithName:nil] == nil, "nil name gives nil");
        CHECK([NSPrinter printerWithType:@"darling-no-such-type"] == nil, "unknown type gives nil");

        NSSize letter = [printer pageSizeForPaper:@"US Letter"];
        CHECK(letter.width == 612 && letter.height == 792, "US Letter is 612 x 792 points");
        NSSize a4 = [printer pageSizeForPaper:@"A4"];
        CHECK(a4.width == 595 && a4.height == 842, "A4 is 595 x 842 points");
        NSSize unknown = [printer pageSizeForPaper:@"darling-no-such-paper"];
        CHECK(unknown.width == 0 && unknown.height == 0, "unknown paper gives NSZeroSize");
        CHECK([printer languageLevel] > 0, "language level");
        CHECK([[[printer deviceDescription] objectForKey:NSDeviceIsPrinter] boolValue],
              "device description says printer");
        CHECK([[printer description] length] > 0, "NSObject methods still work (description)");

        CHECK([NSPrintInfo defaultPrinter] != nil, "default printer");
        NSPrintInfo *info = [[NSPrintInfo alloc] init];
        CHECK([info printer] != nil, "print info has a printer");
        CHECK([info printer] == [info printer], "print info keeps its printer");
        [info release];

        // The print delegate is told when there is nothing to print.
        NoOperationDocument *doc = [[NoOperationDocument alloc] init];
        PrintDelegate *delegate = [[PrintDelegate alloc] init];
        [doc printDocumentWithSettings:@{}
                        showPrintPanel:NO
                              delegate:delegate
                      didPrintSelector:@selector(document:didPrint:contextInfo:)
                           contextInfo:NULL];
        CHECK(delegate.calls == 1 && !delegate.success, "delegate called with NO when there is no operation");
        [doc release];
        [delegate release];
    }
    if (failures == 0)
        printf("PASS\n");
    return failures ? 1 : 0;
}
