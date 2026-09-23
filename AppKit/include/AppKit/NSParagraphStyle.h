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

#import <AppKit/NSText.h>

@class NSTextBlock, NSTextList, NSTextTab;

NS_HEADER_AUDIT_BEGIN(nullability, sendability)

#if !__NSPARAGRAPH_STYLE_SHARED_SECTION__
#define __NSPARAGRAPH_STYLE_SHARED_SECTION__ 1

typedef NS_ENUM(NSUInteger, NSLineBreakMode) {
    NSLineBreakByWordWrapping = 0,
    NSLineBreakByCharWrapping,
    NSLineBreakByClipping,
    NSLineBreakByTruncatingHead,
    NSLineBreakByTruncatingTail,
    NSLineBreakByTruncatingMiddle
};

typedef NS_OPTIONS(NSUInteger, NSLineBreakStrategy) {
    NSLineBreakStrategyNone = 0,
    NSLineBreakStrategyPushOut = 1 << 0,
    NSLineBreakStrategyHangulWordPriority = 1 << 1,
    NSLineBreakStrategyStandard = 0xFFFF
};

#endif // !__NSPARAGRAPH_STYLE_SHARED_SECTION__

// The primary interfaces match Apple's declarations member for member: Clang
// rejects a class that two modules define differently.
@interface NSParagraphStyle : NSObject <NSCopying, NSMutableCopying, NSSecureCoding>

@property (class, readonly, copy, NS_NONATOMIC_IOSONLY) NSParagraphStyle *defaultParagraphStyle;

+ (NSWritingDirection)defaultWritingDirectionForLanguage:(nullable NSString *)languageName;

@property (readonly, NS_NONATOMIC_IOSONLY) CGFloat lineSpacing;
@property (readonly, NS_NONATOMIC_IOSONLY) CGFloat paragraphSpacing;

@property (readonly, NS_NONATOMIC_IOSONLY) CGFloat headIndent;
@property (readonly, NS_NONATOMIC_IOSONLY) CGFloat tailIndent;
@property (readonly, NS_NONATOMIC_IOSONLY) CGFloat firstLineHeadIndent;

@property (readonly, NS_NONATOMIC_IOSONLY) CGFloat minimumLineHeight;
@property (readonly, NS_NONATOMIC_IOSONLY) CGFloat maximumLineHeight;

@property (readonly, NS_NONATOMIC_IOSONLY) NSLineBreakMode lineBreakMode;

@property (readonly, NS_NONATOMIC_IOSONLY) NSWritingDirection baseWritingDirection;

@property (readonly, NS_NONATOMIC_IOSONLY) CGFloat lineHeightMultiple;
@property (readonly, NS_NONATOMIC_IOSONLY) CGFloat paragraphSpacingBefore;

@property (readonly, NS_NONATOMIC_IOSONLY) float hyphenationFactor;

@property (readonly, NS_NONATOMIC_IOSONLY) BOOL usesDefaultHyphenation;

@property (readonly,copy, NS_NONATOMIC_IOSONLY) NSArray<NSTextTab *> *tabStops;
@property (readonly, NS_NONATOMIC_IOSONLY) CGFloat defaultTabInterval;

@property (readonly, copy, NS_NONATOMIC_IOSONLY) NSArray<NSTextList *> *textLists;

@property (readonly, NS_NONATOMIC_IOSONLY) BOOL allowsDefaultTighteningForTruncation;

@property (readonly, NS_NONATOMIC_IOSONLY) NSLineBreakStrategy lineBreakStrategy;

@end

@interface NSParagraphStyle (NSParagraphStyleAppKit)
@property (readonly, NS_NONATOMIC_IOSONLY) NSTextAlignment alignment;
@property (readonly, copy, NS_NONATOMIC_IOSONLY) NSArray<__kindof NSTextBlock *> *textBlocks;
@property (readonly) float tighteningFactorForTruncation;
@property (readonly) NSInteger headerLevel;
// Undocumented (TextEdit on macOS 26 sets 0); stored, not used for layout.
@property (readonly) NSInteger horizontalAlignment;
@end

NS_HEADER_AUDIT_END(nullability, sendability)

#import <AppKit/NSMutableParagraphStyle.h>
