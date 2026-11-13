#import <CoreGraphics/CGPDFString.h>
#import <Onyx2D/O2PDFString.h>
#include <stdlib.h>

CFStringRef CGPDFStringCopyTextString(CGPDFStringRef string) {
    NSCParameterAssert(string != NULL);
    O2PDFString *pdfString = (O2PDFString *)string;
    const unsigned char *bytes = [pdfString bytes];
    size_t length = [pdfString length];
    if (!length) return CFStringCreateWithCharacters(NULL, NULL, 0);
    UniChar *characters = malloc(length * sizeof(UniChar));
    if (!characters) return NULL;
    size_t count = 0;
    bool valid = true;
    if (length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF) {
        bool needsLowSurrogate = false;
        valid = (length % 2) == 0;
        for (size_t i = 2; valid && i + 1 < length; i += 2) {
            UniChar character = ((UniChar)bytes[i] << 8) | bytes[i + 1];
            bool lowSurrogate = CFStringIsSurrogateLowCharacter(character);
            if (needsLowSurrogate != lowSurrogate) {
                valid = false;
                break;
            }
            needsLowSurrogate = CFStringIsSurrogateHighCharacter(character);
            characters[count++] = character;
        }
        valid = valid && !needsLowSurrogate;
    } else {
        // PDF 1.7 Appendix D.2; 0x8A's Unicode value is corrected by ISO errata.
        static const UniChar accents[] = {0x02D8, 0x02C7, 0x02C6, 0x02D9, 0x02DD, 0x02DB, 0x02DA, 0x02DC};
        static const UniChar symbols[] = {
            0x2022, 0x2020, 0x2021, 0x2026, 0x2014, 0x2013, 0x0192, 0x2044,
            0x2039, 0x203A, 0x2212, 0x2030, 0x201E, 0x201C, 0x201D, 0x2018,
            0x2019, 0x201A, 0x2122, 0xFB01, 0xFB02, 0x0141, 0x0152, 0x0160,
            0x0178, 0x017D, 0x0131, 0x0142, 0x0153, 0x0161, 0x017E
        };
        for (size_t i = 0; i < length; i++) {
            unsigned char byte = bytes[i];
            if ((byte < 0x18 && byte != 0x09 && byte != 0x0A && byte != 0x0D) ||
                byte == 0x7F || byte == 0x9F || byte == 0xAD) {
                valid = false;
                break;
            }
            if (byte >= 0x18 && byte <= 0x1F) characters[count++] = accents[byte - 0x18];
            else if (byte >= 0x80 && byte <= 0x9E) characters[count++] = symbols[byte - 0x80];
            else characters[count++] = byte == 0xA0 ? 0x20AC : byte;
        }
    }
    CFStringRef result = valid ? CFStringCreateWithCharacters(NULL, characters, count) : NULL;
    free(characters);
    return result;
}
