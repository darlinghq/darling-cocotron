// Contract: Apple CoreGraphics documentation for CGPDFScanner, CGPDFOperatorTable and
// CGPDFContentStream (https://developer.apple.com/documentation/coregraphics): only the operators
// that have a registered callback invoke anything (CGPDFScannerScan), the others are passed over
// with their operands. From PDF 32000-1 7.8.2, the operands written before an operator are that
// operator's, and the content streams of a page are read as one. The expected values come from
// those, and from the operand stack (operands are popped from the top, so in reverse order of
// writing), not from observation of macOS.
// Exit codes: the first failing check of a callback is reported as its own code (100 and up);
// 10 to 99 identify the failing check of main. What the documentation leaves open (a NULL
// argument, what a failed pop leaves on the stack) is listed under GUESS in the commit message
// and is only checked here where marked.
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#include <stdarg.h>
#include <stdio.h>
#include <string.h>

static void append(NSMutableData *data, const char *format, ...) {
    char buffer[1024];
    va_list arguments;
    va_start(arguments, format);
    int length = vsnprintf(buffer, sizeof(buffer), format, arguments);
    va_end(arguments);
    [data appendBytes:buffer length:length];
}

// A one-page document whose page has the content stream 4 (and, when `second` is not NULL, the
// content stream 5 after it, with `dangling` a reference to an object that does not exist between
// them) and whose Info dictionary holds a resource dictionary and a reference to the stream 4, so
// the stream can be reached through the public API.
static CGPDFDocumentRef makeDocument(const char *first, const char *second, bool dangling) {
    NSMutableData *data = [NSMutableData data];
    NSUInteger offsets[6];
    append(data, "%%PDF-1.4\n");
    offsets[0] = [data length];
    append(data, "1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n");
    offsets[1] = [data length];
    append(data, "2 0 obj\n<< /Type /Pages /Kids [3 0 R] /Count 1 >>\nendobj\n");
    offsets[2] = [data length];
    append(data, "3 0 obj\n<< /Type /Page /Parent 2 0 R /MediaBox [0 0 20 20] /Contents %s >>\nendobj\n",
           second ? (dangling ? "[4 0 R 99 0 R 5 0 R]" : "[4 0 R 5 0 R]") : "4 0 R");
    offsets[3] = [data length];
    append(data, "4 0 obj\n<< /Length %zu >>\nstream\n%s\nendstream\nendobj\n", strlen(first), first);
    offsets[4] = [data length];
    if (!second) second = "";
    append(data, "5 0 obj\n<< /Length %zu >>\nstream\n%s\nendstream\nendobj\n", strlen(second), second);
    offsets[5] = [data length];
    append(data, "6 0 obj\n<< /Res << /K 1 >> /Cs 4 0 R >>\nendobj\n");
    NSUInteger xref = [data length];
    append(data, "xref\n0 7\n0000000000 65535 f \n");
    for (int i = 0; i < 6; i++)
        append(data, "%010lu 00000 n \n", (unsigned long)offsets[i]);
    append(data, "trailer\n<< /Size 7 /Root 1 0 R /Info 6 0 R >>\nstartxref\n%lu\n%%%%EOF\n", (unsigned long)xref);

    CGDataProviderRef provider = CGDataProviderCreateWithCFData((CFDataRef)data);
    CGPDFDocumentRef document = CGPDFDocumentCreateWithProvider(provider);
    CGDataProviderRelease(provider);
    return document;
}

struct State {
    const char *log[32];
    int count;
    int failure;
    CGPDFContentStreamRef cs;
};

static void expect_ok(struct State *state, int code, bool ok) {
    if (!ok && !state->failure)
        state->failure = code;
}

// Every callback gets the info pointer given to CGPDFScannerCreate and a scanner whose content
// stream is the one it was created with.
static struct State *begin(CGPDFScannerRef scanner, void *info, const char *name) {
    struct State *state = info;
    if (state->count < 32)
        state->log[state->count] = name;
    state->count++;
    expect_ok(state, 100, CGPDFScannerGetContentStream(scanner) == state->cs);
    return state;
}

// Empties the operand stack, whatever a failed pop did with its operand.
static void drain(CGPDFScannerRef scanner) {
    CGPDFObjectRef object;
    while (CGPDFScannerPopObject(scanner, &object))
        ;
}

static void opQ(CGPDFScannerRef scanner, void *info) {
    begin(scanner, info, "q");
}

static void opRestore(CGPDFScannerRef scanner, void *info) {
    begin(scanner, info, "Q");
}

static void opFill(CGPDFScannerRef scanner, void *info) {
    begin(scanner, info, "f");
}

// 0.25 0.5 0.75 rg: the operands come out last to first.
static void opRg(CGPDFScannerRef scanner, void *info) {
    struct State *state = begin(scanner, info, "rg");
    CGPDFReal blue = -1, green = -1, red = -1, extra = 42;
    expect_ok(state, 110, CGPDFScannerPopNumber(scanner, &blue) && blue == 0.75);
    expect_ok(state, 111, CGPDFScannerPopNumber(scanner, &green) && green == 0.5);
    expect_ok(state, 112, CGPDFScannerPopNumber(scanner, &red) && red == 0.25);
    expect_ok(state, 113, !CGPDFScannerPopNumber(scanner, &extra) && extra == 42);
}

// 10 20 30 40 re: integers read as numbers, and as integers.
static void opRect(CGPDFScannerRef scanner, void *info) {
    struct State *state = begin(scanner, info, "re");
    CGPDFReal height = -1, width = -1;
    CGPDFInteger y = -1, x = -1;
    expect_ok(state, 120, CGPDFScannerPopNumber(scanner, &height) && height == 40);
    expect_ok(state, 121, CGPDFScannerPopNumber(scanner, &width) && width == 30);
    expect_ok(state, 122, CGPDFScannerPopInteger(scanner, &y) && y == 20);
    expect_ok(state, 123, CGPDFScannerPopInteger(scanner, &x) && x == 10);
}

// /F1 12 Tf: a number, then a name.
static void opFont(CGPDFScannerRef scanner, void *info) {
    struct State *state = begin(scanner, info, "Tf");
    CGPDFReal size = -1;
    const char *name = NULL;
    expect_ok(state, 130, CGPDFScannerPopNumber(scanner, &size) && size == 12);
    expect_ok(state, 131, CGPDFScannerPopName(scanner, &name) && name && strcmp(name, "F1") == 0);
}

// <00FF41> Tj: the bytes of a string, which are not text.
static void opShow(CGPDFScannerRef scanner, void *info) {
    struct State *state = begin(scanner, info, "Tj");
    CGPDFStringRef string = NULL;
    expect_ok(state, 140, CGPDFScannerPopString(scanner, &string) && string);
    if (!string) return;
    const unsigned char expected[] = {0x00, 0xFF, 0x41};
    expect_ok(state, 141, CGPDFStringGetLength(string) == 3);
    expect_ok(state, 142, CGPDFStringGetBytePtr(string) && memcmp(CGPDFStringGetBytePtr(string), expected, 3) == 0);
}

// [(A) -120 (B)] TJ
static void opShowArray(CGPDFScannerRef scanner, void *info) {
    struct State *state = begin(scanner, info, "TJ");
    CGPDFArrayRef array = NULL;
    expect_ok(state, 150, CGPDFScannerPopArray(scanner, &array) && array);
    if (!array) return;
    expect_ok(state, 151, CGPDFArrayGetCount(array) == 3);
    CGPDFStringRef string = NULL;
    CGPDFReal adjust = 0;
    expect_ok(state, 152, CGPDFArrayGetString(array, 0, &string) && CGPDFStringGetLength(string) == 1 &&
                          CGPDFStringGetBytePtr(string)[0] == 'A');
    expect_ok(state, 153, CGPDFArrayGetNumber(array, 1, &adjust) && adjust == -120);
    expect_ok(state, 154, CGPDFArrayGetString(array, 2, &string) && CGPDFStringGetBytePtr(string)[0] == 'B');
}

// /Span << /MCID 3 >> BDC: a dictionary, then a name.
static void opBeginMarked(CGPDFScannerRef scanner, void *info) {
    struct State *state = begin(scanner, info, "BDC");
    CGPDFDictionaryRef properties = NULL;
    CGPDFInteger identifier = -1;
    const char *tag = NULL;
    expect_ok(state, 160, CGPDFScannerPopDictionary(scanner, &properties) && properties);
    expect_ok(state, 161, properties && CGPDFDictionaryGetInteger(properties, "MCID", &identifier) && identifier == 3);
    expect_ok(state, 162, CGPDFScannerPopName(scanner, &tag) && tag && strcmp(tag, "Span") == 0);
}

// /N true 7 mm: an integer, a Boolean, and then a pop of the wrong type, which fails and leaves
// its output alone.
static void opMixed(CGPDFScannerRef scanner, void *info) {
    struct State *state = begin(scanner, info, "mm");
    CGPDFInteger integer = -1, wrong = 123;
    CGPDFBoolean boolean = 9;
    expect_ok(state, 170, CGPDFScannerPopInteger(scanner, &integer) && integer == 7);
    expect_ok(state, 171, CGPDFScannerPopBoolean(scanner, &boolean) && boolean == 1);
    expect_ok(state, 172, !CGPDFScannerPopInteger(scanner, &wrong) && wrong == 123);
    drain(scanner);
}

// 7 nn: the output pointer is optional (the documentation marks it nullable).
static void opNoOutput(CGPDFScannerRef scanner, void *info) {
    struct State *state = begin(scanner, info, "nn");
    expect_ok(state, 180, CGPDFScannerPopInteger(scanner, NULL));
}

// (s) oo: any operand pops as an object.
static void opObject(CGPDFScannerRef scanner, void *info) {
    struct State *state = begin(scanner, info, "oo");
    CGPDFObjectRef object = NULL;
    expect_ok(state, 190, CGPDFScannerPopObject(scanner, &object) && object);
    expect_ok(state, 191, !CGPDFScannerPopObject(scanner, &object));
}

// false bf: a false Boolean pops as 0 (the output starts as 9).
static void opFalse(CGPDFScannerRef scanner, void *info) {
    struct State *state = begin(scanner, info, "bf");
    CGPDFBoolean boolean = 9;
    expect_ok(state, 230, CGPDFScannerPopBoolean(scanner, &boolean) && boolean == 0);
}

// << /A 1 >> ss: a dictionary is not a stream, so the pop fails and leaves its output alone. (A
// stream cannot be an operand of a content stream, so a successful PopStream cannot be reached
// from a content stream; the same pop of the other types is checked above.)
static void opNotStream(CGPDFScannerRef scanner, void *info) {
    struct State *state = begin(scanner, info, "ss");
    CGPDFStreamRef stream = (CGPDFStreamRef)state;
    expect_ok(state, 235, !CGPDFScannerPopStream(scanner, &stream) && stream == (CGPDFStreamRef)state);
}

// 1 2 3 pf: pops only the top operand and leaves the other two unpopped.
static void opPopOne(CGPDFScannerRef scanner, void *info) {
    struct State *state = begin(scanner, info, "pf");
    CGPDFReal real = -1;
    expect_ok(state, 240, CGPDFScannerPopNumber(scanner, &real) && real == 3);
}

// 4 pg: finds its own operand and none of the two pf left.
static void opOwnOperands(CGPDFScannerRef scanner, void *info) {
    struct State *state = begin(scanner, info, "pg");
    CGPDFReal real = -1, extra = 42;
    expect_ok(state, 241, CGPDFScannerPopNumber(scanner, &real) && real == 4);
    expect_ok(state, 242, !CGPDFScannerPopNumber(scanner, &extra) && extra == 42);
}

// No operands: every pop fails and none writes its output.
static void opEmpty(CGPDFScannerRef scanner, void *info) {
    struct State *state = begin(scanner, info, "ee");
    CGPDFObjectRef object = (CGPDFObjectRef)state;
    CGPDFBoolean boolean = 9;
    CGPDFInteger integer = 9;
    CGPDFReal real = 9;
    const char *name = (const char *)state;
    CGPDFStringRef string = (CGPDFStringRef)state;
    CGPDFArrayRef array = (CGPDFArrayRef)state;
    CGPDFDictionaryRef dictionary = (CGPDFDictionaryRef)state;
    CGPDFStreamRef stream = (CGPDFStreamRef)state;
    expect_ok(state, 200, !CGPDFScannerPopObject(scanner, &object) && object == (CGPDFObjectRef)state);
    expect_ok(state, 201, !CGPDFScannerPopBoolean(scanner, &boolean) && boolean == 9);
    expect_ok(state, 202, !CGPDFScannerPopInteger(scanner, &integer) && integer == 9);
    expect_ok(state, 203, !CGPDFScannerPopNumber(scanner, &real) && real == 9);
    expect_ok(state, 204, !CGPDFScannerPopName(scanner, &name) && name == (const char *)state);
    expect_ok(state, 205, !CGPDFScannerPopString(scanner, &string) && string == (CGPDFStringRef)state);
    expect_ok(state, 206, !CGPDFScannerPopArray(scanner, &array) && array == (CGPDFArrayRef)state);
    expect_ok(state, 207, !CGPDFScannerPopDictionary(scanner, &dictionary) && dictionary == (CGPDFDictionaryRef)state);
    expect_ok(state, 208, !CGPDFScannerPopStream(scanner, &stream) && stream == (CGPDFStreamRef)state);
}

// (s) ww: a string is not a number, so the pop fails and leaves its output alone.
static void opWrongType(CGPDFScannerRef scanner, void *info) {
    struct State *state = begin(scanner, info, "ww");
    CGPDFReal real = 5;
    expect_ok(state, 210, !CGPDFScannerPopNumber(scanner, &real) && real == 5);
    drain(scanner);
}

// 9 qq: after the unknown operator ZZ in the stream, only the operand written after it is left.
static void opAfterUnknown(CGPDFScannerRef scanner, void *info) {
    struct State *state = begin(scanner, info, "qq");
    CGPDFReal real = -1, extra = 42;
    expect_ok(state, 220, CGPDFScannerPopNumber(scanner, &real) && real == 9);
    expect_ok(state, 221, !CGPDFScannerPopNumber(scanner, &extra) && extra == 42);
}

static const char *mainContent =
    "q 0.25 0.5 0.75 rg 10 20 30 40 re f Q\n"
    "/F1 12 Tf <00FF41> Tj [(A) -120 (B)] TJ /Span << /MCID 3 >> BDC\n"
    "/N true 7 mm 7 nn (s) oo ee (s) ww false bf << /A 1 >> ss\n"
    "1 2 3 pf 4 pg\n"
    "1 2 3 ZZ 9 qq\n";

static const char *mainLog[] = {"q", "rg", "re", "f", "Q", "Tf", "Tj", "TJ", "BDC", "mm", "nn", "oo", "ee", "ww", "bf", "ss", "pf", "pg", "qq"};
#define MAIN_COUNT ((int)(sizeof(mainLog) / sizeof(mainLog[0])))

static CGPDFOperatorTableRef makeTable(void) {
    CGPDFOperatorTableRef table = CGPDFOperatorTableCreate();
    CGPDFOperatorTableSetCallback(table, "q", opQ);
    CGPDFOperatorTableSetCallback(table, "Q", opRestore);
    CGPDFOperatorTableSetCallback(table, "f", opFill);
    CGPDFOperatorTableSetCallback(table, "rg", opRg);
    CGPDFOperatorTableSetCallback(table, "re", opRect);
    CGPDFOperatorTableSetCallback(table, "Tf", opFont);
    CGPDFOperatorTableSetCallback(table, "Tj", opShow);
    CGPDFOperatorTableSetCallback(table, "TJ", opShowArray);
    CGPDFOperatorTableSetCallback(table, "BDC", opBeginMarked);
    CGPDFOperatorTableSetCallback(table, "mm", opMixed);
    CGPDFOperatorTableSetCallback(table, "nn", opNoOutput);
    CGPDFOperatorTableSetCallback(table, "oo", opObject);
    CGPDFOperatorTableSetCallback(table, "ee", opEmpty);
    CGPDFOperatorTableSetCallback(table, "ww", opWrongType);
    CGPDFOperatorTableSetCallback(table, "bf", opFalse);
    CGPDFOperatorTableSetCallback(table, "ss", opNotStream);
    CGPDFOperatorTableSetCallback(table, "pf", opPopOne);
    CGPDFOperatorTableSetCallback(table, "pg", opOwnOperands);
    CGPDFOperatorTableSetCallback(table, "qq", opAfterUnknown);
    return table;
}

// Scans `cs` with the full table and reports whether it parsed and the operators it called.
static bool scan(CGPDFContentStreamRef cs, CGPDFOperatorTableRef table, struct State *state, bool *parsed) {
    memset(state, 0, sizeof(*state));
    state->cs = cs;
    CGPDFScannerRef scanner = CGPDFScannerCreate(cs, table, state);
    if (!scanner)
        return false;
    // Retain returns the same scanner, which then needs two releases.
    CGPDFScannerRef retained = CGPDFScannerRetain(scanner);
    *parsed = retained == scanner && CGPDFScannerScan(scanner);
    CGPDFScannerRelease(retained);
    CGPDFScannerRelease(scanner);
    return true;
}

static bool logIs(const struct State *state, const char **expected, int count) {
    if (state->count != count)
        return false;
    for (int i = 0; i < count; i++)
        if (strcmp(state->log[i], expected[i]) != 0)
            return false;
    return true;
}

int main(void) {
    @autoreleasepool {
        CGPDFOperatorTableRef table = makeTable();
        // Retain returns the same table; one release then leaves the original reference.
        if (CGPDFOperatorTableRetain(table) != table) return 9;
        CGPDFOperatorTableRelease(table);
        struct State state;
        bool parsed = false;

        // A page with one content stream: every operator reaches its callback, in order, with
        // the info pointer, and each callback sees the operands of its own operator.
        CGPDFDocumentRef document = makeDocument(mainContent, NULL, false);
        CGPDFPageRef page = document ? CGPDFDocumentGetPage(document, 1) : NULL;
        if (!page) return 10;
        CGPDFContentStreamRef cs = CGPDFContentStreamCreateWithPage(page);
        if (!cs) return 11;
        if (!scan(cs, table, &state, &parsed) || !parsed) return 12;
        if (state.failure) return state.failure;
        if (!logIs(&state, mainLog, MAIN_COUNT)) return 13;

        CFArrayRef streams = CGPDFContentStreamGetStreams(cs);
        if (!streams || CFArrayGetCount(streams) != 1) return 14;

        // The same stream reached through the public readers and made a content stream of its own.
        CGPDFDictionaryRef info = CGPDFDocumentGetInfo(document);
        CGPDFStreamRef formStream = NULL;
        CGPDFDictionaryRef resources = NULL;
        if (!info || !CGPDFDictionaryGetStream(info, "Cs", &formStream) || !formStream) return 15;
        if (!CGPDFDictionaryGetDictionary(info, "Res", &resources) || !resources) return 16;
        CGPDFContentStreamRef form = CGPDFContentStreamCreateWithStream(formStream, resources, NULL);
        if (!form) return 17;
        if (!scan(form, table, &state, &parsed) || !parsed) return 18;
        if (state.failure) return state.failure;
        if (!logIs(&state, mainLog, MAIN_COUNT)) return 19;

        // Resources are looked up in the stream's own resource dictionary, then in its parent's.
        // The parent's resources are the Info dictionary, whose entry Res is a dictionary with the
        // entry K (category Res, name K); the child's resources, << /K 1 >>, have no category Res.
        CGPDFContentStreamRef parent = CGPDFContentStreamCreateWithStream(formStream, info, NULL);
        CGPDFContentStreamRef child = CGPDFContentStreamCreateWithStream(formStream, resources, parent);
        if (!parent || !child) return 20;
        CGPDFDictionaryRef categoryDictionary = NULL;
        CGPDFObjectRef expected = NULL;
        if (!CGPDFDictionaryGetDictionary(info, "Res", &categoryDictionary) ||
            !CGPDFDictionaryGetObject(categoryDictionary, "K", &expected) || !expected) return 21;
        if (CGPDFContentStreamGetResource(parent, "Res", "K") != expected) return 22;
        if (CGPDFContentStreamGetResource(child, "Res", "K") != expected) return 23;
        if (CGPDFContentStreamGetResource(child, "Res", "Missing") != NULL) return 24;
        if (CGPDFContentStreamGetResource(child, "Missing", "K") != NULL) return 25;
        // Retain and release balance, and the content stream outlives the extra reference.
        if (CGPDFContentStreamRetain(child) != child) return 26;
        CGPDFContentStreamRelease(child);
        CGPDFContentStreamRelease(child);
        CGPDFContentStreamRelease(parent);
        CGPDFContentStreamRelease(form);

        // A scanner created without a table calls nothing, and still parses the stream.
        if (!scan(cs, NULL, &state, &parsed) || !parsed || state.count != 0) return 30;
        CGPDFContentStreamRelease(cs);
        CGPDFDocumentRelease(document);

        // Two content streams make one stream of operators; GetStreams gives both, as streams.
        document = makeDocument("q 0.25 0.5 0.75 rg", "10 20 30 40 re f Q", false);
        page = document ? CGPDFDocumentGetPage(document, 1) : NULL;
        if (!page) return 40;
        cs = CGPDFContentStreamCreateWithPage(page);
        if (!cs) return 41;
        streams = CGPDFContentStreamGetStreams(cs);
        if (!streams || CFArrayGetCount(streams) != 2) return 42;
        for (CFIndex i = 0; i < 2; i++) {
            CGPDFStreamRef element = (CGPDFStreamRef)CFArrayGetValueAtIndex(streams, i);
            CGPDFInteger length = -1;
            CGPDFDictionaryRef dictionary = element ? CGPDFStreamGetDictionary(element) : NULL;
            if (!dictionary || !CGPDFDictionaryGetInteger(dictionary, "Length", &length)) return 43;
            if (length != 18) return 44;
        }
        if (!scan(cs, table, &state, &parsed) || !parsed || state.failure) return 45;
        if (!logIs(&state, mainLog, 5)) return 46;
        CGPDFContentStreamRelease(cs);
        CGPDFDocumentRelease(document);

        // An operator's operands may be in one content stream and the operator in the next.
        document = makeDocument("q 0.25 0.5", "0.75 rg 10 20 30 40 re f Q", false);
        page = document ? CGPDFDocumentGetPage(document, 1) : NULL;
        cs = page ? CGPDFContentStreamCreateWithPage(page) : NULL;
        if (!cs) return 47;
        if (!scan(cs, table, &state, &parsed) || !parsed || state.failure) return 48;
        if (!logIs(&state, mainLog, 5)) return 49;
        CGPDFContentStreamRelease(cs);
        CGPDFDocumentRelease(document);

        // An entry of /Contents that refers to an object that does not exist is not a content
        // stream: GetStreams leaves it out, and the scan reads the streams around it.
        document = makeDocument("q 0.25 0.5 0.75 rg", "10 20 30 40 re f Q", true);
        page = document ? CGPDFDocumentGetPage(document, 1) : NULL;
        cs = page ? CGPDFContentStreamCreateWithPage(page) : NULL;
        if (!cs) return 70;
        streams = CGPDFContentStreamGetStreams(cs);
        if (!streams || CFArrayGetCount(streams) != 2) return 71;
        for (CFIndex i = 0; i < 2; i++) {
            CGPDFStreamRef element = (CGPDFStreamRef)CFArrayGetValueAtIndex(streams, i);
            if (!element || !CGPDFStreamGetDictionary(element)) return 72;
        }
        if (!scan(cs, table, &state, &parsed) || !parsed || state.failure) return 73;
        if (!logIs(&state, mainLog, 5)) return 74;
        CGPDFContentStreamRelease(cs);
        CGPDFDocumentRelease(document);

        // An empty content stream parses and calls nothing.
        document = makeDocument("", NULL, false);
        page = document ? CGPDFDocumentGetPage(document, 1) : NULL;
        cs = page ? CGPDFContentStreamCreateWithPage(page) : NULL;
        if (!cs) return 50;
        if (!scan(cs, table, &state, &parsed) || !parsed || state.count != 0) return 51;
        CGPDFContentStreamRelease(cs);
        CGPDFDocumentRelease(document);

        // A stream that cannot be parsed (an array that is never closed) fails the scan.
        document = makeDocument("q [ 1 2", NULL, false);
        page = document ? CGPDFDocumentGetPage(document, 1) : NULL;
        cs = page ? CGPDFContentStreamCreateWithPage(page) : NULL;
        if (!cs) return 55;
        if (!scan(cs, table, &state, &parsed) || parsed) return 56;
        CGPDFContentStreamRelease(cs);
        CGPDFDocumentRelease(document);

        // CGPDFStringGetBytePtr and CGPDFStringGetLength: NULL gives NULL and 0 (documented).
        if (CGPDFStringGetBytePtr(NULL) != NULL || CGPDFStringGetLength(NULL) != 0) return 60;

        // GUESS (not specified by the documentation): a NULL scanner or operator table argument
        // does nothing and a pop from a NULL scanner fails, rather than crashing.
        CGPDFObjectRef object = NULL;
        CGPDFReal real = 1;
        if (CGPDFScannerScan(NULL) || CGPDFScannerGetContentStream(NULL) != NULL) return 61;
        if (CGPDFScannerPopObject(NULL, &object) || CGPDFScannerPopNumber(NULL, &real)) return 62;
        CGPDFOperatorTableSetCallback(NULL, "q", opQ);
        CGPDFOperatorTableSetCallback(table, NULL, opQ);

        CGPDFOperatorTableRelease(table);
    }
    puts("PDF scanner, operator table and content stream behave as documented");
    return 0;
}
