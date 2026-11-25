/* Copyright (c) 2007 Christopher J. W. Lloyd

Permission is hereby granted, free of charge, to any person obtaining a copy of
this software and associated documentation files (the "Software"), to deal in
the Software without restriction, including without limitation the rights to
use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
the Software, and to permit persons to whom the Software is furnished to do so,
subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */
#import <AppKit/AppKitExport.h>
#import <AppKit/AppKitIvarLayout.h>
#import <Foundation/NSObject.h>

APPKIT_EXPORT NSString *const NSTextListMarkerDecimal;
APPKIT_EXPORT NSString *const NSTextListMarkerDisc;
APPKIT_EXPORT NSString *const NSTextListMarkerHyphen;
APPKIT_EXPORT NSString *const NSTextListMarkerBox;
APPKIT_EXPORT NSString *const NSTextListMarkerCheck;
APPKIT_EXPORT NSString *const NSTextListMarkerCircle;
APPKIT_EXPORT NSString *const NSTextListMarkerDiamond;
APPKIT_EXPORT NSString *const NSTextListMarkerSquare;
APPKIT_EXPORT NSString *const NSTextListMarkerLowercaseHexadecimal;
APPKIT_EXPORT NSString *const NSTextListMarkerUppercaseHexadecimal;
APPKIT_EXPORT NSString *const NSTextListMarkerOctal;
APPKIT_EXPORT NSString *const NSTextListMarkerLowercaseAlpha;
APPKIT_EXPORT NSString *const NSTextListMarkerUppercaseAlpha;
APPKIT_EXPORT NSString *const NSTextListMarkerLowercaseLatin;
APPKIT_EXPORT NSString *const NSTextListMarkerUppercaseLatin;
APPKIT_EXPORT NSString *const NSTextListMarkerLowercaseRoman;
APPKIT_EXPORT NSString *const NSTextListMarkerUppercaseRoman;

enum { NSTextListPrependEnclosingMarker = 0x01 };

#define _NS_SIDE_NSTextList 0, 1,
#define _NS_HAS_EXTRA_IVARS_NSTextList 1
// Legacy ObjC ABI (i386): instance size must stay 20, Apple's. Add new state
// to the extra struct, never as an ivar.
@interface NSTextList : NSObject {
    NSString *_markerFormat;
    unsigned _options;
    NS_LEGACY_IVAR_PAD(_NSTextListReserved, 8)
    NS_EXTRA_IVARS_BEGIN(NSTextList)
        NSInteger _startingItemNumber;
    NS_SIDE_IVARS_END(NSTextList)
}

- initWithMarkerFormat: (NSString *) format options: (unsigned) options;

- (NSString *) markerFormat;
- (unsigned) listOptions;

- (NSString *) markerForItemNumber: (int) index;

// the number of the list's first item; 1 unless set
@property NSInteger startingItemNumber;

@end
