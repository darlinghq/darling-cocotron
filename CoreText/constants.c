/*
 This file is part of Darling.

 Copyright (C) 2019 Lubos Dolezel

 Darling is free software: you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation, either version 3 of the License, or
 (at your option) any later version.

 Darling is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU General Public License for more details.

 You should have received a copy of the GNU General Public License
 along with Darling.  If not, see <http://www.gnu.org/licenses/>.
*/

#include <CoreFoundation/CoreFoundation.h>
#include <CoreFoundation/CFString.h>
#include <CoreGraphics/CGBase.h>

const CFStringRef kCTFontAttributeName = CFSTR("NSFont");
const CFStringRef kCTFontSymbolicTrait = CFSTR("NSCTFontSymbolicTrait");
const CFStringRef kCTForegroundColorFromContextAttributeName = CFSTR("CTForegroundColorFromContext");
const CFStringRef kCTStrokeWidthAttributeName = CFSTR("NSStrokeWidth");
const CFStringRef kCTForegroundColorAttributeName = CFSTR("CTForegroundColor");
const CFStringRef kCTParagraphStyleAttributeName = CFSTR("NSParagraphStyle");
const CFStringRef kCTGlyphInfoAttributeName = CFSTR("NSGlyphInfo");
const CFStringRef kCTKernAttributeName = CFSTR("CTKernAttributeName");
// the string values of the next two are those of macOS 10.14.4 and 26.7.3 (printed from the constants)
const CFStringRef kCTLanguageAttributeName = CFSTR("NSLanguage");
const CFStringRef kCTTypesetterOptionForcedEmbeddingLevel = CFSTR("CTTypesetterOptionForcedEmbeddingLevel");
// The same attribute as AppKit's NSVerticalGlyphFormAttributeName (so documented), whose string,
// "CTVerticalForms", was read on macOS 26.7.3 and 10.14 (see appkit-attribute-name-constants.m).
const CFStringRef kCTVerticalFormsAttributeName = CFSTR("CTVerticalForms");

// Documented attribute names (CTStringAttributes.h, CTTextTab.h) that were missing. The SDK headers give the names
// and types but not the strings; the strings were read from the exported constants on macOS 26.7.3 and on 10.14.4
// (black-box observation; see the test that pins them).
const CFStringRef kCTTrackingAttributeName = CFSTR("CTTracking");
const CFStringRef kCTHorizontalInVerticalFormsAttributeName = CFSTR("CTHorizontalInVerticalForms");
const CFStringRef kCTStrokeColorAttributeName = CFSTR("CTStrokeColor");
const CFStringRef kCTWritingDirectionAttributeName = CFSTR("NSWritingDirection");
const CFStringRef kCTTabColumnTerminatorsAttributeName = CFSTR("NSTabColumnTerminatorsAttributeName");
const CFStringRef kCTFontWeightTrait = CFSTR("NSCTFontWeightTrait");
const CFStringRef kCTFontWidthTrait = CFSTR("NSCTFontWidthTrait");
const CFStringRef kCTFontSlantTrait = CFSTR("NSCTFontSlantTrait");
const CFStringRef kCTFontOpenTypeFeatureTag = CFSTR("CTFeatureOpenTypeTag");
const CFStringRef kCTFontOpenTypeFeatureValue = CFSTR("CTFeatureOpenTypeValue");

// Not declared in the public SDK headers, but exported by macOS's CoreText (as an NSString attribute name) and bound by
// applications. The string was read from the exported constant on macOS 26.7.3 (black-box observation; absent on macOS 10.14).
const CFStringRef NSTextEncapsulationAttributeName = CFSTR("NSTextEncapsulation");

// Constants exported by macOS's CoreText but not declared in the SDK headers (CTFontSPI.h and
// CTLineSPI.h declare them), and kCTFontOpticalSizeAttribute, which CTFontDescriptor.h declares.
// Every value was read from the exported constant on macOS 26.7.3, and agrees on macOS 10.14.4 for
// the constants that release exports (black-box observation). Not on 10.14.4: kCTFontGradeTrait,
// kCTFontIgnoreLegibilityWeightAttribute, kCTFontSizeCategoryAttribute,
// kCTFontUIFontDesignMonospaced, kCTFontUIFontDesignSerif, kCTFontUnscaledTrackingAttribute and the
// widths other than Condensed, Standard and Expanded (which 10.14.4 holds as single-precision values).
// Test: tests/coretext-spi-constants.c
const CFStringRef kCTFontDescriptorTextStyleAttribute = CFSTR("NSCTFontUIUsageAttribute");
const CFStringRef kCTFontUIFontDesignTrait = CFSTR("NSCTFontUIFontDesignTrait");
const CFStringRef kCTFontUIFontDesignDefault = CFSTR("NSCTFontUIFontDesignDefault");
const CFStringRef kCTFontUIFontDesignMonospaced = CFSTR("NSCTFontUIFontDesignMonospaced");
const CFStringRef kCTFontUIFontDesignRounded = CFSTR("NSCTFontUIFontDesignRounded");
const CFStringRef kCTFontUIFontDesignSerif = CFSTR("NSCTFontUIFontDesignSerif");

const CFStringRef kCTUIFontTextStyleTitle0 = CFSTR("UICTFontTextStyleTitle0");
const CFStringRef kCTUIFontTextStyleTitle1 = CFSTR("UICTFontTextStyleTitle1");
const CFStringRef kCTUIFontTextStyleTitle2 = CFSTR("UICTFontTextStyleTitle2");
const CFStringRef kCTUIFontTextStyleTitle3 = CFSTR("UICTFontTextStyleTitle3");
const CFStringRef kCTUIFontTextStyleHeadline = CFSTR("UICTFontTextStyleHeadline");
const CFStringRef kCTUIFontTextStyleSubhead = CFSTR("UICTFontTextStyleSubhead");
const CFStringRef kCTUIFontTextStyleBody = CFSTR("UICTFontTextStyleBody");
const CFStringRef kCTUIFontTextStyleFootnote = CFSTR("UICTFontTextStyleFootnote");
const CFStringRef kCTUIFontTextStyleCaption1 = CFSTR("UICTFontTextStyleCaption1");
const CFStringRef kCTUIFontTextStyleCaption2 = CFSTR("UICTFontTextStyleCaption2");
const CFStringRef kCTUIFontTextStyleTitle4 = CFSTR("UICTFontTextStyleTitle4");
const CFStringRef kCTUIFontTextStyleShortHeadline = CFSTR("UICTFontTextStyleShortHeadline");
const CFStringRef kCTUIFontTextStyleShortBody = CFSTR("UICTFontTextStyleShortBody");
const CFStringRef kCTUIFontTextStyleShortSubhead = CFSTR("UICTFontTextStyleShortSubhead");
const CFStringRef kCTUIFontTextStyleShortFootnote = CFSTR("UICTFontTextStyleShortFootnote");
const CFStringRef kCTUIFontTextStyleShortCaption1 = CFSTR("UICTFontTextStyleShortCaption1");
const CFStringRef kCTUIFontTextStyleTallBody = CFSTR("UICTFontTextStyleTallBody");
const CFStringRef kCTFontContentSizeCategoryL = CFSTR("UICTContentSizeCategoryL");

const CFStringRef kCTFontCSSFamilySerif = CFSTR("serif");
const CFStringRef kCTFontCSSFamilySansSerif = CFSTR("sans-serif");
const CFStringRef kCTFontCSSFamilyCursive = CFSTR("cursive");
const CFStringRef kCTFontCSSFamilyFantasy = CFSTR("fantasy");
const CFStringRef kCTFontCSSFamilyMonospace = CFSTR("monospace");

const CFStringRef kCTFontOpticalSizeAttribute = CFSTR("NSCTFontOpticalSizeAttribute");
const CFStringRef kCTFontReferenceURLAttribute = CFSTR("NSCTFontReferenceURLAttribute");
const CFStringRef kCTFontPostScriptNameAttribute = CFSTR("NSCTFontPostScriptNameAttribute");
const CFStringRef kCTFontUserInstalledAttribute = CFSTR("NSCTFontUserInstalledAttribute");
const CFStringRef kCTFontFallbackOptionAttribute = CFSTR("NSCTFontFallbackOptionAttribute");
const CFStringRef kCTFontCSSWeightAttribute = CFSTR("CTFontCSSWeightAttribute");
const CFStringRef kCTFontCSSWidthAttribute = CFSTR("CTFontCSSWidthAttribute");
const CFStringRef kCTFontGradeTrait = CFSTR("NSCTFontGradeTrait");
const CFStringRef kCTFontIgnoreLegibilityWeightAttribute = CFSTR("CTFontIgnoreLegibilityWeightAttribute");
const CFStringRef kCTFontSizeCategoryAttribute = CFSTR("NSCTFontSizeCategoryAttribute");
const CFStringRef kCTFontTrackAttribute = CFSTR("NSCTFontTrackAttribute");
const CFStringRef kCTFontUnscaledTrackingAttribute = CFSTR("NSCTFontUnscaledTrackingAttribute");
const CFStringRef kCTFontPaletteAttribute = CFSTR("CTFontPaletteAttribute");
const CFStringRef kCTFontPaletteColorsAttribute = CFSTR("CTFontPaletteColorsAttribute");
const CFStringRef kCTFrameMaximumNumberOfLinesAttributeName = CFSTR("CTFrameMaximumNumberOfLines");

const CGFloat kCTFontWeightUltraLight = -0.8f;
const CGFloat kCTFontWeightThin = -0.6f;
const CGFloat kCTFontWeightLight = -0.4f;
const CGFloat kCTFontWeightRegular = 0;
const CGFloat kCTFontWeightMedium = 0.23f;
const CGFloat kCTFontWeightSemibold = 0.3f;
const CGFloat kCTFontWeightBold = 0.4f;
const CGFloat kCTFontWeightHeavy = 0.56f;
const CGFloat kCTFontWeightBlack = 0.62f;

const CGFloat kCTFontWidthUltraCompressed = -0.5;
const CGFloat kCTFontWidthExtraCompressed = -0.4;
const CGFloat kCTFontWidthExtraCondensed = -0.3;
const CGFloat kCTFontWidthCondensed = -0.2;
const CGFloat kCTFontWidthSemiCondensed = -0.1;
const CGFloat kCTFontWidthStandard = 0;
const CGFloat kCTFontWidthSemiExpanded = 0.1;
const CGFloat kCTFontWidthExpanded = 0.2;
const CGFloat kCTFontWidthExtraExpanded = 0.3;
