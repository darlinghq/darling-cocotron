/* Copyright (c) 2006-2007 Christopher J. W. Lloyd

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

#import <AppKit/NSParagraphStyle.h>
#import <AppKit/NSTextTab.h>

NS_HEADER_AUDIT_BEGIN(nullability, sendability)

@interface NSMutableParagraphStyle : NSParagraphStyle

@property (NS_NONATOMIC_IOSONLY) CGFloat lineSpacing;
@property (NS_NONATOMIC_IOSONLY) CGFloat paragraphSpacing;
@property (NS_NONATOMIC_IOSONLY) CGFloat firstLineHeadIndent;
@property (NS_NONATOMIC_IOSONLY) CGFloat headIndent;
@property (NS_NONATOMIC_IOSONLY) CGFloat tailIndent;
@property (NS_NONATOMIC_IOSONLY) NSLineBreakMode lineBreakMode;
@property (NS_NONATOMIC_IOSONLY) CGFloat minimumLineHeight;
@property (NS_NONATOMIC_IOSONLY) CGFloat maximumLineHeight;
@property (NS_NONATOMIC_IOSONLY) NSWritingDirection baseWritingDirection;
@property (NS_NONATOMIC_IOSONLY) CGFloat lineHeightMultiple;
@property (NS_NONATOMIC_IOSONLY) CGFloat paragraphSpacingBefore;
@property (NS_NONATOMIC_IOSONLY) float hyphenationFactor;
@property (readwrite, NS_NONATOMIC_IOSONLY) BOOL usesDefaultHyphenation;
@property (null_resettable, copy, NS_NONATOMIC_IOSONLY) NSArray<NSTextTab *> *tabStops;
@property (NS_NONATOMIC_IOSONLY) CGFloat defaultTabInterval;
@property (NS_NONATOMIC_IOSONLY) BOOL allowsDefaultTighteningForTruncation;
@property (NS_NONATOMIC_IOSONLY) NSLineBreakStrategy lineBreakStrategy;
@property (NS_NONATOMIC_IOSONLY, copy) NSArray<NSTextList *> *textLists;

- (void)addTabStop:(NSTextTab *)anObject;
- (void)removeTabStop:(NSTextTab *)anObject;

- (void)setParagraphStyle:(NSParagraphStyle *)obj;

@end

@interface NSMutableParagraphStyle (NSMutableParagraphStyleAppKit)
@property (NS_NONATOMIC_IOSONLY) NSTextAlignment alignment;
@property (copy, NS_NONATOMIC_IOSONLY) NSArray<__kindof NSTextBlock *> *textBlocks;
@property float tighteningFactorForTruncation;
@property NSInteger headerLevel;
// See -[NSParagraphStyle horizontalAlignment].
@property NSInteger horizontalAlignment;
@end

NS_HEADER_AUDIT_END(nullability, sendability)
