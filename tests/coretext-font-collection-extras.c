/* Copyright (C) 2026 Lubos Dolezel */
/* Mutable font collections, exclusion descriptors, sorting with a callback,
 * CTFontManagerCreateFontDescriptorsFromURL and CTGetCoreTextVersion. */
#include <CoreText/CoreText.h>
#include <stdio.h>

static int failures;
#define CHECK(c) do { if (!(c)) { fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #c); failures++; } } while (0)

static CFComparisonResult byName(CTFontDescriptorRef a, CTFontDescriptorRef b, void *refCon) {
    int *calls = refCon;
    (*calls)++;
    CFStringRef na = CTFontDescriptorCopyAttribute(a, kCTFontNameAttribute);
    CFStringRef nb = CTFontDescriptorCopyAttribute(b, kCTFontNameAttribute);
    CFComparisonResult r = na && nb ? CFStringCompare(nb, na, 0) : kCFCompareEqualTo;  /* descending */
    if (na) CFRelease(na);
    if (nb) CFRelease(nb);
    return r;
}

int main(void) {
    CHECK(CTGetCoreTextVersion() != 0);

    CTFontCollectionRef all = CTFontCollectionCreateFromAvailableFonts(NULL);
    CHECK(all != NULL);
    CHECK(CTFontCollectionCopyQueryDescriptors(all) == NULL);

    CTMutableFontCollectionRef copy = CTFontCollectionCreateMutableCopy(all);
    CHECK(copy != NULL && (void *) copy != (void *) all);

    CTFontDescriptorRef query = CTFontDescriptorCreateWithAttributes(
            CFDictionaryCreate(NULL, NULL, NULL, 0, &kCFTypeDictionaryKeyCallBacks,
                               &kCFTypeDictionaryValueCallBacks));
    CFArrayRef queries = CFArrayCreate(NULL, (const void **) &query, 1, &kCFTypeArrayCallBacks);
    CTFontCollectionSetQueryDescriptors(copy, queries);
    CFArrayRef got = CTFontCollectionCopyQueryDescriptors(copy);
    CHECK(got != NULL && CFArrayGetCount(got) == 1);
    CHECK(CTFontCollectionCopyQueryDescriptors(all) == NULL);   /* the original is unchanged */

    CFArrayRef matches = CTFontCollectionCreateMatchingFontDescriptors(copy);
    CHECK(matches != NULL && CFArrayGetCount(matches) > 1);

    int calls = 0;
    CFArrayRef sorted = CTFontCollectionCreateMatchingFontDescriptorsSortedWithCallback(copy, byName, &calls);
    CHECK(sorted != NULL && CFArrayGetCount(sorted) == CFArrayGetCount(matches));
    CHECK(calls > 0);
    CFStringRef n0 = CTFontDescriptorCopyAttribute(CFArrayGetValueAtIndex(sorted, 0), kCTFontNameAttribute);
    CFStringRef nl = CTFontDescriptorCopyAttribute(
            CFArrayGetValueAtIndex(sorted, CFArrayGetCount(sorted) - 1), kCTFontNameAttribute);
    CHECK(n0 && nl && CFStringCompare(n0, nl, 0) != kCFCompareLessThan);

    // Excluding one face removes it from the matches.
    CTFontDescriptorRef first = CFArrayGetValueAtIndex(matches, 0);
    CFArrayRef exclusions = CFArrayCreate(NULL, (const void **) &first, 1, &kCFTypeArrayCallBacks);
    CTFontCollectionSetExclusionDescriptors(copy, exclusions);
    CFArrayRef exGot = CTFontCollectionCopyExclusionDescriptors(copy);
    CHECK(exGot != NULL && CFArrayGetCount(exGot) == 1);
    CFArrayRef fewer = CTFontCollectionCreateMatchingFontDescriptors(copy);
    CHECK(fewer == NULL || CFArrayGetCount(fewer) < CFArrayGetCount(matches));

    // From a file URL.
    CHECK(CTFontManagerCreateFontDescriptorsFromURL(NULL) == NULL);
    CFURLRef missing = CFURLCreateWithFileSystemPath(NULL, CFSTR("/nonexistent/font.ttf"),
                                                     kCFURLPOSIXPathStyle, false);
    CHECK(CTFontManagerCreateFontDescriptorsFromURL(missing) == NULL);

    puts(failures ? "FAILED" : "PASS");
    return failures != 0;
}
