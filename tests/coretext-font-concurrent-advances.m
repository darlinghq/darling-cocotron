#import <Foundation/Foundation.h>
#import <CoreText/CoreText.h>
#import <CoreGraphics/CoreGraphics.h>
#include <pthread.h>
#include <stdatomic.h>
#include <stdio.h>
#include <string.h>

// CTFonts made from one CGFont share its FreeType face (pixel size and glyph slot). Every thread
// measures glyphs, or builds a glyph path, at its own size and must get the single-threaded answer.

#define THREADS 8
#define ROUNDS 3000
#define GLYPHS 12

static CTFontRef fonts[THREADS];
static CGGlyph glyphs[GLYPHS];
static CGSize expectedAdvances[THREADS][GLYPHS];
static double expectedSums[THREADS];
static CGRect expectedBounds[THREADS];
static atomic_int ready;
static atomic_long mismatches[THREADS];

static void *worker(void *argument)
{
    long index = (long)argument;
    atomic_fetch_add(&ready, 1);
    while (atomic_load(&ready) < THREADS) {}
    for (int round = 0; round < ROUNDS; ++round) {
        // Even threads measure advances, odd threads build the path of glyph 0.
        if (index % 2 == 0) {
            CGSize advances[GLYPHS];
            double sum = CTFontGetAdvancesForGlyphs(fonts[index], kCTFontOrientationHorizontal, glyphs, advances, GLYPHS);
            if (sum != expectedSums[index] || memcmp(advances, expectedAdvances[index], sizeof(advances)) != 0)
                atomic_fetch_add(&mismatches[index], 1);
        } else {
            CGPathRef path = CTFontCreatePathForGlyph(fonts[index], glyphs[0], NULL);
            if (path == NULL || !CGRectEqualToRect(CGPathGetBoundingBox(path), expectedBounds[index]))
                atomic_fetch_add(&mismatches[index], 1);
            if (path != NULL) CGPathRelease(path);
        }
    }
    return NULL;
}

int main(void)
{
    @autoreleasepool {
        CTFontRef base = CTFontCreateWithName(CFSTR("Helvetica"), 10, NULL);
        if (base == NULL) { fputs("no font\n", stderr); return 2; }
        const UniChar characters[GLYPHS] = {'W', 'i', 'g', 'H', 'm', 'l', 'Q', 'x', 'B', 'j', 'M', 'o'};
        if (!CTFontGetGlyphsForCharacters(base, characters, glyphs, GLYPHS)) { fputs("missing glyphs\n", stderr); return 2; }
        for (long i = 0; i < THREADS; ++i) {
            // Different integer sizes: FreeType truncates a fractional size, so these stay distinct.
            fonts[i] = CTFontCreateCopyWithAttributes(base, 9 + 7 * i, NULL, NULL);
            expectedSums[i] = CTFontGetAdvancesForGlyphs(fonts[i], kCTFontOrientationHorizontal, glyphs, expectedAdvances[i], GLYPHS);
            CGPathRef path = CTFontCreatePathForGlyph(fonts[i], glyphs[0], NULL);
            if (path == NULL) { fputs("no glyph path\n", stderr); return 2; }
            expectedBounds[i] = CGPathGetBoundingBox(path);
            CGPathRelease(path);
            // The test only means something if sizes give different answers.
            if (i > 0 && expectedSums[i] == expectedSums[i - 1]) { fputs("sizes not distinguishable\n", stderr); return 2; }
        }
        // The fonts must really share one face, or there is nothing to race on.
        for (long i = 1; i < THREADS; ++i) {
            CGFontRef a = CTFontCopyGraphicsFont(fonts[0], NULL), b = CTFontCopyGraphicsFont(fonts[i], NULL);
            if (a != b) { fputs("fonts do not share a CGFont\n", stderr); return 2; }
            CGFontRelease(a); CGFontRelease(b);
        }
        pthread_t threads[THREADS];
        for (long i = 0; i < THREADS; ++i)
            pthread_create(&threads[i], NULL, worker, (void *)i);
        for (long i = 0; i < THREADS; ++i)
            pthread_join(threads[i], NULL);
        long advanceBad = 0, pathBad = 0;
        for (long i = 0; i < THREADS; ++i)
            (i % 2 == 0 ? &advanceBad : &pathBad)[0] += atomic_load(&mismatches[i]);
        printf("advance mismatches=%ld path mismatches=%ld of %d calls per thread\n", advanceBad, pathBad, ROUNDS);
        if (advanceBad || pathBad) { puts("FAIL"); return 1; }
    }
    puts("PASS");
    return 0;
}
