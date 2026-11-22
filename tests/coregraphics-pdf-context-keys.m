// Contract: the CoreGraphics documentation pages of kCGPDFContextSubject, kCGPDFContextCreatePDFA,
// kCGPDFContextOutputIntent, kCGPDFXInfo, kCGPDFXOutputConditionIdentifier, kCGPDFXOutputIntentSubtype and
// kCGPDFXDestinationOutputProfile declare each as extern CFStringRef const, without the string values. The values
// are pinned to what was observed on macOS 26.7.3 and Mac OS X 10.14.4 (black-box read of the public symbols,
// identical on both; kCGPDFContextCreatePDFA does not exist on 10.14.4, the 26.7.3 value is used): Subject and
// OutputIntent are the symbol names, "CGPDFContextCreatePDFA" for the PDF/A key, and the PDF key names Info,
// OutputConditionIdentifier, S and DestOutputProfile for the four PDF/X keys. The constants must also
// differ from each other and from the existing PDF context keys, so they can be dictionary keys of one dictionary.
// The outline keys (kCGPDFOutlineTitle ...) are pinned here too (same observation).
// Exit codes: 5 a new key is not defined, 10 + i for the i-th new key that is NULL,
// 30 + i not a CFString, 50 + i empty, 70 + i equal to an existing key, 100 + i equal
// to another new key, 120 + i a value that differs from the observed one, 140 + i an outline key that does.
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#include <stdio.h>

extern const CFStringRef kCGPDFContextSubject __attribute__((weak_import));
extern const CFStringRef kCGPDFContextCreatePDFA __attribute__((weak_import));
extern const CFStringRef kCGPDFContextOutputIntent __attribute__((weak_import));
extern const CFStringRef kCGPDFXInfo __attribute__((weak_import));
extern const CFStringRef kCGPDFXOutputConditionIdentifier __attribute__((weak_import));
extern const CFStringRef kCGPDFXOutputIntentSubtype __attribute__((weak_import));
extern const CFStringRef kCGPDFXDestinationOutputProfile __attribute__((weak_import));
extern const CFStringRef kCGPDFOutlineTitle __attribute__((weak_import));
extern const CFStringRef kCGPDFOutlineChildren __attribute__((weak_import));
extern const CFStringRef kCGPDFOutlineDestination __attribute__((weak_import));
extern const CFStringRef kCGPDFOutlineDestinationRect __attribute__((weak_import));

int main(void) {
    @autoreleasepool {
        if (&kCGPDFContextSubject == NULL || &kCGPDFContextCreatePDFA == NULL ||
            &kCGPDFContextOutputIntent == NULL || &kCGPDFXInfo == NULL ||
            &kCGPDFXOutputConditionIdentifier == NULL || &kCGPDFXOutputIntentSubtype == NULL ||
            &kCGPDFXDestinationOutputProfile == NULL) {
            fputs("missing PDF subject, PDF/A or PDF/X key\n", stderr);
            return 5;
        }
        const CFStringRef keys[] = {
            kCGPDFContextSubject,
            kCGPDFContextCreatePDFA,
            kCGPDFContextOutputIntent,
            kCGPDFXInfo,
            kCGPDFXOutputConditionIdentifier,
            kCGPDFXOutputIntentSubtype,
            kCGPDFXDestinationOutputProfile,
        };
        const char *expected[] = {
            "kCGPDFContextSubject", "CGPDFContextCreatePDFA", "kCGPDFContextOutputIntent", "Info",
            "OutputConditionIdentifier", "S", "DestOutputProfile",
        };
        const CFStringRef outline[] = {kCGPDFOutlineTitle, kCGPDFOutlineChildren, kCGPDFOutlineDestination,
                                       kCGPDFOutlineDestinationRect};
        const char *outlineExpected[] = {"Title", "Children", "Destination", "DestinationRect"};
        const CFStringRef existing[] = {
            kCGPDFContextTitle,
            kCGPDFContextAuthor,
            kCGPDFContextCreator,
            kCGPDFContextKeywords,
            kCGPDFContextMediaBox,
            kCGPDFContextOwnerPassword,
            kCGPDFContextUserPassword,
            kCGPDFContextEncryptionKeyLength,
            kCGPDFContextCropBox,
            kCGPDFContextBleedBox,
            kCGPDFContextTrimBox,
            kCGPDFContextArtBox,
        };
        const unsigned count = sizeof(keys) / sizeof(keys[0]);
        const unsigned existingCount = sizeof(existing) / sizeof(existing[0]);
        for (unsigned i = 0; i < count; i++) {
            if (keys[i] == NULL) return 10 + i;
            CFStringRef want = CFStringCreateWithCString(NULL, expected[i], kCFStringEncodingUTF8);
            Boolean same = CFEqual(keys[i], want);
            CFRelease(want);
            if (!same) return 120 + i;
            if (CFGetTypeID(keys[i]) != CFStringGetTypeID()) return 30 + i;
            if (CFStringGetLength(keys[i]) == 0) return 50 + i;
            for (unsigned j = 0; j < existingCount; j++)
                if (CFEqual(keys[i], existing[j])) return 70 + i;
            for (unsigned j = i + 1; j < count; j++)
                if (CFEqual(keys[i], keys[j])) return 100 + i;
        }
        for (unsigned i = 0; i < 4; i++) {
            CFStringRef want = CFStringCreateWithCString(NULL, outlineExpected[i], kCFStringEncodingUTF8);
            Boolean same = outline[i] != NULL && CFEqual(outline[i], want);
            CFRelease(want);
            if (!same) return 140 + i;
        }
        puts("PDF context subject, PDF/A and PDF/X keys passed");
    }
    return 0;
}
