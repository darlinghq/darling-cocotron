#include <CoreFoundation/CoreFoundation.h>
#include <CoreGraphics/CoreGraphics.h>
#include <stdarg.h>
#include <stdio.h>

// CGPDFDocumentIsEncrypted is true when the trailer has an /Encrypt dictionary.
// A document that is not encrypted is unlocked. One encrypted with a non-empty user
// password is locked until CGPDFDocumentUnlockWithPassword succeeds.
// The encrypted document uses the standard security handler, revision 2 (40-bit RC4),
// user password "secret", owner password "owner", P = -4 and the first file identifier
// 00 01 .. 0F; /O and /U were computed with Algorithms 3 and 4 of PDF 32000-1 7.6.3.4.
// The pages hold no strings or streams, so nothing else needs encrypting.
// Exits non-zero on failure.

static void append(CFMutableDataRef data, const char *format, ...) {
    char buffer[1024];
    va_list arguments;
    va_start(arguments, format);
    int length = vsnprintf(buffer, sizeof(buffer), format, arguments);
    va_end(arguments);
    CFDataAppendBytes(data, (const UInt8 *)buffer, length);
}

static CGPDFDocumentRef createDocument(int encrypted) {
    CFMutableDataRef data = CFDataCreateMutable(NULL, 0);
    CFIndex offsets[4];
    int count = encrypted ? 4 : 3;
    append(data, "%%PDF-1.4\n");
    offsets[0] = CFDataGetLength(data);
    append(data, "1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n");
    offsets[1] = CFDataGetLength(data);
    append(data, "2 0 obj\n<< /Type /Pages /Kids [3 0 R] /Count 1 >>\nendobj\n");
    offsets[2] = CFDataGetLength(data);
    append(data, "3 0 obj\n<< /Type /Page /Parent 2 0 R /MediaBox [0 0 100 100] >>\nendobj\n");
    if (encrypted) {
        offsets[3] = CFDataGetLength(data);
        append(data, "4 0 obj\n<< /Filter /Standard /V 1 /R 2 /P -4\n"
                     "/O <92FE0F4454AD4C9644693F33C07CB54F587DCE1E2682FE9ECEA6107A1EF630DD>\n"
                     "/U <A2D98DD93474875EC95C60445C51FE1DF35FFAAC7DA1BACA629058B1C08A8E39> >>\nendobj\n");
    }
    CFIndex xref = CFDataGetLength(data);
    append(data, "xref\n0 %d\n0000000000 65535 f \n", count + 1);
    for (int i = 0; i < count; i++)
        append(data, "%010ld 00000 n \n", (long)offsets[i]);
    append(data, "trailer\n<< /Size %d /Root 1 0 R", count + 1);
    if (encrypted)
        append(data, " /Encrypt 4 0 R /ID [<000102030405060708090A0B0C0D0E0F> <000102030405060708090A0B0C0D0E0F>]");
    append(data, " >>\nstartxref\n%ld\n%%%%EOF\n", (long)xref);

    CGDataProviderRef provider = CGDataProviderCreateWithCFData(data);
    CGPDFDocumentRef document = CGPDFDocumentCreateWithProvider(provider);
    CGDataProviderRelease(provider);
    CFRelease(data);
    return document;
}

int main(void) {
    int failures = 0;

    CGPDFDocumentRef plain = createDocument(0);
    if (plain == NULL) {
        printf("FAIL: the unencrypted document did not open\n");
        return 1;
    }
    if (CGPDFDocumentIsEncrypted(plain)) {
        printf("FAIL: an unencrypted document is reported as encrypted\n");
        failures++;
    }
    if (!CGPDFDocumentIsUnlocked(plain)) {
        printf("FAIL: an unencrypted document is reported as locked\n");
        failures++;
    }
    CGPDFDocumentRelease(plain);

    CGPDFDocumentRef locked = createDocument(1);
    if (locked == NULL) {
        printf("FAIL: the encrypted document did not open\n");
        return failures + 1;
    }
    if (!CGPDFDocumentIsEncrypted(locked)) {
        printf("FAIL: a document with /Encrypt is reported as not encrypted\n");
        failures++;
    }
    if (CGPDFDocumentIsUnlocked(locked)) {
        printf("FAIL: a document with a user password is reported as unlocked before any password\n");
        failures++;
    }
    CGPDFDocumentRelease(locked);

    if (failures)
        return failures;
    puts("PDF encryption and lock state passed");
    return 0;
}
