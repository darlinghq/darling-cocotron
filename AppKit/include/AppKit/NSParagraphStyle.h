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

typedef enum {
    NSLineBreakByWordWrapping,
    NSLineBreakByCharWrapping,
    NSLineBreakByClipping,
    NSLineBreakByTruncatingHead,
    NSLineBreakByTruncatingTail,
    NSLineBreakByTruncatingMiddle
} NSLineBreakMode;

@interface NSParagraphStyle : NSObject <NSCopying, NSMutableCopying> {
    NSWritingDirection _writingDirection;
    CGFloat _paragraphSpacing;
    CGFloat _paragraphSpacingBefore;
    NSArray *_textBlocks;
    NSArray *_textLists;
    int _headerLevel;
    CGFloat _firstLineHeadIndent;
    CGFloat _headIndent;
    CGFloat _tailIndent;
    NSTextAlignment _alignment;
    NSLineBreakMode _lineBreakMode;
    CGFloat _minimumLineHeight;
    CGFloat _maximumLineHeight;
    CGFloat _lineHeightMultiple;
    CGFloat _lineSpacing;
    CGFloat _defaultTabInterval;
    NSMutableArray *_tabStops;
    float _hyphenationFactor;
    float _tighteningFactorForTruncation;
}

+ (NSParagraphStyle *) defaultParagraphStyle;

+ (NSWritingDirection)defaultWritingDirectionForLanguage: (NSString *)languageName;

- (NSWritingDirection) baseWritingDirection;

- (CGFloat) paragraphSpacing;
- (CGFloat) paragraphSpacingBefore;

- (NSArray *) textBlocks;
- (NSArray *) textLists;

- (int) headerLevel;

- (CGFloat) firstLineHeadIndent;
- (CGFloat) headIndent;
- (CGFloat) tailIndent;

- (NSTextAlignment) alignment;
- (NSLineBreakMode) lineBreakMode;

- (CGFloat) minimumLineHeight;
- (CGFloat) maximumLineHeight;
- (CGFloat) lineHeightMultiple;
- (CGFloat) lineSpacing;

- (CGFloat) defaultTabInterval;
- (NSArray *) tabStops;

- (float) hyphenationFactor;
- (float) tighteningFactorForTruncation;

@end

#import <AppKit/NSMutableParagraphStyle.h>
