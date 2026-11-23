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
