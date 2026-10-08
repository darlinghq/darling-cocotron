#import <Foundation/Foundation.h>
#import <CoreText/CoreText.h>
#import <CoreGraphics/CoreGraphics.h>
#include <stdio.h>

#define CHECK(condition) do { if (!(condition)) { \
    fprintf(stderr, "failed line %d: %s\n", __LINE__, #condition); return 20; \
} } while (0)

static bool expectedMembership(CFCharacterSetRef set)
{
    return CFCharacterSetIsLongCharacterMember(set, 'A') &&
        CFCharacterSetIsLongCharacterMember(set, 0x1D538) &&
        !CFCharacterSetIsLongCharacterMember(set, 0x1D53A) &&
        !CFCharacterSetIsLongCharacterMember(set, 0x10FFFF) &&
        !CFCharacterSetIsLongCharacterMember(set, 0);
}

int main(int argc, const char **argv)
{
    if (argc != 2) return 2;
    NSAutoreleasePool *outer = [NSAutoreleasePool new];
    NSAutoreleasePool *inner = [NSAutoreleasePool new];
    NSData *data = [NSData dataWithContentsOfFile:[NSString stringWithUTF8String:argv[1]]];
    CHECK(data != nil);
    CGDataProviderRef provider = CGDataProviderCreateWithCFData((CFDataRef)data);
    CHECK(provider != NULL);
    CGFontRef graphics = CGFontCreateWithDataProvider(provider);
    CHECK(graphics != NULL);
    CTFontRef font = CTFontCreateWithGraphicsFont(graphics, 18, NULL, NULL);
    CHECK(font != NULL);
    CFCharacterSetRef first = CTFontCopyCharacterSet(font);
    if (!first) {
        fprintf(stderr, "CTFontCopyCharacterSet returned NULL for a Unicode font\n");
        return 10;
    }
    CHECK(CFGetTypeID(first) == CFCharacterSetGetTypeID());
    CHECK(expectedMembership(first));
    CHECK(CTFontCopyCharacterSet(NULL) == NULL);
    CFMutableCharacterSetRef changed = CFCharacterSetCreateMutableCopy(NULL, first);
    CHECK(changed != NULL);
    CFCharacterSetRemoveCharactersInRange(changed, CFRangeMake('A', 1));
    CFCharacterSetAddCharactersInRange(changed, CFRangeMake(0x1D53A, 1));
    CHECK(!CFCharacterSetIsLongCharacterMember(changed, 'A'));
    CHECK(CFCharacterSetIsLongCharacterMember(changed, 0x1D53A));
    CHECK(expectedMembership(first));
    CFCharacterSetRef second = CTFontCopyCharacterSet(font);
    CHECK(second != NULL && expectedMembership(second));
    CFRelease(changed);
    CFRelease(font);
    CGFontRelease(graphics);
    CGDataProviderRelease(provider);
    [inner drain];
    CHECK(expectedMembership(first) && expectedMembership(second));
    CFRelease(first);
    CHECK(expectedMembership(second));
    CFRelease(second);
    [outer drain];
    puts("Unicode cmap membership, independent copies, and owned lifetime passed");
    return 0;
}
