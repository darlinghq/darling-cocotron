// Copyright (C) 2026 Lubos Dolezel
// Attribute names whose strings were corrected or added to match macOS 26.7.3 (black-box observation of the exported constants;
// NSVerticalGlyphFormAttributeName also on macOS 10.14): NSVerticalGlyphFormAttributeName is "CTVerticalForms", and AppKit and
// CoreText export NSParagraphAttachmentAttributeName and NSTextEncapsulationAttributeName. The two latter are in no public header,
// so they are looked up by symbol. Not run in Darling (prepared only).
#import <AppKit/AppKit.h>
#include <dlfcn.h>
#include <stdlib.h>

static void expect(BOOL condition, NSString *message)
{
    if (!condition)
    {
        NSLog(@"FAIL: %@", message);
        exit(1);
    }
}

static void expectSymbol(const char *name, NSString *value)
{
    NSString *const *symbol = (NSString *const *)dlsym(RTLD_DEFAULT, name);
    expect(symbol != NULL, [NSString stringWithFormat:@"%s is exported", name]);
    expect([*symbol isEqualToString:value], [NSString stringWithFormat:@"%s is \"%@\", expected \"%@\"", name, *symbol, value]);
}

int main(void)
{
    @autoreleasepool
    {
        expect([NSVerticalGlyphFormAttributeName isEqualToString:@"CTVerticalForms"],
               [NSString stringWithFormat:@"NSVerticalGlyphFormAttributeName is \"%@\"", NSVerticalGlyphFormAttributeName]);
        expectSymbol("NSVerticalGlyphFormAttributeName", @"CTVerticalForms");
        expectSymbol("NSParagraphAttachmentAttributeName", @"NSTextParagraphAnchoredAttachment");
        expectSymbol("NSTextEncapsulationAttributeName", @"NSTextEncapsulation");
        NSLog(@"appkit-attribute-name-constants: ok");
    }
    return 0;
}
