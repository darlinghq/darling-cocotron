/* Copyright (c) 2006-2007 Christopher J. W. Lloyd <cjwl@objc.net>

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

// Apple's public NSParagraphStyle declares no instance variables; they live
// here so NSMutableParagraphStyle can still reach them.
@interface NSParagraphStyle () {
@protected
    NSWritingDirection _writingDirection;
    CGFloat _paragraphSpacing;
    CGFloat _paragraphSpacingBefore;
    NSArray *_textBlocks;
    NSArray *_textLists;
    NSInteger _headerLevel;
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
    NSInteger _horizontalAlignment;
    BOOL _usesDefaultHyphenation;
    BOOL _allowsDefaultTighteningForTruncation;
    NSLineBreakStrategy _lineBreakStrategy;
}
+ (NSArray *) _defaultTabStops;
- initWithParagraphStyle: (NSParagraphStyle *) other;
@end
