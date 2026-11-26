/* Copyright (C) 2026 Lubos Dolezel */
/* CoreText line, run, typesetter, paragraph style and frame functions that
 * macOS exports but the SDK does not declare.
 *
 * A line or typesetter made from a character provider lays the text out as
 * one made from the same attributed string does; every piece the provider
 * returns is handed back to the dispose callback. The maximum number of lines
 * frame attribute limits the lines of a frame. NULL arguments give NULL or do
 * nothing. Darling's runs start at their first glyph, so the initial advance
 * is zero. */
#include <CoreText/CoreText.h>
#include <stdio.h>
#include <string.h>

typedef const UniChar *(*CTUniCharProviderCallback)(CFIndex, CFIndex *, CFDictionaryRef *, void *);
typedef void (*CTUniCharDisposeCallback)(const UniChar *, void *);
typedef uint8_t CTCompositionLanguage;
enum { kCTCompositionLanguageNone = 1 };

extern CTLineRef CTLineCreateWithUniCharProvider(CTUniCharProviderCallback, CTUniCharDisposeCallback, void *);
extern CTTypesetterRef CTTypesetterCreateWithUniCharProviderAndOptions(CTUniCharProviderCallback,
                                                                       CTUniCharDisposeCallback, void *,
                                                                       CFDictionaryRef);
extern CGSize CTRunGetInitialAdvance(CTRunRef);
extern void CTParagraphStyleSetCompositionLanguage(CTParagraphStyleRef, CTCompositionLanguage);
extern const CFStringRef kCTFrameMaximumNumberOfLinesAttributeName;

static int failures;
#define CHECK(c) do { if (!(c)) { fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #c); failures++; } } while (0)

/* Supplies the text in pieces of at most three characters. */
typedef struct {
    const UniChar *text;
    CFIndex length;
    CFDictionaryRef attributes;
    int provided, disposed;
} Provider;

static const UniChar *provide(CFIndex index, CFIndex *count, CFDictionaryRef *attributes, void *refCon) {
    Provider *provider = refCon;
    if (index >= provider->length)
        return NULL;
    *count = provider->length - index < 3 ? provider->length - index : 3;
    *attributes = provider->attributes;
    provider->provided++;
    return provider->text + index;
}

static void dispose(const UniChar *characters, void *refCon) {
    ((Provider *) refCon)->disposed++;
}

int main(void) {
    CTFontRef font = CTFontCreateWithName(CFSTR("DejaVu Sans"), 16, NULL);
    CHECK(font != NULL);
    if (font == NULL)
        return 1;
    CFDictionaryRef attributes = CFDictionaryCreate(NULL, (const void **) &kCTFontAttributeName,
                                                    (const void **) &font, 1, &kCFTypeDictionaryKeyCallBacks,
                                                    &kCFTypeDictionaryValueCallBacks);
    static const UniChar text[] = { 'H', 'e', 'l', 'l', 'o', ' ', 'w', 'o', 'r', 'l', 'd' };
    const CFIndex length = sizeof(text) / sizeof(text[0]);
    CFStringRef string = CFStringCreateWithCharacters(NULL, text, length);
    CFAttributedStringRef attributed = CFAttributedStringCreate(NULL, string, attributes);

    Provider provider = { text, length, attributes, 0, 0 };
    CTLineRef fromProvider = CTLineCreateWithUniCharProvider(provide, dispose, &provider);
    CTLineRef fromString = CTLineCreateWithAttributedString(attributed);
    CHECK(fromProvider != NULL && fromString != NULL);
    /* every piece was asked for; macOS 26.7.3 hands them back to dispose when
     * the line is released (Darling, which copies them, may do it sooner) */
    CHECK(provider.provided == 4);
    if (fromProvider != NULL && fromString != NULL) {
        CHECK(CTLineGetStringRange(fromProvider).length == length);
        CHECK(CTLineGetGlyphCount(fromProvider) == CTLineGetGlyphCount(fromString));
        double a = CTLineGetTypographicBounds(fromProvider, NULL, NULL, NULL);
        double b = CTLineGetTypographicBounds(fromString, NULL, NULL, NULL);
        CHECK(a > 0 && a == b);
        CFArrayRef runs = CTLineGetGlyphRuns(fromProvider);
        CHECK(CFArrayGetCount(runs) >= 1);
        for (CFIndex i = 0; i < CFArrayGetCount(runs); i++) {
            CGSize initial = CTRunGetInitialAdvance((CTRunRef) CFArrayGetValueAtIndex(runs, i));
            CHECK(initial.width == 0 && initial.height == 0);
        }
    }
    if (fromProvider) CFRelease(fromProvider);
    CHECK(provider.disposed == 4);
    if (fromString) CFRelease(fromString);
    CGSize none = CTRunGetInitialAdvance(NULL);
    CHECK(none.width == 0 && none.height == 0);

    /* without a dispose callback, and a typesetter */
    provider.provided = provider.disposed = 0;
    CTTypesetterRef typesetter = CTTypesetterCreateWithUniCharProviderAndOptions(provide, NULL, &provider, NULL);
    CHECK(typesetter != NULL && provider.disposed == 0);
    if (typesetter != NULL) {
        CTLineRef line = CTTypesetterCreateLine(typesetter, CFRangeMake(0, 5));
        CHECK(line != NULL && CTLineGetStringRange(line).length == 5);
        if (line) CFRelease(line);
        CHECK(CTTypesetterSuggestLineBreak(typesetter, 0, 1000) == length);
        CFRelease(typesetter);
    }

    /* an empty text gives an empty line; no provider gives nothing */
    Provider empty = { text, 0, attributes, 0, 0 };
    CTLineRef emptyLine = CTLineCreateWithUniCharProvider(provide, dispose, &empty);
    CHECK(emptyLine == NULL || CTLineGetGlyphCount(emptyLine) == 0);
    if (emptyLine) CFRelease(emptyLine);
    CHECK(CTLineCreateWithUniCharProvider(NULL, dispose, &provider) == NULL);
    CHECK(CTTypesetterCreateWithUniCharProviderAndOptions(NULL, NULL, NULL, NULL) == NULL);

    /* the composition language is accepted and changes no other value */
    CTParagraphStyleRef style = CTParagraphStyleCreate(NULL, 0);
    CHECK(style != NULL);
    CTParagraphStyleSetCompositionLanguage(style, kCTCompositionLanguageNone);
    CTTextAlignment alignment = 99;
    CHECK(CTParagraphStyleGetValueForSpecifier(style, kCTParagraphStyleSpecifierAlignment,
                                               sizeof(alignment), &alignment));
    CHECK(alignment == kCTTextAlignmentNatural);
    CTParagraphStyleSetCompositionLanguage(NULL, kCTCompositionLanguageNone);
    CFRelease(style);

    /* frames: a line limit */
    static const UniChar words[] = { 'o', 'n', 'e', ' ', 't', 'w', 'o', ' ', 't', 'h', 'r', 'e', 'e', ' ',
                                     'f', 'o', 'u', 'r', ' ', 'f', 'i', 'v', 'e' };
    CFStringRef wordString = CFStringCreateWithCharacters(NULL, words, sizeof(words) / sizeof(words[0]));
    CFAttributedStringRef wordText = CFAttributedStringCreate(NULL, wordString, attributes);
    CTFramesetterRef framesetter = CTFramesetterCreateWithAttributedString(wordText);
    CHECK(framesetter != NULL);
    if (framesetter != NULL) {
        int two = 2;
        CFNumberRef twoNumber = CFNumberCreate(NULL, kCFNumberIntType, &two);
        CFDictionaryRef limit = CFDictionaryCreate(NULL, (const void **) &kCTFrameMaximumNumberOfLinesAttributeName,
                                                   (const void **) &twoNumber, 1, &kCFTypeDictionaryKeyCallBacks,
                                                   &kCFTypeDictionaryValueCallBacks);
        CFRange fit, unlimitedFit;
        CGSize unlimited = CTFramesetterSuggestFrameSizeWithConstraints(framesetter, CFRangeMake(0, 0), NULL,
                                                                        CGSizeMake(45, 10000), &unlimitedFit);
        CGSize limited = CTFramesetterSuggestFrameSizeWithConstraints(framesetter, CFRangeMake(0, 0), limit,
                                                                      CGSizeMake(45, 10000), &fit);
        CHECK(unlimited.height > 0 && limited.height > 0 && limited.height < unlimited.height);
        /* observed on macOS 26.7.3: the last allowed line takes the rest of the
         * text, so all of it is reported as fitting */
        CHECK(fit.location == 0 && fit.length == unlimitedFit.length);
        CGPathRef path = CGPathCreateWithRect(CGRectMake(0, 0, 45, 10000), NULL);
        CTFrameRef frame = CTFramesetterCreateFrame(framesetter, CFRangeMake(0, 0), path, limit);
        CHECK(frame != NULL);
        if (frame != NULL) {
            CHECK(CFArrayGetCount(CTFrameGetLines(frame)) == 2);
            CHECK(CTFrameGetVisibleStringRange(frame).length == fit.length);
            CFRelease(frame);
        }
        /* 0 is no limit */
        int zero = 0;
        CFNumberRef zeroNumber = CFNumberCreate(NULL, kCFNumberIntType, &zero);
        CFDictionaryRef noLimit = CFDictionaryCreate(NULL, (const void **) &kCTFrameMaximumNumberOfLinesAttributeName,
                                                     (const void **) &zeroNumber, 1, &kCFTypeDictionaryKeyCallBacks,
                                                     &kCFTypeDictionaryValueCallBacks);
        CTFramesetterSuggestFrameSizeWithConstraints(framesetter, CFRangeMake(0, 0), noLimit,
                                                     CGSizeMake(45, 10000), &fit);
        CHECK(fit.length == unlimitedFit.length);
        CFRelease(noLimit);
        CFRelease(zeroNumber);
        CGPathRelease(path);
        CFRelease(limit);
        CFRelease(twoNumber);
        CFRelease(framesetter);
    }
    CFRelease(wordText);
    CFRelease(wordString);

    CFRelease(attributed);
    CFRelease(string);
    CFRelease(attributes);
    CFRelease(font);
    printf(failures ? "FAILED\n" : "PASS\n");
    return failures != 0;
}
