// Contract: the operands written before an operator belong to that operator (PDF 32000-1 7.8.2),
// so operands its callback leaves unpopped must not be seen by the next operator. Each callback
// below pops fewer operands than it was given (or none), and the next operator must find only
// its own. Exits non-zero with the number of failed checks.
#import <Foundation/Foundation.h>
#import <Onyx2D/O2PDFContentStream.h>
#import <Onyx2D/O2PDFOperatorTable.h>
#import <Onyx2D/O2PDFScanner.h>
#import <Onyx2D/O2PDFStream.h>
#include <stdio.h>
#include <string.h>

static unsigned failures;

static void expect(const char *what, BOOL ok) {
    if (!ok) {
        fprintf(stderr, "FAIL: %s\n", what);
        failures++;
    }
}

// 1 2 3 aa: pops only the top operand.
static void opA(O2PDFScanner *scanner, void *info) {
    O2PDFReal value = -1;
    expect("aa pops 3", O2PDFScannerPopNumber(scanner, &value) && value == 3);
}

// 4 bb: pops its operand, then finds none (not the 1 and 2 aa left).
static void opB(O2PDFScanner *scanner, void *info) {
    O2PDFReal value = -1;
    expect("bb pops 4", O2PDFScannerPopNumber(scanner, &value) && value == 4);
    expect("bb finds no other operand", !O2PDFScannerPopNumber(scanner, &value));
}

// 5 6 cc: pops nothing.
static void opC(O2PDFScanner *scanner, void *info) {
}

// 7 dd: pops its operand, then finds none (not the 5 and 6 cc left).
static void opD(O2PDFScanner *scanner, void *info) {
    O2PDFReal value = -1;
    expect("dd pops 7", O2PDFScannerPopNumber(scanner, &value) && value == 7);
    expect("dd finds no other operand", !O2PDFScannerPopNumber(scanner, &value));
}

int main(void) {
    @autoreleasepool {
        const char *content = "1 2 3 aa 4 bb 5 6 cc 7 dd";
        O2PDFStream *stream = [O2PDFStream pdfStreamWithBytes:content length:(unsigned)strlen(content)];
        O2PDFContentStream *contentStream = [[[O2PDFContentStream alloc] initWithStream:stream resources:nil parent:nil] autorelease];
        O2PDFOperatorTable *table = [[[O2PDFOperatorTable alloc] init] autorelease];
        [table setCallback:opA forName:"aa"];
        [table setCallback:opB forName:"bb"];
        [table setCallback:opC forName:"cc"];
        [table setCallback:opD forName:"dd"];
        O2PDFScanner *scanner = [[[O2PDFScanner alloc] initWithContentStream:contentStream operatorTable:table info:NULL] autorelease];
        expect("scan succeeds", [scanner scan]);
        if (failures) return failures;
        puts("operands left by a callback do not reach the next operator");
    }
    return 0;
}
