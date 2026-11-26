/*
 * Copyright (C) 2026 Lubos Dolezel
 * SPDX-License-Identifier: GPL-3.0-or-later
 */
// NSFontDescriptor and CTFontDescriptorRef are toll-free bridged: an NSFontDescriptor works with the CoreText
// descriptor functions, and a CoreText descriptor answers NSFontDescriptor's messages. WebKit relies on the first
// when it resolves the CSS system font shorthands (it gives -[NSFont fontDescriptor] to
// CTFontDescriptorCopyAttribute()). Observed on macOS 26.7.3 x86_64, where this test passes:
//  - the size of a system font's descriptor is a number, from AppKit and from CoreText;
//  - CoreText gives its name and its traits, whose weight is on CoreText's scale (0 for the regular system font,
//    more for the bold one);
//  - CTFontCreateWithFontDescriptor() makes a font of the descriptor's size from it;
//  - a descriptor made with CoreText gives its point size, attributes and name to NSFontDescriptor's messages.
#import <AppKit/AppKit.h>
#import <CoreText/CoreText.h>
#include <stdio.h>

static int failures;
#define CHECK(cond, what) do { int ok_ = (cond); printf("%s: %s\n", ok_ ? "PASS" : "FAIL", what); if (!ok_) failures++; } while (0)

static double number(CFTypeRef value) {
    double result = -1000;
    if (value != NULL && CFGetTypeID(value) == CFNumberGetTypeID())
        CFNumberGetValue((CFNumberRef) value, kCFNumberDoubleType, &result);
    return result;
}

int main(void) {
    @autoreleasepool {
        NSFontDescriptor *regular = [NSFont systemFontOfSize: 11].fontDescriptor;
        NSFontDescriptor *bold = [NSFont boldSystemFontOfSize: 13].fontDescriptor;
        CTFontDescriptorRef ctRegular = (CTFontDescriptorRef) regular, ctBold = (CTFontDescriptorRef) bold;

        id size = [regular objectForKey: NSFontSizeAttribute];
        CHECK([size isKindOfClass: [NSNumber class]] && [size doubleValue] == 11, "the descriptor's size is a number");

        CFTypeRef ctSize = CTFontDescriptorCopyAttribute(ctRegular, kCTFontSizeAttribute);
        CHECK(number(ctSize) == 11, "CoreText gives an NSFontDescriptor's size");
        if (ctSize) CFRelease(ctSize);
        ctSize = CTFontDescriptorCopyAttribute(ctBold, kCTFontSizeAttribute);
        CHECK(number(ctSize) == 13, "CoreText gives the bold system font's size");
        if (ctSize) CFRelease(ctSize);

        CFTypeRef name = CTFontDescriptorCopyAttribute(ctRegular, kCTFontNameAttribute);
        CHECK(name != NULL && CFGetTypeID(name) == CFStringGetTypeID() && CFStringGetLength((CFStringRef) name) > 0,
              "CoreText gives an NSFontDescriptor's name");
        if (name) CFRelease(name);

        CFDictionaryRef traits = CTFontDescriptorCopyAttribute(ctRegular, kCTFontTraitsAttribute);
        double regularWeight = traits ? number(CFDictionaryGetValue(traits, kCTFontWeightTrait)) : -1000;
        if (traits) CFRelease(traits);
        traits = CTFontDescriptorCopyAttribute(ctBold, kCTFontTraitsAttribute);
        double boldWeight = traits ? number(CFDictionaryGetValue(traits, kCTFontWeightTrait)) : -1000;
        if (traits) CFRelease(traits);
        CHECK(regularWeight == 0, "the regular system font's weight trait is 0");
        CHECK(boldWeight > 0 && boldWeight <= 1, "the bold system font's weight trait is on CoreText's scale");

        CTFontRef font = CTFontCreateWithFontDescriptor(ctRegular, 0, NULL);
        CHECK(font != NULL && CTFontGetSize(font) == 11, "CoreText makes a font of the descriptor's size");
        if (font) CFRelease(font);

        CTFontDescriptorRef helvetica = CTFontDescriptorCreateWithNameAndSize(CFSTR("Helvetica"), 14);
        NSFontDescriptor *bridged = (NSFontDescriptor *) helvetica;
        CHECK(bridged.pointSize == 14, "a CoreText descriptor gives its point size");
        CHECK([[bridged objectForKey: NSFontNameAttribute] isEqual: @"Helvetica"], "a CoreText descriptor gives its name");
        CHECK([[bridged.fontAttributes objectForKey: NSFontSizeAttribute] doubleValue] == 14, "a CoreText descriptor gives its attributes");
        CFRelease(helvetica);
    }
    printf("%s\n", failures ? "FAILED" : "ALL PASSED");
    return failures != 0;
}
