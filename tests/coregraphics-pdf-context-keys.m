// Contract: Apple CoreGraphics documentation pages of kCGPDFContextSubject,
// kCGPDFContextCreatePDFA, kCGPDFContextOutputIntent, kCGPDFXInfo,
// kCGPDFXOutputConditionIdentifier, kCGPDFXOutputIntentSubtype and
// kCGPDFXDestinationOutputProfile: each is declared as extern CFStringRef const.
// The pages do not state the string values, so none is pinned here (the values
// are GUESS, listed in the commit message): the checks are that each constant
// exists, is a non-empty CFString, and differs from the others of the set and
// from the existing PDF context keys, so one can be used as a dictionary key
// without colliding with another.
// Exit codes: 5 a new key is not defined, 10 + i for the i-th new key that is NULL,
// 30 + i not a CFString, 50 + i empty, 70 + i equal to an existing key, 100 + i equal
// to another new key.
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
            if (CFGetTypeID(keys[i]) != CFStringGetTypeID()) return 30 + i;
            if (CFStringGetLength(keys[i]) == 0) return 50 + i;
            for (unsigned j = 0; j < existingCount; j++)
                if (CFEqual(keys[i], existing[j])) return 70 + i;
            for (unsigned j = i + 1; j < count; j++)
                if (CFEqual(keys[i], keys[j])) return 100 + i;
        }
        puts("PDF context subject, PDF/A and PDF/X keys passed");
    }
    return 0;
}
